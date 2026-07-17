/**
 * Atlas — google-connect Edge Function (Deno)
 *
 * Manages a user's Google Calendar CONNECTIONS (multi-account, design 2026-07-15).
 * Each connection is a google_connections row: (google login, calendar_id 'primary',
 * user's name, destination space). The refresh token lives in Supabase Vault
 * (service-role only); the row points at it by vault_secret_id — the token value
 * never returns to any client.
 *
 * POST   /functions/v1/google-connect
 *        { "refreshToken": "<google refresh token>", "name": "School",
 *          "googleEmail": "me@school.edu", "spaceId": "<uuid>"? }
 *        → verifies the caller's Supabase JWT (auth.getUser — REAL verification),
 *          stashes the token in Vault, and INSERTS a connection row. Re-POST for an
 *          existing (user, email, calendar) = reconnect: replace the Vault secret,
 *          reset status='active', clear last_error. A different-email duplicate is
 *          simply a new row. →  200 { ok: true, id, status: "active" }
 *          409 when spaceId is already linked to another connection.
 *
 * PATCH  /functions/v1/google-connect   { "connectionId": "<uuid>", "name"?, "spaceId"? }
 *        → verifies the JWT, renames / re-maps ONE connection (mirrors
 *          canvas-connect's destination PATCH). The Vault secret, sync_token and
 *          status are untouched — a rename/re-map never resets sync.
 *          →  200 { ok: true, status: <unchanged> }  (404 if no such row,
 *          409 if spaceId is already linked to another connection).
 *
 * DELETE /functions/v1/google-connect   { "connectionId": "<uuid>" }
 *        → verifies the JWT, deletes the connection row + its Vault secret. Other
 *          connections are untouched. →  200 { ok: true }  (404 if no such row).
 *
 * Auth:  Authorization: Bearer <Supabase user JWT>  (verified — this handles a
 *        live Google credential, so presence-only like `capture` is not enough).
 *
 * Env (auto-injected by the platform):
 *   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy google-connect --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, tooManyRequests } from "../_shared/rate_limit.ts";
import { refreshAccessToken } from "../_shared/google_pull.ts";
import { diffSelection, fetchCalendarList } from "../_shared/google_calendars.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, PATCH, DELETE, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Postgres unique-violation SQLSTATE. Two unique constraints exist on
// google_connections: unique(space_id) and unique(user_id, google_email,
// calendar_id). `spaceConflict` distinguishes the former from its error detail.
const UNIQUE_VIOLATION = "23505";
function spaceConflict(err: { code?: string; message?: string } | null): boolean {
  return err?.code === UNIQUE_VIOLATION && !!err.message?.includes("space_id");
}

/**
 * Enumerate the account's calendars (calendarList.list) and upsert the per-connection
 * registry (google_connection_calendars, 0036). Best-effort: a fetch/quota failure
 * NEVER fails the connect — we guarantee a selected 'primary' row so the sync still
 * has a calendar. An existing calendar's `selected` choice is preserved across a
 * reconnect; a brand-new calendar defaults to selected only if it is the primary
 * (v1 behavior: primary syncs, secondaries are opt-in).
 */
async function syncConnectionCalendars(
  admin: SupabaseClient,
  connectionId: string,
  googleEmail: string,
  refreshToken: string,
  clientId: string | undefined,
  clientSecret: string | undefined,
): Promise<void> {
  // Existing selections to preserve across a reconnect / re-enumeration.
  const { data: existing } = await admin
    .from("google_connection_calendars")
    .select("calendar_id, selected")
    .eq("connection_id", connectionId);
  const selById = new Map(
    ((existing ?? []) as { calendar_id: string; selected: boolean }[]).map((r) => [r.calendar_id, r.selected]),
  );

  let entries: { calendarId: string; summary: string; isPrimary: boolean }[] = [];
  if (clientId && clientSecret) {
    try {
      const accessToken = await refreshAccessToken(refreshToken, clientId, clientSecret);
      entries = await fetchCalendarList(accessToken);
    } catch {
      entries = []; // fall through to the primary-only fallback below
    }
  }

  if (entries.length === 0) {
    // Enumeration unavailable (no client creds / fetch error): guarantee a primary
    // row so the connection syncs its primary calendar exactly as before.
    if (!selById.has("primary")) {
      await admin.from("google_connection_calendars").insert({
        connection_id: connectionId,
        calendar_id: "primary",
        summary: googleEmail,
        is_primary: true,
        selected: true,
      });
    }
    return;
  }

  const rows = entries.map((e) => ({
    connection_id: connectionId,
    calendar_id: e.calendarId,
    summary: e.summary,
    is_primary: e.isPrimary,
    // Preserve an existing choice; new calendars default to primary-only. `sync_token`
    // is intentionally omitted so an existing calendar keeps its incremental cursor.
    selected: selById.has(e.calendarId) ? selById.get(e.calendarId)! : e.isPrimary,
  }));
  await admin
    .from("google_connection_calendars")
    .upsert(rows, { onConflict: "connection_id,calendar_id" });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST" && req.method !== "PATCH" && req.method !== "DELETE") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "Server not configured" }, 500);
  }
  // Google creds (project-wide secrets, shared with google-sync) let us enumerate the
  // account's calendars at connect time. Absent → calendar enumeration is skipped and
  // the connection falls back to a primary-only row (never fatal to connect).
  const googleClientId = Deno.env.get("GOOGLE_CLIENT_ID");
  const googleClientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET");

  // ── Real JWT verification: resolve the caller from their Supabase token ──
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    return json({ error: "Missing or invalid Authorization header" }, 401);
  }
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) {
    return json({ error: "Invalid or expired token" }, 401);
  }
  const userId = userData.user.id;

  // Service-role client: Vault RPCs + google_connections writes (bypasses RLS).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Connect/rename/disconnect are OAuth-credential operations — occasional by
  // nature. 20/hour is generous (add several accounts + a few space re-maps in a
  // sitting) yet blocks a token-storing loop.
  const rl = await checkRateLimit(admin, userId, "google-connect", 20, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  // ── DISCONNECT (DELETE) ─────────────────────────────────────
  if (req.method === "DELETE") {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    // Docs singleton disconnect (`{docs:true}`): remove the dedicated Notes/Docs
    // connection + its Vault secret. Idempotent — 200 even if none exists.
    if (body?.docs === true) {
      const { data: docsRow } = await admin
        .from("google_docs_connections")
        .select("vault_secret_id")
        .eq("user_id", userId)
        .maybeSingle();
      const { error: delErr } = await admin
        .from("google_docs_connections")
        .delete()
        .eq("user_id", userId);
      if (delErr) {
        return json({ error: "Failed to remove docs connection" }, 500);
      }
      if (docsRow?.vault_secret_id) {
        await admin.rpc("delete_google_secret", { secret_id: docsRow.vault_secret_id });
      }
      return json({ ok: true });
    }

    let connectionId: string;
    if (typeof body?.connectionId !== "string" || !body.connectionId.trim()) {
      return json({ error: "Body must contain a non-empty `connectionId` string" }, 400);
    }
    connectionId = body.connectionId.trim();

    // Grab the row (scoped to the caller) so we can purge its Vault secret after.
    const { data: existing } = await admin
      .from("google_connections")
      .select("vault_secret_id")
      .eq("id", connectionId)
      .eq("user_id", userId)
      .maybeSingle();
    if (!existing) {
      return json({ error: "No such Google connection" }, 404);
    }

    // Delete the row (other connections untouched). The row is gone regardless of
    // the best-effort secret cleanup below.
    const { error: delErr } = await admin
      .from("google_connections")
      .delete()
      .eq("id", connectionId)
      .eq("user_id", userId);
    if (delErr) {
      return json({ error: "Failed to remove connection" }, 500);
    }
    if (existing.vault_secret_id) {
      await admin.rpc("delete_google_secret", { secret_id: existing.vault_secret_id });
    }
    return json({ ok: true });
  }

  // ── RENAME / RE-MAP / CALENDAR SELECTION (PATCH) ────────────
  if (req.method === "PATCH") {
    let connectionId: string;
    let name: string | undefined;
    let spaceId: string | null | undefined;
    let calendars: string[] | undefined;
    try {
      const body = await req.json();
      if (typeof body?.connectionId !== "string" || !body.connectionId.trim()) {
        return json({ error: "Body must contain a non-empty `connectionId` string" }, 400);
      }
      connectionId = body.connectionId.trim();
      // `calendars`: the FULL set of calendar ids the user wants synced for this
      // connection. Present ⇒ this is a selection update (handled below, independent
      // of name/space). A pure selection PATCH omits name/spaceId.
      if (body.calendars !== undefined) {
        if (!Array.isArray(body.calendars) || body.calendars.some((c: unknown) => typeof c !== "string")) {
          return json({ error: "`calendars` must be an array of calendar-id strings" }, 400);
        }
        calendars = (body.calendars as string[]).map((c) => c.trim()).filter((c) => c.length > 0);
      }
      if (body.name !== undefined) {
        if (typeof body.name !== "string" || !body.name.trim()) {
          return json({ error: "`name` must be a non-empty string" }, 400);
        }
        name = body.name.trim();
      }
      // spaceId: string re-maps, null unlinks (read-in only). Absent = leave as is.
      if (body.spaceId !== undefined) {
        if (body.spaceId === null) {
          spaceId = null;
        } else if (typeof body.spaceId === "string" && body.spaceId.trim()) {
          spaceId = body.spaceId.trim();
        } else {
          return json({ error: "`spaceId` must be a uuid string or null" }, 400);
        }
      }
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    // ── CALENDAR SELECTION update ──────────────────────────────
    // Set which of the connection's calendars sync. Newly selected → reset its
    // per-calendar cursor so the next tick full-resyncs it. Newly deselected → delete
    // that calendar's mirrored events from Atlas WITHOUT deleting them from Google
    // (clear the tombstones the delete trigger writes), then reset its cursor.
    if (calendars !== undefined) {
      // Ownership: the connection must belong to the caller.
      const { data: conn } = await admin
        .from("google_connections")
        .select("id")
        .eq("id", connectionId)
        .eq("user_id", userId)
        .maybeSingle();
      if (!conn) return json({ error: "No such Google connection" }, 404);

      const { data: calRows } = await admin
        .from("google_connection_calendars")
        .select("calendar_id, selected")
        .eq("connection_id", connectionId);
      const currentlySelected = ((calRows ?? []) as { calendar_id: string; selected: boolean }[])
        .filter((r) => r.selected)
        .map((r) => r.calendar_id);
      const { toSelect, toDeselect } = diffSelection(currentlySelected, calendars);

      for (const calId of toSelect) {
        // Reset the cursor so the next sync tick full-resyncs this newly-on calendar.
        const { error } = await admin
          .from("google_connection_calendars")
          .update({ selected: true, sync_token: null })
          .eq("connection_id", connectionId)
          .eq("calendar_id", calId);
        if (error) return json({ error: "Failed to update calendar selection" }, 500);
      }

      for (const calId of toDeselect) {
        // Collect this calendar's mirrored gids BEFORE deleting so we can clear the
        // tombstones the AFTER DELETE trigger writes — a deselect must not delete the
        // user's real Google events, only their Atlas mirrors.
        const { data: evs } = await admin
          .from("events")
          .select("google_event_id")
          .eq("user_id", userId)
          .eq("google_connection_id", connectionId)
          .eq("google_calendar_id", calId);
        const gids = ((evs ?? []) as { google_event_id: string | null }[])
          .map((e) => e.google_event_id)
          .filter((g): g is string => !!g);

        const { error: delErr } = await admin
          .from("events")
          .delete()
          .eq("user_id", userId)
          .eq("google_connection_id", connectionId)
          .eq("google_calendar_id", calId);
        if (delErr) return json({ error: "Failed to remove deselected calendar's events" }, 500);

        if (gids.length > 0) {
          await admin
            .from("deleted_google_events")
            .delete()
            .eq("google_connection_id", connectionId)
            .in("google_event_id", gids);
        }

        const { error: updErr } = await admin
          .from("google_connection_calendars")
          .update({ selected: false, sync_token: null })
          .eq("connection_id", connectionId)
          .eq("calendar_id", calId);
        if (updErr) return json({ error: "Failed to update calendar selection" }, 500);
      }

      return json({ ok: true });
    }

    if (name === undefined && spaceId === undefined) {
      return json({ error: "Nothing to update (send `name`, `spaceId`, or `calendars`)" }, 400);
    }

    const patch: Record<string, unknown> = {};
    if (name !== undefined) patch.name = name;
    if (spaceId !== undefined) patch.space_id = spaceId;

    // Update ONLY the routing/label fields. vault_secret_id, sync_token and status
    // are deliberately left alone so a rename/re-map never resets sync. `.select`
    // lets us 404 when the caller has no matching connection row.
    const { data: updated, error: updErr } = await admin
      .from("google_connections")
      .update(patch)
      .eq("id", connectionId)
      .eq("user_id", userId)
      .select("status");
    if (updErr) {
      if (updErr.code === UNIQUE_VIOLATION) {
        return json({ error: "That space is already linked to another Google account" }, 409);
      }
      return json({ error: "Failed to update connection" }, 500);
    }
    if (!updated || updated.length === 0) {
      return json({ error: "No such Google connection" }, 404);
    }
    return json({ ok: true, status: updated[0].status });
  }

  // ── CONNECT (POST) ──────────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // ── DOCS singleton connect (`{docs:true, refreshToken, googleEmail}`) ──
  // Designates the ONE Google sign-in that Drive/Docs background work runs off
  // (drive-writeback, drive-import, reference-pull), independent of the N calendar
  // connections. Re-POST replaces the Vault secret (reconnect). No name/space — this
  // account never routes calendar events.
  if (body?.docs === true) {
    let docsRefreshToken: string;
    let docsEmail: string;
    if (typeof body?.refreshToken !== "string" || !body.refreshToken.trim()) {
      return json({ error: "Body must contain a non-empty `refreshToken` string" }, 400);
    }
    if (typeof body?.googleEmail !== "string" || !body.googleEmail.trim()) {
      return json({ error: "Body must contain a non-empty `googleEmail` string" }, 400);
    }
    docsRefreshToken = body.refreshToken.trim();
    docsEmail = body.googleEmail.trim();

    // Prior secret (if reconnecting) so we can purge it after the row points at the new one.
    const { data: docsPrior } = await admin
      .from("google_docs_connections")
      .select("vault_secret_id")
      .eq("user_id", userId)
      .maybeSingle();
    const docsPriorSecretId: string | null = docsPrior?.vault_secret_id ?? null;

    const docsSecretName = `google_docs_refresh_token:${userId}:${Date.now()}`;
    const { data: docsSecretId, error: docsSecretErr } = await admin.rpc(
      "create_google_secret",
      { secret: docsRefreshToken, name: docsSecretName },
    );
    if (docsSecretErr || !docsSecretId) {
      return json({ error: "Failed to store credential" }, 500);
    }

    // Upsert the singleton (PK user_id): swap secret + email, reactivate.
    const { error: docsUpErr } = await admin
      .from("google_docs_connections")
      .upsert(
        {
          user_id: userId,
          google_email: docsEmail,
          vault_secret_id: docsSecretId,
          status: "active",
          last_error: null,
        },
        { onConflict: "user_id" },
      );
    if (docsUpErr) {
      await admin.rpc("delete_google_secret", { secret_id: docsSecretId });
      return json({ error: "Failed to save docs connection" }, 500);
    }
    if (docsPriorSecretId && docsPriorSecretId !== docsSecretId) {
      await admin.rpc("delete_google_secret", { secret_id: docsPriorSecretId });
    }
    return json({ ok: true, status: "active" });
  }

  let refreshToken: string;
  let name: string;
  let googleEmail: string;
  let spaceId: string | null;
  if (typeof body?.refreshToken !== "string" || !body.refreshToken.trim()) {
    return json({ error: "Body must contain a non-empty `refreshToken` string" }, 400);
  }
  if (typeof body?.name !== "string" || !body.name.trim()) {
    return json({ error: "Body must contain a non-empty `name` string" }, 400);
  }
  if (typeof body?.googleEmail !== "string" || !body.googleEmail.trim()) {
    return json({ error: "Body must contain a non-empty `googleEmail` string" }, 400);
  }
  refreshToken = body.refreshToken.trim();
  name = body.name.trim();
  googleEmail = body.googleEmail.trim();
  // spaceId optional; null = read-in only (no default fallback — decision 3).
  if (body.spaceId === undefined || body.spaceId === null) {
    spaceId = null;
  } else if (typeof body.spaceId === "string" && body.spaceId.trim()) {
    spaceId = body.spaceId.trim();
  } else {
    return json({ error: "`spaceId` must be a uuid string or null" }, 400);
  }

  const calendarId = "primary"; // v1: one calendar per login.

  // Existing row for this (user, email, calendar)? Present = reconnect (swap the
  // Vault secret, reactivate); absent = a brand-new connection row.
  const { data: prior } = await admin
    .from("google_connections")
    .select("id, vault_secret_id")
    .eq("user_id", userId)
    .eq("google_email", googleEmail)
    .eq("calendar_id", calendarId)
    .maybeSingle();
  const priorSecretId: string | null = prior?.vault_secret_id ?? null;

  // Stash the refresh token in Vault. A unique name avoids a collision when a
  // user reconnects before the old secret is removed.
  const secretName = `google_refresh_token:${userId}:${Date.now()}`;
  const { data: newSecretId, error: secretErr } = await admin.rpc(
    "create_google_secret",
    { secret: refreshToken, name: secretName },
  );
  if (secretErr || !newSecretId) {
    return json({ error: "Failed to store credential" }, 500);
  }

  let connectionId: string;
  if (prior) {
    // Reconnect: point the existing row at the new secret and reactivate it.
    // name/space_id are refreshed too so re-adding an account updates its label.
    const { error: updErr } = await admin
      .from("google_connections")
      .update({
        name,
        space_id: spaceId,
        vault_secret_id: newSecretId,
        status: "active",
        last_error: null,
      })
      .eq("id", prior.id)
      .eq("user_id", userId);
    if (updErr) {
      await admin.rpc("delete_google_secret", { secret_id: newSecretId });
      if (spaceConflict(updErr)) {
        return json({ error: "That space is already linked to another Google account" }, 409);
      }
      return json({ error: "Failed to save connection" }, 500);
    }
    connectionId = prior.id;
  } else {
    // Brand-new connection row.
    const { data: inserted, error: insErr } = await admin
      .from("google_connections")
      .insert({
        user_id: userId,
        name,
        google_email: googleEmail,
        calendar_id: calendarId,
        space_id: spaceId,
        vault_secret_id: newSecretId,
        status: "active",
        last_error: null,
      })
      .select("id")
      .single();
    if (insErr || !inserted) {
      // Roll back the just-created secret so we never orphan it.
      await admin.rpc("delete_google_secret", { secret_id: newSecretId });
      if (spaceConflict(insErr)) {
        return json({ error: "That space is already linked to another Google account" }, 409);
      }
      if (insErr?.code === UNIQUE_VIOLATION) {
        // (user, email, calendar) race — the account is already connected.
        return json({ error: "This Google account is already connected" }, 409);
      }
      return json({ error: "Failed to save connection" }, 500);
    }
    connectionId = inserted.id;
  }

  // Remove the previous secret now that the row points at the new one.
  if (priorSecretId && priorSecretId !== newSecretId) {
    await admin.rpc("delete_google_secret", { secret_id: priorSecretId });
  }

  // Enumerate the account's calendars so the client can offer a per-calendar picker
  // (0036). Best-effort — a failure here leaves a primary-only row and never fails the
  // connect; the picker still shows primary and the sync runs as before.
  await syncConnectionCalendars(admin, connectionId, googleEmail, refreshToken, googleClientId, googleClientSecret);

  return json({ ok: true, id: connectionId, status: "active" });
});
