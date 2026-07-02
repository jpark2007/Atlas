/**
 * Atlas — google-sync Edge Function (Deno)  ·  the two-way sync runner
 *
 * Invoked by pg_cron (Task 4) every 5 minutes with the service-role key. For each
 * active google_connections row (oldest last_synced_at first, batched) it:
 *   PULL  Google → Supabase: incremental events.list with the stored sync_token
 *         (410 GONE → full −30d…+365d resync), upserting Google-origin rows and
 *         applying deletions.
 *   PUSH  Supabase → Google: Atlas-origin rows changed since last_synced_at —
 *         insert (write the returned id back) or PATCH — with newest-wins.
 *
 * Single-owner / no-duplicates invariant is backstopped by the DB:
 *   • unique (user_id, google_event_id) where gid is not null  (0006)
 *   • events.google_origin bit                                  (0007)
 *
 * events.google_origin semantics (0007): true ⇒ the runner must NEVER push this
 * row to Google. Set true on a Google-origin insert AND when un-mirroring an
 * Atlas row (its gid nulled after a Google-side delete) so the detached row is
 * never resurrected on Google. That single bit resolves BOTH the delete-vs-
 * un-mirror choice on cancel and the no-resurrection guarantee.
 *
 * Auth: service-role only. The bearer token MUST equal SUPABASE_SERVICE_ROLE_KEY
 * (rejects anon / user JWTs). There is no inbound user to carry a JWT — the cron
 * is the caller.
 *
 * Modes:  POST /functions/v1/google-sync            → run (reads + writes)
 *         POST /functions/v1/google-sync?dryRun=1   → read + log intended writes,
 *                                                      write NOTHING (DB, Google,
 *                                                      or connection rows).
 *
 * Env (SUPABASE_* auto-injected; GOOGLE_* set via `supabase secrets set`):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
 *
 * Deploy: supabase functions deploy google-sync --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const GCAL_BASE = "https://www.googleapis.com/calendar/v3";
const BATCH_LIMIT = 20; // connections processed per invocation (oldest first)
const FULL_WINDOW_BACK_DAYS = 30;
const FULL_WINDOW_FWD_DAYS = 365;
const DAY_MS = 86_400_000;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * The `role` claim of a Supabase JWT, or null if it doesn't decode. Signature is
 * NOT re-checked here — the platform gateway already verifies it before the
 * request reaches this function (an unsigned/forged token gets a gateway 401),
 * so trusting the claim after that gate is safe and is Supabase's own pattern.
 */
function jwtRole(token: string): string | null {
  try {
    const seg = token.split(".")[1];
    if (!seg) return null;
    let b64 = seg.replace(/-/g, "+").replace(/_/g, "/");
    b64 += "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(atob(b64));
    return typeof payload?.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

// ── Google types (only the fields we use) ───────────────────────
interface GTime {
  dateTime?: string;
  date?: string;
}
interface GEvent {
  id?: string;
  status?: string; // "confirmed" | "tentative" | "cancelled"
  summary?: string;
  description?: string;
  start?: GTime;
  end?: GTime;
  updated?: string; // RFC3339 last-modified
}

// A local events row, minimal projection.
interface EventRow {
  id: string;
  google_event_id: string | null;
  google_origin: boolean;
  updated_at: string;
  space_name: string;
  title?: string;
  subtitle?: string;
  start_at?: string;
  end_at?: string;
  is_all_day?: boolean;
  notes?: string | null;
}

interface Connection {
  user_id: string;
  vault_secret_id: string | null;
  calendar_id: string;
  sync_token: string | null;
  last_synced_at: string | null;
}

// Per-user tally returned in the response (never contains tokens).
interface UserResult {
  userId: string;
  status: string;
  inserted: number;
  updated: number;
  deleted: number;
  unmirrored: number;
  pushedNew: number;
  pushedUpdated: number;
  fullResync: boolean;
  error?: string;
}

// ── date helpers (mirror the Mac's GoogleCalendarMapper) ────────
function dateOnlyUTC(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10); // yyyy-MM-dd (UTC)
}

/** Resolve (start, end, isAllDay) from a Google start/end pair; null if unmappable. */
function interval(start?: GTime, end?: GTime): { start: string; end: string; allDay: boolean } | null {
  if (!start || !end) return null;
  if (start.dateTime && end.dateTime) {
    return { start: new Date(start.dateTime).toISOString(), end: new Date(end.dateTime).toISOString(), allDay: false };
  }
  if (start.date && end.date) {
    // yyyy-MM-dd → UTC midnight, matching the Swift allDayFormatter (UTC).
    return { start: new Date(`${start.date}T00:00:00Z`).toISOString(), end: new Date(`${end.date}T00:00:00Z`).toISOString(), allDay: true };
  }
  return null;
}

/** Google write-body for insert/patch (mirrors GoogleCalendarMapper.eventBody). */
function googleEventBody(row: EventRow): Record<string, unknown> {
  const body: Record<string, unknown> = { summary: row.title ?? "" };
  if (row.notes) body.description = row.notes;
  if (row.is_all_day) {
    body.start = { date: dateOnlyUTC(row.start_at!) };
    body.end = { date: dateOnlyUTC(row.end_at!) };
  } else {
    body.start = { dateTime: new Date(row.start_at!).toISOString() };
    body.end = { dateTime: new Date(row.end_at!).toISOString() };
  }
  return body;
}

// ── Google token refresh ────────────────────────────────────────
class InvalidGrantError extends Error {}

async function refreshAccessToken(refreshToken: string, clientId: string, clientSecret: string): Promise<string> {
  const body = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: "refresh_token",
  });
  const res = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  const text = await res.text();
  if (!res.ok) {
    // Google returns 400 { "error": "invalid_grant" } for a revoked/expired token.
    if (text.includes("invalid_grant")) throw new InvalidGrantError("invalid_grant");
    throw new Error(`token refresh ${res.status}: ${text.slice(0, 200)}`);
  }
  const parsed = JSON.parse(text);
  if (!parsed.access_token) throw new Error("token refresh: no access_token");
  return parsed.access_token as string;
}

// ── Google events.list (paged; incremental or full window) ──────
interface ListResult {
  items: GEvent[];
  nextSyncToken: string | null;
  gone: boolean; // 410 → sync token stale, caller must full-resync
}

async function listEvents(accessToken: string, calendarId: string, syncToken: string | null, full: boolean): Promise<ListResult> {
  const items: GEvent[] = [];
  let pageToken: string | undefined;
  let nextSyncToken: string | null = null;

  while (true) {
    const params = new URLSearchParams();
    params.set("singleEvents", "true"); // must stay consistent across incremental calls
    params.set("maxResults", "250");
    if (syncToken && !full) {
      // Incremental: no time bounds / orderBy allowed alongside a syncToken.
      params.set("syncToken", syncToken);
    } else {
      // Full window resync. No orderBy so Google returns a nextSyncToken.
      const now = Date.now();
      params.set("timeMin", new Date(now - FULL_WINDOW_BACK_DAYS * DAY_MS).toISOString());
      params.set("timeMax", new Date(now + FULL_WINDOW_FWD_DAYS * DAY_MS).toISOString());
    }
    if (pageToken) params.set("pageToken", pageToken);

    const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(calendarId)}/events?${params}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (res.status === 410) return { items: [], nextSyncToken: null, gone: true };
    if (!res.ok) throw new Error(`events.list ${res.status}: ${(await res.text()).slice(0, 200)}`);

    const data = await res.json();
    for (const it of (data.items ?? []) as GEvent[]) items.push(it);
    if (data.nextPageToken) {
      pageToken = data.nextPageToken;
      continue;
    }
    nextSyncToken = data.nextSyncToken ?? null;
    break;
  }
  return { items, nextSyncToken, gone: false };
}

// ── One user's sync ─────────────────────────────────────────────
async function syncUser(admin: SupabaseClient, conn: Connection, clientId: string, clientSecret: string, dryRun: boolean): Promise<UserResult> {
  const userId = conn.user_id;
  const runStart = new Date();
  const result: UserResult = {
    userId,
    status: "active",
    inserted: 0,
    updated: 0,
    deleted: 0,
    unmirrored: 0,
    pushedNew: 0,
    pushedUpdated: 0,
    fullResync: false,
  };

  if (!conn.vault_secret_id) throw new Error("connection has no vault_secret_id");

  // 1. Decrypt the refresh token (service-role Vault read) and mint an access token.
  const { data: refreshToken, error: secretErr } = await admin.rpc("read_google_secret", { secret_id: conn.vault_secret_id });
  if (secretErr || !refreshToken) throw new Error("vault read failed");
  const accessToken = await refreshAccessToken(refreshToken as string, clientId, clientSecret);

  // 2. PULL. Incremental when we hold a sync_token; on 410 (or no token) fall
  //    back to a full-window resync.
  let listing: ListResult = { items: [], nextSyncToken: null, gone: false };
  if (conn.sync_token) {
    listing = await listEvents(accessToken, conn.calendar_id, conn.sync_token, false);
  }
  if (!conn.sync_token || listing.gone) {
    listing = await listEvents(accessToken, conn.calendar_id, null, true);
    result.fullResync = true;
  }
  const newSyncToken = listing.nextSyncToken ?? conn.sync_token;

  // Split incoming events into deletions and upserts, keyed by gid.
  interface UpsertVal {
    fields: { start: string; end: string; allDay: boolean };
    title: string;
    notes: string | null;
    googleUpdated: number;
  }
  const cancelledGids: string[] = [];
  const upserts = new Map<string, UpsertVal>();
  for (const ev of listing.items) {
    const gid = ev.id;
    if (!gid) continue;
    if (ev.status === "cancelled") {
      cancelledGids.push(gid);
      continue;
    }
    const iv = interval(ev.start, ev.end);
    if (!iv) continue; // unmappable (e.g. no times) — skip
    upserts.set(gid, {
      fields: iv,
      title: ev.summary ?? "Untitled",
      notes: ev.description ?? null,
      googleUpdated: ev.updated ? new Date(ev.updated).getTime() : runStart.getTime(),
    });
  }

  // Existing local rows for every gid we saw (both upserts and cancellations).
  const seenGids = [...new Set([...upserts.keys(), ...cancelledGids])];
  const existingByGid = new Map<string, EventRow>();
  if (seenGids.length > 0) {
    const { data: rows, error } = await admin
      .from("events")
      .select("id, google_event_id, google_origin, updated_at, space_name")
      .eq("user_id", userId)
      .in("google_event_id", seenGids);
    if (error) throw new Error(`events select failed: ${error.message}`);
    for (const r of (rows ?? []) as EventRow[]) {
      if (r.google_event_id) existingByGid.set(r.google_event_id, r);
    }
  }

  // Default space (the app orders spaces by `sort`; there is no created_at column).
  let defaultSpace: string | null = null;
  const { data: spaceRows } = await admin
    .from("spaces")
    .select("name, sort")
    .eq("user_id", userId)
    .order("sort", { ascending: true })
    .order("name", { ascending: true })
    .limit(1);
  defaultSpace = (spaceRows?.[0]?.name as string | undefined) ?? null;

  // The set of row ids the sync itself wrote this run — excluded from PUSH so a
  // pulled/un-mirrored row is never echoed back to Google in the same pass.
  const syncTouched = new Set<string>();

  // 2a. Deletions (cancelled events).
  const toDelete: string[] = [];
  const toUnmirror: string[] = [];
  for (const gid of cancelledGids) {
    const row = existingByGid.get(gid);
    if (!row) continue;
    syncTouched.add(row.id);
    if (row.google_origin) toDelete.push(row.id); // Google owns it → remove
    else toUnmirror.push(row.id); // Atlas mirror → keep event, detach from Google
  }

  // 2b. Upserts (Google-origin inserts + newest-wins updates).
  const inserts: Record<string, unknown>[] = [];
  const updates: { id: string; patch: Record<string, unknown> }[] = [];
  for (const [gid, u] of upserts) {
    const row = existingByGid.get(gid);
    if (row) {
      syncTouched.add(row.id);
      // Newest-wins: only let Google overwrite when its copy is at least as new.
      if (u.googleUpdated >= new Date(row.updated_at).getTime()) {
        updates.push({
          id: row.id,
          patch: { title: u.title, start_at: u.fields.start, end_at: u.fields.end, is_all_day: u.fields.allDay, notes: u.notes },
        });
      }
      // else: Atlas edit is newer — leave it; PUSH will PATCH it back to Google.
    } else {
      if (!defaultSpace) continue; // no space to file it under — skip insert (space_name is NOT NULL)
      inserts.push({
        id: crypto.randomUUID(),
        user_id: userId,
        space_name: defaultSpace,
        title: u.title,
        subtitle: "Google Calendar",
        start_at: u.fields.start,
        end_at: u.fields.end,
        is_all_day: u.fields.allDay,
        notes: u.notes,
        google_event_id: gid,
        google_origin: true,
      });
    }
  }
  result.inserted = inserts.length;
  result.updated = updates.length;
  result.deleted = toDelete.length;
  result.unmirrored = toUnmirror.length;

  // 3. Apply pull writes (skipped entirely in dryRun).
  if (!dryRun) {
    if (inserts.length > 0) {
      // Idempotent: unique (user_id, google_event_id) makes a re-run a no-op.
      const { error } = await admin.from("events").upsert(inserts, { onConflict: "user_id,google_event_id" });
      if (error) throw new Error(`insert failed: ${error.message}`);
    }
    for (const u of updates) {
      const { error } = await admin.from("events").update(u.patch).eq("id", u.id);
      if (error) throw new Error(`update failed: ${error.message}`);
    }
    if (toDelete.length > 0) {
      const { error } = await admin.from("events").delete().in("id", toDelete);
      if (error) throw new Error(`delete failed: ${error.message}`);
    }
    if (toUnmirror.length > 0) {
      // Detach: null the gid AND mark google_origin so it is never re-pushed.
      const { error } = await admin.from("events").update({ google_event_id: null, google_origin: true }).in("id", toUnmirror);
      if (error) throw new Error(`unmirror failed: ${error.message}`);
    }
  }

  // 4. PUSH. Atlas-origin rows (google_origin=false) changed since last_synced_at.
  //    First run (last_synced_at null) backfills all — parity with the Mac's
  //    backfillEventsToGoogle on toggle-on.
  let pushQ = admin
    .from("events")
    .select("id, google_event_id, google_origin, updated_at, space_name, title, start_at, end_at, is_all_day, notes")
    .eq("user_id", userId)
    .eq("google_origin", false);
  if (conn.last_synced_at) pushQ = pushQ.gt("updated_at", conn.last_synced_at);
  const { data: pushRows, error: pushErr } = await pushQ;
  if (pushErr) throw new Error(`push select failed: ${pushErr.message}`);

  for (const row of (pushRows ?? []) as EventRow[]) {
    if (syncTouched.has(row.id)) continue; // just written by the pull this run
    if (row.google_event_id) {
      // Already mirrored → PATCH (newest-wins: a push candidate is the newer side).
      result.pushedUpdated++;
      if (!dryRun) {
        const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(conn.calendar_id)}/events/${encodeURIComponent(row.google_event_id)}`, {
          method: "PATCH",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify(googleEventBody(row)),
        });
        if (!res.ok && res.status !== 404 && res.status !== 410) {
          throw new Error(`google patch ${res.status}: ${(await res.text()).slice(0, 200)}`);
        }
      }
    } else {
      // Not yet mirrored → create on Google, write the returned id back.
      result.pushedNew++;
      if (!dryRun) {
        const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(conn.calendar_id)}/events`, {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify(googleEventBody(row)),
        });
        if (!res.ok) throw new Error(`google insert ${res.status}: ${(await res.text()).slice(0, 200)}`);
        const created = await res.json();
        if (created.id) {
          const { error } = await admin.from("events").update({ google_event_id: created.id }).eq("id", row.id);
          if (error) throw new Error(`writeback failed: ${error.message}`);
        }
      }
    }
  }

  // 5. Advance the cursor (success only; skipped in dryRun).
  if (!dryRun) {
    const { error } = await admin
      .from("google_connections")
      .update({ sync_token: newSyncToken, last_synced_at: runStart.toISOString(), status: "active", last_error: null })
      .eq("user_id", userId);
    if (error) throw new Error(`connection update failed: ${error.message}`);
  }

  return result;
}

// ── HTTP entry ──────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");
  if (!supabaseUrl || !serviceKey || !clientId || !clientSecret) {
    return json({ error: "Server not configured" }, 500);
  }

  // Service-role only. Accept the exact injected key, or any service_role JWT
  // (the cron sends the service key). Rejects anon (role=anon) and user
  // (role=authenticated) tokens.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token || (token !== serviceKey && jwtRole(token) !== "service_role")) {
    return json({ error: "Forbidden" }, 401);
  }

  const dryRun = new URL(req.url).searchParams.get("dryRun") === "1";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Batch: active connections, oldest last_synced_at first.
  const { data: conns, error: connErr } = await admin
    .from("google_connections")
    .select("user_id, vault_secret_id, calendar_id, sync_token, last_synced_at")
    .eq("status", "active")
    .order("last_synced_at", { ascending: true, nullsFirst: true })
    .limit(BATCH_LIMIT);
  if (connErr) return json({ error: "Failed to load connections" }, 500);

  const results: UserResult[] = [];
  for (const conn of (conns ?? []) as Connection[]) {
    try {
      results.push(await syncUser(admin, conn, clientId, clientSecret, dryRun));
    } catch (e) {
      // Per-user isolation: one failure never blocks the batch.
      const revoked = e instanceof InvalidGrantError;
      const msg = revoked ? "invalid_grant" : String((e as Error)?.message ?? e).slice(0, 500);
      if (!dryRun) {
        await admin
          .from("google_connections")
          .update({ status: revoked ? "revoked" : "error", last_error: msg })
          .eq("user_id", conn.user_id);
      }
      results.push({
        userId: conn.user_id,
        status: revoked ? "revoked" : "error",
        inserted: 0, updated: 0, deleted: 0, unmirrored: 0, pushedNew: 0, pushedUpdated: 0,
        fullResync: false, error: msg,
      });
    }
  }

  return json({ ok: true, dryRun, count: results.length, users: results });
});
