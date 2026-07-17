/**
 * Atlas — google-sync Edge Function (Deno)  ·  the two-way sync runner
 *
 * Invoked by pg_cron (Task 4) every 5 minutes with the service-role key. It leases
 * a batch of due google_connections rows (claim_google_sync_connections, 0028 —
 * oldest last_synced_at first, single-flight via `for update skip locked`). Each row
 * is ONE connection (multi-account, 0028); a user may hold several. For each:
 *   DELETE Atlas → Google: process the user's tombstones FIRST (deleted_google_events,
 *         0011) — an app-side delete of a mirrored row is replayed as a Google
 *         DELETE /events/{id} (404/410 = already gone = success), then the tombstone
 *         is cleared. "Deleted anywhere = deleted everywhere."
 *   PULL  Google → Supabase: incremental events.list with the stored sync_token
 *         (410 GONE → full −30d…+365d resync), upserting Google-origin rows and
 *         DELETING any row whose Google event is cancelled (regardless of origin).
 *   PUSH  Supabase → Google: rows changed since last_synced_at — POST a not-yet-
 *         mirrored Atlas row (deterministic id), or PATCH a mirrored one.
 *
 * Single-owner / no-duplicates invariant is backstopped by the DB:
 *   • unique (user_id, google_event_id)         non-partial, so ON CONFLICT infers it (0009/C1)
 *   • events.google_origin bit                  never-re-create-on-Google authority (0007)
 *   • events.google_updated_at                  two-timestamp reconcile (0009/C2)
 *
 * events.google_origin semantics (0007): true ⇒ this row is Google-owned. It is
 * still EDIT-synced back to Google (I2 — a local edit PATCHes it) but is NEVER
 * re-CREATED on Google (no POST path for an origin row). It is set true on a
 * Google-origin insert. Only google_origin=false + null-gid rows are POSTed as new
 * Google events; the null-gid + origin=true PUSH guard now covers only LEGACY
 * detached rows — un-mirroring was removed with the two-way-delete change, so a
 * Google-side cancellation now DELETES the local row regardless of origin.
 *
 * ── Two-way delete (0011). deleted_google_events tombstones an app-side delete of
 * a mirrored row (AFTER DELETE trigger on events, fired for Mac + phone alike). Each
 * cycle the runner (a) replays the tombstones as Google deletes and clears them,
 * (b) SKIPS any incoming pull event whose id still has a pending tombstone so a
 * failed delete isn't resurrected, and (c) clears the tombstones its OWN pull-side
 * deletes just wrote (Google already cancelled those) to avoid a redundant next-run
 * DELETE. Work-block mirror gids live on `tasks`, not `events`, so the trigger never
 * fires for them.
 *
 * Deterministic Google ids (C3): a new push derives the Google event id from the
 * row UUID (base32hex-lowercase of its 16 bytes → [0-9a-v]{26}, inside Google's
 * [a-v0-9]{5,1024}). POSTing that id is idempotent: if a prior POST succeeded but
 * the id write-back didn't, the next cycle re-POSTs the SAME id → Google 409
 * "already exists" → treated as success → converges with no duplicate.
 *
 * ── Storm termination (C2). The reviewer's perpetual push↔pull cycle was:
 *   1. PULL applies a Google event to a mirrored row → trigger bumps updated_at.
 *   2. PUSH sees updated_at > last_synced_at → PATCHes it back → Google bumps its `updated`.
 *   3. PULL sees Google's newer `updated` → re-applies → bumps updated_at again.
 *   4. PUSH re-PATCHes → … forever.
 * The fix breaks every edge:
 *   • Step 1→2: a PULL write stamps updated_at = runStart (explicit; the 0009
 *     trigger honors it) and google_updated_at = google.updated. runStart equals
 *     the NEXT run's last_synced_at, so the row fails `updated_at > last_synced_at`
 *     and PUSH never re-selects a purely sync-applied row.
 *   • Step 3: a PULL recency gate skips the write when google.updated <=
 *     google_updated_at (same clock), plus a content no-op guard — so Google
 *     echoing our own push (whose `updated` we stored at push time) re-applies
 *     nothing and bumps nothing.
 *   • A genuine user edit auto-stamps updated_at=now() (> last_synced_at) and its
 *     content differs from Google's last, so it PUSHes exactly once; the push
 *     write-back stamps updated_at=runStart and google_updated_at=response.updated,
 *     so the next run neither re-selects (push) nor re-applies (pull). Converges in
 *     one cycle. ∎
 *
 * Auth: service-role only. The bearer token MUST equal SUPABASE_SERVICE_ROLE_KEY
 * (rejects anon / user JWTs). There is no inbound user to carry a JWT — the cron
 * is the caller.
 *
 * Modes:  POST /functions/v1/google-sync            → run (reads + writes; leases users)
 *         POST /functions/v1/google-sync?dryRun=1   → read + log intended writes,
 *                                                      write NOTHING (DB, Google, or
 *                                                      connection rows — and does NOT
 *                                                      lease, so it never mutates).
 *
 * Env (SUPABASE_* auto-injected; GOOGLE_* set via `supabase secrets set`):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
 *
 * Deploy: supabase functions deploy google-sync --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  driveFileMeta,
  InvalidGrantError,
  mintAccessToken,
  pullDocNoteReference,
} from "../_shared/google_pull.ts";

const GCAL_BASE = "https://www.googleapis.com/calendar/v3";
const BATCH_LIMIT = 60; // connections processed per invocation (oldest first)
const REF_BATCH = 100;  // Drive references pulled per user per tick (least-recently-synced first)
// Bounded fan-out. Users are independent (per-user leases) and references are
// deduped per Doc before dispatch, so the only coupling is Google quota — 6×6
// worst-case in-flight calls stays far under both Drive and Docs per-user caps.
// This is what lets BATCH_LIMIT be 60 inside the function wall-clock budget:
// tick duration ≈ slowest user-chain, not the sum of every sequential await.
const USER_CONCURRENCY = 6;
const REF_CONCURRENCY = 6;

/** Run `fn` over `items` with at most `limit` in flight; results keep item order.
 *  Rejections propagate — callers that need per-item isolation catch inside `fn`. */
async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}
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
 * Deterministic Google event id from a row UUID: base32hex-lowercase of the 16
 * UUID bytes → 26 chars in [0-9a-v], inside Google's [a-v0-9]{5,1024}. Same UUID
 * ⇒ same id every cycle, which is what makes a re-POST after a failed write-back
 * idempotent (Google returns 409 "already exists" instead of creating a duplicate).
 */
function uuidToGoogleId(uuid: string): string {
  const hex = uuid.replace(/-/g, "");
  const alphabet = "0123456789abcdefghijklmnopqrstuv"; // RFC 4648 base32hex
  let value = 0;
  let bits = 0;
  let out = "";
  for (let i = 0; i < 16; i++) {
    value = (value << 8) | parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    bits += 8;
    while (bits >= 5) {
      out += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += alphabet[(value << (5 - bits)) & 31];
  return out;
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
  google_updated_at: string | null;
  space_name: string;
  title?: string;
  subtitle?: string;
  start_at?: string;
  end_at?: string;
  is_all_day?: boolean;
  notes?: string | null;
  google_calendar_id?: string | null;
}

interface Connection {
  id: string;
  user_id: string;
  vault_secret_id: string | null;
  calendar_id: string;
  space_id: string | null;
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
  tombstoned: number;
  pushedNew: number;
  pushedUpdated: number;
  referencesChecked: number;
  referencesSynced: number;
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

// Text-field normalization. Google and the DB disagree on "empty": Google serializes
// a blank description as "" while a never-set DB column is null. Treating those as
// different made a just-pulled, untouched Google row (description:"" vs notes:null)
// look locally edited, so PUSH re-PATCHed it back — the incident that aborted a run
// on an immutable birthday. Canonicalize null / undefined / "" to a single value.
function normText(v: string | null | undefined): string {
  return v == null ? "" : v;
}
/** Google text → canonical DB form: empty/undefined description stored as NULL. */
function normNotes(v: string | null | undefined): string | null {
  return v == null || v === "" ? null : v;
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

// Content the PULL would write vs. what the row already holds. Compares instants by
// epoch (DB and Google serialize timestamps differently) so an identical event is a
// true no-op — skipping the write avoids an updated_at trigger bump (C2 storm guard).
interface MappedGoogle {
  fields: { start: string; end: string; allDay: boolean };
  title: string;
  notes: string | null;
}
function contentMatches(row: EventRow, u: MappedGoogle): boolean {
  const sameStart = row.start_at != null && new Date(row.start_at).getTime() === new Date(u.fields.start).getTime();
  const sameEnd = row.end_at != null && new Date(row.end_at).getTime() === new Date(u.fields.end).getTime();
  return normText(row.title) === normText(u.title) &&
    sameStart && sameEnd &&
    (!!row.is_all_day) === u.fields.allDay &&
    normText(row.notes) === normText(u.notes);
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

// ── Drive references (Docs → Notes import) ──────────────────────
// A minimal projection of a project_references row (migration 0013).
interface RefRow {
  id: string;
  kind: string;            // 'doc_note' | 'file' | 'link'
  drive_file_id: string | null;
  mime_type: string | null;
  modified_time: string | null;
  note_id: string | null;
}

/**
 * Pull this user's Drive-backed references (design doc §Server-flow 3). Shares the
 * calendar sync's access token, so the refresh token MUST carry `drive.file` (403s
 * here just mark the reference 'error' — never fatal to the calendar sync).
 *
 *   doc_note: files.get modifiedTime; changed vs the stored baseline → files.export
 *             text/markdown → overwrite notes.body + re-baseline modified_time. The
 *             baseline gate (drive.modifiedTime > stored) is the notes analogue of the
 *             calendar C2 storm guard: after a write-back re-baselines to Drive's new
 *             time, the next pull sees equal and re-pulls nothing.
 *   file:     metadata refresh only (view-only; bytes stay in Drive).
 *
 * TITLE is intentionally never overwritten on pull — it's set at import and left
 * alone so a local rename isn't clobbered every tick. Per-reference isolation: one
 * file's failure is recorded and marked 'error'; the loop and the run continue.
 */
async function syncUserReferences(
  admin: SupabaseClient,
  userId: string,
  accessToken: string,
  runStartISO: string,
  dryRun: boolean,
): Promise<{ checked: number; synced: number; errors: { id: string; message: string }[] }> {
  const errors: { id: string; message: string }[] = [];
  let checked = 0;
  let synced = 0;
  // References whose meta check found NOTHING changed. The common case by far —
  // written as ONE batched update at the end instead of a round-trip per ref.
  const noopIds: string[] = [];

  // Drive-backed only ('link' has nothing to pull). Least-recently-synced first, capped
  // per tick so a big pool can't monopolize the batch (calendar's chunking idiom).
  const { data: rows, error } = await admin
    .from("project_references")
    .select("id, kind, drive_file_id, mime_type, modified_time, note_id")
    .eq("user_id", userId)
    .in("kind", ["doc_note", "file"])
    .order("last_synced_at", { ascending: true, nullsFirst: true })
    .limit(REF_BATCH);
  if (error) throw new Error(`references select failed: ${error.message}`);

  // Per-tick dedupe BEFORE the fan-out: two references to the SAME Doc pull once
  // (first = least-recently-synced wins) — the sibling re-baseline in
  // pullDocNoteReference keeps the skipped duplicate honest.
  const seenFiles = new Set<string>();
  const work: RefRow[] = [];
  for (const row of (rows ?? []) as RefRow[]) {
    const driveFileId = row.drive_file_id;
    if (!driveFileId) continue;
    checked++;
    if (seenFiles.has(driveFileId)) continue; // same Doc already handled this tick
    seenFiles.add(driveFileId);
    work.push(row);
  }

  // Per-reference isolation preserved: every failure is caught INSIDE the worker,
  // so one bad file never rejects the pool. Counters/arrays are safe to touch from
  // concurrent workers (single-threaded event loop).
  await mapWithConcurrency(work, REF_CONCURRENCY, async (row) => {
    const driveFileId = row.drive_file_id!;
    try {
      if (row.kind === "doc_note") {
        // The complete doc_note pull (meta check, storm guard, single/multi-tab
        // fork, tab upsert, re-baseline) lives in the shared module. It fetches its
        // own meta and THROWS on gone/trashed — the catch below marks 'error'.
        const { changed } = await pullDocNoteReference(
          admin,
          userId,
          accessToken,
          {
            id: row.id,
            drive_file_id: driveFileId,
            note_id: row.note_id,
            mime_type: row.mime_type,
            modified_time: row.modified_time,
          },
          runStartISO,
          dryRun,
          { skipNoOpBaseline: true }, // batched below
        );
        if (changed) synced++;
        else noopIds.push(row.id);
      } else {
        // 'file' — metadata refresh only (view-only reference; bytes stay in Drive).
        const metaRes = await driveFileMeta(accessToken, driveFileId);
        if (!metaRes.ok) {
          // Gone / access lost (404/403) or any non-2xx — mark this one 'error' and move
          // on. Never auto-delete: removing a reference is a user action.
          if (!dryRun) {
            await admin.from("project_references")
              .update({ sync_state: "error", last_synced_at: runStartISO })
              .eq("id", row.id).eq("user_id", userId);
          }
          errors.push({ id: row.id, message: `drive ${metaRes.status}: ${metaRes.message}` });
          return;
        }
        const meta = metaRes.meta;
        if (meta.trashed) {
          if (!dryRun) {
            await admin.from("project_references")
              .update({ sync_state: "error", last_synced_at: runStartISO })
              .eq("id", row.id).eq("user_id", userId);
          }
          errors.push({ id: row.id, message: "drive file trashed" });
          return;
        }
        // Unchanged metadata is a no-op check — fold into the batched bump instead
        // of writing identical values back row-by-row every tick.
        const sameTime = (meta.modifiedTime ?? null) === (row.modified_time ?? null) ||
          (meta.modifiedTime != null && row.modified_time != null &&
            new Date(meta.modifiedTime).getTime() === new Date(row.modified_time).getTime());
        if (sameTime && (meta.mimeType ?? row.mime_type) === row.mime_type) {
          noopIds.push(row.id);
          return;
        }
        if (!dryRun) {
          await admin.from("project_references")
            .update({
              modified_time: meta.modifiedTime ?? null,
              mime_type: meta.mimeType ?? row.mime_type,
              last_synced_at: runStartISO,
              sync_state: "synced",
            })
            .eq("id", row.id).eq("user_id", userId);
        }
        synced++;
      }
    } catch (e) {
      const message = String((e as Error)?.message ?? e).slice(0, 200);
      errors.push({ id: row.id, message });
      if (!dryRun) {
        await admin.from("project_references")
          .update({ sync_state: "error", last_synced_at: runStartISO })
          .eq("id", row.id).eq("user_id", userId);
      }
    }
  });

  // One write for every unchanged reference this tick (the successful-check stamp).
  if (!dryRun && noopIds.length > 0) {
    const { error: bErr } = await admin.from("project_references")
      .update({ last_synced_at: runStartISO, sync_state: "synced" })
      .in("id", noopIds).eq("user_id", userId);
    if (bErr) errors.push({ id: "*", message: `noop baseline batch failed: ${bErr.message}` });
  }
  return { checked, synced, errors };
}

// ── One user's sync ─────────────────────────────────────────────
async function syncUser(admin: SupabaseClient, conn: Connection, clientId: string, clientSecret: string, dryRun: boolean): Promise<UserResult> {
  const userId = conn.user_id;
  const runStart = new Date();
  const runStartISO = runStart.toISOString();
  const result: UserResult = {
    userId,
    status: "active",
    inserted: 0,
    updated: 0,
    deleted: 0,
    tombstoned: 0,
    pushedNew: 0,
    pushedUpdated: 0,
    referencesChecked: 0,
    referencesSynced: 0,
    fullResync: false,
  };

  // 1. Decrypt THIS connection's refresh token (service-role Vault read) and mint
  //    an access token. Multi-account: mint by the connection's own secret, never a
  //    per-user lookup (a user may hold several connections).
  const accessToken = await mintAccessToken(admin, userId, clientId, clientSecret, conn.vault_secret_id);

  // I1: gids of this user's Mac-owned work-block mirrors. Work-block mirroring is
  //     Mac-owned and OFF in server mode (v1), but a legacy mirror may still exist
  //     on Google — never ingest one as a duplicate `events` row.
  const workBlockGids = new Set<string>();
  {
    const { data: wbRows } = await admin
      .from("tasks")
      .select("work_block_google_event_id")
      .eq("user_id", userId)
      .not("work_block_google_event_id", "is", null);
    for (const r of (wbRows ?? []) as { work_block_google_event_id: string | null }[]) {
      if (r.work_block_google_event_id) workBlockGids.add(r.work_block_google_event_id);
    }
  }

  // Which calendars of this connection sync (0036). Reads fan in from every SELECTED
  //     calendar; each carries its own incremental sync_token. Resilience: a connection
  //     with no registry rows yet (created before 0036, or enumeration failed) syncs its
  //     stored primary calendar with the legacy connection-level cursor — pre-0036 behavior.
  interface SelectedCalendar { calendar_id: string; is_primary: boolean; sync_token: string | null }
  let selectedCals: SelectedCalendar[] = [];
  {
    const { data: calRows, error: calErr } = await admin
      .from("google_connection_calendars")
      .select("calendar_id, is_primary, sync_token")
      .eq("connection_id", conn.id)
      .eq("selected", true);
    if (calErr) throw new Error(`calendar list select failed: ${calErr.message}`);
    selectedCals = (calRows ?? []) as SelectedCalendar[];
  }
  if (selectedCals.length === 0) {
    selectedCals = [{ calendar_id: conn.calendar_id, is_primary: true, sync_token: conn.sync_token }];
  }
  // Writes route OUT to the connection's PRIMARY calendar only (reads fan in from all).
  const primaryCalId = selectedCals.find((c) => c.is_primary)?.calendar_id ?? conn.calendar_id;

  // I4 (two-way delete). Replay this user's app-side deletions to Google FIRST. A
  //     tombstone (deleted_google_events, 0011) is written by an AFTER DELETE trigger
  //     whenever an events row carrying a google_event_id is deleted (Mac or phone).
  //     Read the set up front: it both drives the Google deletes below AND gates the
  //     PULL so a not-yet-deleted event is never resurrected. Each tombstone carries the
  //     calendar the event lived on (0036) so the delete replays to the right calendar.
  const tombstonedGids = new Set<string>();
  const tombstoneCalById = new Map<string, string>();
  {
    const { data: tombRows, error: tombErr } = await admin
      .from("deleted_google_events")
      .select("google_event_id, google_calendar_id")
      .eq("user_id", userId)
      .eq("google_connection_id", conn.id);
    if (tombErr) throw new Error(`tombstone select failed: ${tombErr.message}`);
    for (const r of (tombRows ?? []) as { google_event_id: string; google_calendar_id: string | null }[]) {
      if (r.google_event_id) {
        tombstonedGids.add(r.google_event_id);
        tombstoneCalById.set(r.google_event_id, r.google_calendar_id ?? primaryCalId);
      }
    }
  }
  result.tombstoned = tombstonedGids.size;

  // Per-event isolation mirrors the PUSH loop: one failed delete records and the
  // loop continues; only successfully-deleted (or already-gone) tombstones clear,
  // so a failure retries next cycle. dryRun issues no Google/DB writes.
  const tombstoneErrors: { gid: string; message: string }[] = [];
  if (!dryRun && tombstonedGids.size > 0) {
    const cleared: string[] = [];
    for (const gid of tombstonedGids) {
      try {
        const calId = tombstoneCalById.get(gid) ?? primaryCalId;
        const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(calId)}/events/${encodeURIComponent(gid)}`, {
          method: "DELETE",
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        // 2xx deleted; 404/410 already gone — both success. Anything else is real.
        if (res.ok || res.status === 404 || res.status === 410) {
          cleared.push(gid);
        } else {
          throw new Error(`google delete ${res.status}: ${(await res.text()).slice(0, 200)}`);
        }
      } catch (e) {
        tombstoneErrors.push({ gid, message: String((e as Error)?.message ?? e).slice(0, 200) });
      }
    }
    if (cleared.length > 0) {
      const { error } = await admin
        .from("deleted_google_events")
        .delete()
        .eq("user_id", userId)
        .eq("google_connection_id", conn.id)
        .in("google_event_id", cleared);
      if (error) throw new Error(`tombstone clear failed: ${error.message}`);
    }
  }

  // Landing / routing space for THIS connection (once — same for every calendar).
  // Incoming events land in the connection's linked space (space_id → name); PUSH
  // routes out only events in that same space. When the connection has no link
  // (space_id null — "read-in only"), pulled events still need a home
  // (events.space_name is NOT NULL), so they fall back to the user's first space;
  // PUSH is skipped ("an unlinked space stays in Atlas").
  let linkedSpace: string | null = null;
  if (conn.space_id) {
    const { data: sRow } = await admin
      .from("spaces")
      .select("name")
      .eq("user_id", userId)
      .eq("id", conn.space_id)
      .maybeSingle();
    linkedSpace = (sRow?.name as string | undefined) ?? null;
  }
  let defaultSpace: string | null = linkedSpace;
  if (!defaultSpace) {
    // Fallback landing space (the app orders spaces by `sort`; no created_at column).
    const { data: spaceRows } = await admin
      .from("spaces")
      .select("name, sort")
      .eq("user_id", userId)
      .order("sort", { ascending: true })
      .order("name", { ascending: true })
      .limit(1);
    defaultSpace = (spaceRows?.[0]?.name as string | undefined) ?? null;
  }

  // The set of row ids the sync itself wrote this run — excluded from PUSH so a
  // pulled/un-mirrored row is never echoed back to Google in the same pass.
  const syncTouched = new Set<string>();

  // 2. PULL — per SELECTED calendar (0036). Each calendar keeps its own incremental
  //    sync_token; 410 GONE (or no token) → full −30d…+365d resync of THAT calendar.
  //    Reads fan in from every selected calendar; connection-level accumulators collect
  //    their writes so the adoption dedupe and the apply are each ONE batch.
  interface UpsertVal extends MappedGoogle {
    googleUpdated: number;
    googleUpdatedISO: string;
  }
  const allUpserts = new Map<string, UpsertVal>(); // merged, for the PUSH eventTypeRestriction lookup
  const inserts: Record<string, unknown>[] = [];
  const updates: { id: string; expectUpdatedAt: string; patch: Record<string, unknown> }[] = [];
  const toDelete: string[] = [];
  const deletedFromPullGids: string[] = [];
  // Each candidate carries the calendar it came from so its inserted/adopted row is
  // stamped google_calendar_id (needed so a later deselect deletes the right rows).
  const insertCandidates: { gid: string; calendarId: string; u: UpsertVal }[] = [];
  const newSyncTokens = new Map<string, string | null>(); // calendar_id → cursor to persist

  for (const cal of selectedCals) {
    let listing: ListResult = { items: [], nextSyncToken: null, gone: false };
    if (cal.sync_token) {
      listing = await listEvents(accessToken, cal.calendar_id, cal.sync_token, false);
    }
    if (!cal.sync_token || listing.gone) {
      listing = await listEvents(accessToken, cal.calendar_id, null, true);
      result.fullResync = true;
    }
    newSyncTokens.set(cal.calendar_id, listing.nextSyncToken ?? cal.sync_token);

    // Split this calendar's incoming events into deletions and upserts, keyed by gid.
    const cancelledGids: string[] = [];
    const upserts = new Map<string, UpsertVal>();
    for (const ev of listing.items) {
      const gid = ev.id;
      if (!gid) continue;
      if (workBlockGids.has(gid)) continue; // I1: never ingest a Mac-owned work-block mirror
      if (tombstonedGids.has(gid)) continue; // I4: app-deleted (Google DELETE issued above) — never resurrect
      if (ev.status === "cancelled") {
        cancelledGids.push(gid);
        continue;
      }
      const iv = interval(ev.start, ev.end);
      if (!iv) continue; // unmappable (e.g. no times) — skip
      const gUpdatedISO = ev.updated ? new Date(ev.updated).toISOString() : runStartISO;
      const val: UpsertVal = {
        fields: iv,
        title: ev.summary ?? "Untitled",
        notes: normNotes(ev.description),
        googleUpdated: new Date(gUpdatedISO).getTime(),
        googleUpdatedISO: gUpdatedISO,
      };
      upserts.set(gid, val);
      allUpserts.set(gid, val);
    }

    // Existing local rows for THIS calendar's gids (scoped by calendar so attribution
    // stays exact). Content columns feed the C2 no-op guard.
    const seenGids = [...new Set([...upserts.keys(), ...cancelledGids])];
    const existingByGid = new Map<string, EventRow>();
    if (seenGids.length > 0) {
      const { data: rows, error } = await admin
        .from("events")
        .select("id, google_event_id, google_origin, updated_at, google_updated_at, space_name, title, start_at, end_at, is_all_day, notes, google_calendar_id")
        .eq("user_id", userId)
        .eq("google_connection_id", conn.id) // this connection's mirrors only
        .eq("google_calendar_id", cal.calendar_id) // …and this calendar's (per-calendar attribution)
        .in("google_event_id", seenGids);
      if (error) throw new Error(`events select failed: ${error.message}`);
      for (const r of (rows ?? []) as EventRow[]) {
        if (r.google_event_id) existingByGid.set(r.google_event_id, r);
      }
    }

    // 2a. Deletions (cancelled events). "Deleted anywhere = deleted everywhere": a
    //     Google-side cancellation DELETES the local row regardless of google_origin.
    //     deletedFromPullGids lets step 3 clear the self-tombstones this delete triggers.
    for (const gid of cancelledGids) {
      const row = existingByGid.get(gid);
      if (!row) continue;
      syncTouched.add(row.id);
      toDelete.push(row.id);
      deletedFromPullGids.push(gid);
    }

    // 2b. Upserts (newest-wins updates now; inserts/adoptions resolved after the loop).
    for (const [gid, u] of upserts) {
      const row = existingByGid.get(gid);
      if (row) {
        syncTouched.add(row.id);
        // C2 recency (same clock): skip unless Google changed since we last applied/observed it.
        const storedGU = row.google_updated_at ? new Date(row.google_updated_at).getTime() : -Infinity;
        if (u.googleUpdated <= storedGU) continue;
        // C2 no-op guard: identical mapped content ⇒ skip the write (no trigger bump).
        if (contentMatches(row, u)) continue;
        // Write Google's content; stamp updated_at=runStart so PUSH never re-selects
        // it, and google_updated_at=google.updated so the next PULL sees it applied.
        updates.push({
          id: row.id,
          expectUpdatedAt: row.updated_at,
          patch: {
            title: u.title,
            start_at: u.fields.start,
            end_at: u.fields.end,
            is_all_day: u.fields.allDay,
            notes: u.notes,
            updated_at: runStartISO,
            google_updated_at: u.googleUpdatedISO,
          },
        });
      } else {
        insertCandidates.push({ gid, calendarId: cal.calendar_id, u }); // resolve adopt-vs-insert after the loop
      }
    }
  }

  // First-sync adoption dedupe. A user's Google calendar often already contains a
  // copy of an event that also exists as a null-gid Atlas-native row (mirrored here
  // by a prior account, or entered in both places). Inserting the incoming Google
  // event would create a visible TWIN of the native row. Instead, before inserting a
  // no-gid-match event, ADOPT an existing null-gid native row whose title AND
  // start/end instants match exactly: stamp it with this connection's gid so the two
  // become one. google_origin stays as-is (a false, Atlas-born row is now mirrored —
  // edit-synced via PATCH, never re-CREATED). Fields follow the two-timestamp
  // reconcile (updated_at=runStart, google_updated_at=google.updated) so PUSH never
  // re-selects it and the next PULL sees it applied. No match ⇒ a real insert.
  const adoptions: { id: string; expectUpdatedAt: string; patch: Record<string, unknown> }[] = [];
  if (insertCandidates.length > 0) {
    // One query for all candidate titles; match/tie-break in memory.
    const wantTitles = [...new Set(insertCandidates.map((c) => c.u.title))];
    const { data: nativeRows, error: nativeErr } = await admin
      .from("events")
      .select("id, updated_at, title, start_at, end_at")
      .eq("user_id", userId)
      .is("google_event_id", null)
      .eq("google_origin", false) // Atlas-born rows only; never resurrect a legacy detached origin row
      .in("title", wantTitles);
    if (nativeErr) throw new Error(`adoption select failed: ${nativeErr.message}`);
    interface NativeRow { id: string; updated_at: string; title?: string; start_at?: string; end_at?: string }
    const nativeByTitle = new Map<string, NativeRow[]>();
    for (const r of (nativeRows ?? []) as NativeRow[]) {
      const key = normText(r.title);
      const list = nativeByTitle.get(key);
      if (list) list.push(r);
      else nativeByTitle.set(key, [r]);
    }
    const usedNativeIds = new Set<string>(); // one native row can't be adopted twice
    // Deterministic candidate order so which gid wins a shared row is stable.
    insertCandidates.sort((a, b) => (a.gid < b.gid ? -1 : a.gid > b.gid ? 1 : 0));
    for (const { gid, calendarId, u } of insertCandidates) {
      const pool = (nativeByTitle.get(normText(u.title)) ?? []).filter((r) =>
        !usedNativeIds.has(r.id) &&
        r.start_at != null && new Date(r.start_at).getTime() === new Date(u.fields.start).getTime() &&
        r.end_at != null && new Date(r.end_at).getTime() === new Date(u.fields.end).getTime()
      );
      if (pool.length > 0) {
        // Tie-break deterministically: adopt the oldest id.
        pool.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
        const adopt = pool[0];
        usedNativeIds.add(adopt.id);
        syncTouched.add(adopt.id); // just written by the pull — never echo it back to Google this run
        adoptions.push({
          id: adopt.id,
          expectUpdatedAt: adopt.updated_at,
          patch: {
            google_event_id: gid,
            google_connection_id: conn.id,
            google_calendar_id: calendarId, // per-calendar attribution (0036)
            updated_at: runStartISO,
            google_updated_at: u.googleUpdatedISO,
          },
        });
      } else {
        if (!defaultSpace) continue; // no space to file it under — skip insert (space_name is NOT NULL)
        const newId = crypto.randomUUID();
        syncTouched.add(newId); // just-pulled Google-origin row — never echo it back to Google this run
        inserts.push({
          id: newId,
          user_id: userId,
          space_name: defaultSpace,
          title: u.title,
          subtitle: "Google Calendar",
          start_at: u.fields.start,
          end_at: u.fields.end,
          is_all_day: u.fields.allDay,
          notes: u.notes,
          google_event_id: gid,
          google_connection_id: conn.id,   // attribution: this connection owns the mirror
          google_calendar_id: calendarId,  // …and which calendar it came from (0036)
          google_origin: true,
          updated_at: runStartISO,         // ≤ next last_synced_at ⇒ never echoed by PUSH
          google_updated_at: u.googleUpdatedISO,
        });
      }
    }
  }
  result.inserted = inserts.length;
  result.updated = updates.length + adoptions.length;
  result.deleted = toDelete.length;

  // 3. Apply pull writes (skipped entirely in dryRun).
  if (!dryRun) {
    if (inserts.length > 0) {
      // Idempotent: non-partial unique (google_connection_id, google_event_id) makes a re-run a no-op.
      const { error } = await admin.from("events").upsert(inserts, { onConflict: "google_connection_id,google_event_id" });
      if (error) throw new Error(`insert failed: ${error.message}`);
    }
    for (const u of updates) {
      // Optimistic: only apply if the row is unchanged since we read it, so a
      // concurrent Mac edit is never clobbered (it PUSHes next run instead).
      const { error } = await admin.from("events").update(u.patch).eq("id", u.id).eq("updated_at", u.expectUpdatedAt);
      if (error) throw new Error(`update failed: ${error.message}`);
    }
    for (const a of adoptions) {
      // Optimistic on updated_at: a concurrent edit no-ops the adopt; the still-
      // null-gid row is re-considered for adoption next run (idempotent).
      const { error } = await admin.from("events").update(a.patch).eq("id", a.id).eq("updated_at", a.expectUpdatedAt);
      if (error) throw new Error(`adoption failed: ${error.message}`);
    }
    if (toDelete.length > 0) {
      const { error } = await admin.from("events").delete().in("id", toDelete);
      if (error) throw new Error(`delete failed: ${error.message}`);
      // The AFTER DELETE trigger (0011) just tombstoned each of these gids, but
      // Google already cancelled them — clear those self-tombstones so the next run
      // doesn't issue a redundant (404) Google DELETE.
      const { error: tErr } = await admin
        .from("deleted_google_events")
        .delete()
        .eq("user_id", userId)
        .eq("google_connection_id", conn.id)
        .in("google_event_id", deletedFromPullGids);
      if (tErr) throw new Error(`pull-delete tombstone clear failed: ${tErr.message}`);
    }
    // Persist each selected calendar's advanced incremental cursor (0036).
    for (const [calId, token] of newSyncTokens) {
      const { error } = await admin
        .from("google_connection_calendars")
        .update({ sync_token: token })
        .eq("connection_id", conn.id)
        .eq("calendar_id", calId);
      if (error) throw new Error(`calendar sync_token update failed: ${error.message}`);
    }
  }

  // Connection-level cursor kept in step with the PRIMARY calendar — feeds only the
  // pre-0036 resilience fallback (a connection with no registry rows).
  const newSyncToken = newSyncTokens.get(primaryCalId) ?? conn.sync_token;

  // 4. PUSH. Rows changed since last_synced_at, ROUTED to this connection: only
  //    events in the connection's linked space, and — among those — only rows this
  //    connection owns (google_connection_id null = not yet mirrored ⇒ POST here, or
  //    = conn.id ⇒ PATCH here). A row mirrored to a DIFFERENT connection that happens
  //    to sit in this space is never touched. An UNLINKED connection (no space)
  //    routes nothing out ("an unlinked space stays in Atlas").
  //    First run (last_synced_at null) backfills all in-space rows — parity with the
  //    Mac's backfillEventsToGoogle. google_origin=true rows are edit-synced too (I2):
  //    a mirrored gid ⇒ PATCH; only google_origin=false + null-gid rows are POSTed new.
  let pushRows: EventRow[] = [];
  if (linkedSpace) {
    let pushQ = admin
      .from("events")
      .select("id, google_event_id, google_origin, updated_at, google_updated_at, space_name, title, start_at, end_at, is_all_day, notes, google_calendar_id")
      .eq("user_id", userId)
      .eq("space_name", linkedSpace)
      .or(`google_connection_id.is.null,google_connection_id.eq.${conn.id}`);
    if (conn.last_synced_at) pushQ = pushQ.gt("updated_at", conn.last_synced_at);
    const { data, error: pushErr } = await pushQ;
    if (pushErr) throw new Error(`push select failed: ${pushErr.message}`);
    pushRows = (data ?? []) as EventRow[];
  }

  // Per-event push isolation: a single PATCH/POST failure records here and the loop
  // CONTINUES. A per-event failure is NOT a run failure — the run still advances the
  // sync token, stamps last_synced_at and clears the claim (step 5), recording a
  // summary in last_error. This is why one immutable birthday no longer aborts the
  // whole run and strands the connection in status='error'.
  const pushErrors: { id: string; message: string }[] = [];

  for (const row of pushRows) {
    if (syncTouched.has(row.id)) continue; // just written by the pull this run (incl. fresh inserts)
    if (row.google_event_id) {
      // Already mirrored → PATCH (origin or not; the local edit is the newer side).
      // Target the calendar the row lives on (fallback primary for legacy null rows).
      const patchCalId = row.google_calendar_id ?? primaryCalId;
      result.pushedUpdated++;
      if (!dryRun) {
        try {
          const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(patchCalId)}/events/${encodeURIComponent(row.google_event_id)}`, {
            method: "PATCH",
            headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
            body: JSON.stringify(googleEventBody(row)),
          });
          if (res.ok) {
            const patched = await res.json();
            // Record Google's new `updated` and freeze updated_at=runStart so the
            // echo is gated on the next pull and this row isn't re-selected next run.
            await admin
              .from("events")
              .update({ google_updated_at: patched.updated ?? null, updated_at: runStartISO })
              .eq("id", row.id)
              .eq("updated_at", row.updated_at);
          } else if (res.status === 404 || res.status === 410) {
            // gone on Google; leave the row for a future pull cancellation.
          } else {
            const text = (await res.text()).slice(0, 200);
            // Immutable event types (birthdays, etc.) reject PATCH with 400
            // eventTypeRestriction. They are API-immutable, so freeze the row so it
            // never re-qualifies — google_updated_at ≥ Google's own `updated` gates
            // the pull, updated_at=runStart (≤ next last_synced_at) gates the push —
            // and NEVER retry it.
            if (res.status === 400 && text.includes("eventTypeRestriction")) {
              const pulledUpdated = allUpserts.get(row.google_event_id)?.googleUpdatedISO ?? new Date().toISOString();
              await admin
                .from("events")
                .update({ google_updated_at: pulledUpdated, updated_at: runStartISO })
                .eq("id", row.id)
                .eq("updated_at", row.updated_at);
            }
            throw new Error(`google patch ${res.status}: ${text}`);
          }
        } catch (e) {
          pushErrors.push({ id: row.id, message: String((e as Error)?.message ?? e).slice(0, 200) });
        }
      }
    } else if (row.google_origin) {
      // Legacy detached origin row (null gid + origin=true) → NEVER re-create on
      // Google. The runner no longer produces this state (un-mirroring was removed
      // with the two-way delete); this guard only covers rows detached by the prior
      // logic, so they are never resurrected.
      continue;
    } else {
      // Not yet mirrored Atlas row → create with a deterministic id (idempotent).
      result.pushedNew++;
      if (!dryRun) {
        try {
          const gid = uuidToGoogleId(row.id);
          // Writes route OUT to the connection's primary calendar (reads fan in from all).
          const res = await fetch(`${GCAL_BASE}/calendars/${encodeURIComponent(primaryCalId)}/events`, {
            method: "POST",
            headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({ ...googleEventBody(row), id: gid }),
          });
          let googleUpdated: string | null = null;
          if (res.ok) {
            const created = await res.json();
            googleUpdated = created.updated ?? null;
          } else if (res.status !== 409) {
            // 409 = identifier already exists ⇒ a prior POST landed but write-back
            // didn't; treat as success (the next pull sets google_updated_at). Any
            // other non-2xx is a real error.
            throw new Error(`google insert ${res.status}: ${(await res.text()).slice(0, 200)}`);
          }
          // Write the (deterministic) id back, stamp the owning connection, and freeze
          // updated_at so we don't re-push. Optimistic on updated_at: if a concurrent
          // edit bumped it, this no-ops and the next run re-POSTs the SAME id → 409 →
          // converges (no duplicate).
          const patch: Record<string, unknown> = {
            google_event_id: gid,
            google_connection_id: conn.id,
            google_calendar_id: primaryCalId, // pushed to the primary calendar (0036)
            updated_at: runStartISO,
          };
          if (googleUpdated) patch.google_updated_at = googleUpdated;
          await admin.from("events").update(patch).eq("id", row.id).eq("updated_at", row.updated_at);
        } catch (e) {
          pushErrors.push({ id: row.id, message: String((e as Error)?.message ?? e).slice(0, 200) });
        }
      }
    }
  }

  // 4b. Reference pull (Docs → Notes import). Independent of the calendar sync,
  //     sharing the same access token (needs drive.file on the refresh token). Per-
  //     reference isolation mirrors PUSH — one file's failure is recorded and the loop
  //     continues; the run still completes and advances the connection.
  let refErrors: { id: string; message: string }[] = [];
  try {
    const refOut = await syncUserReferences(admin, userId, accessToken, runStartISO, dryRun);
    result.referencesChecked = refOut.checked;
    result.referencesSynced = refOut.synced;
    refErrors = refOut.errors;
  } catch (e) {
    // A pool-level failure (e.g. the references select) is non-fatal to the calendar
    // sync — record it and let step 5 still advance the connection.
    refErrors = [{ id: "*", message: String((e as Error)?.message ?? e).slice(0, 200) }];
  }

  // 5. Advance the cursor and release the lease. Per-event push failures DON'T fail
  //    the run — they complete it and record a truncated summary in last_error, and
  //    status stays 'active' so the connection keeps syncing.
  const errorParts: string[] = [];
  if (tombstoneErrors.length > 0) {
    errorParts.push(`delete: ${tombstoneErrors.length} event error(s): ${tombstoneErrors.map((e) => `${e.gid} ${e.message}`).join(" | ")}`);
  }
  if (pushErrors.length > 0) {
    errorParts.push(`push: ${pushErrors.length} event error(s): ${pushErrors.map((e) => `${e.id} ${e.message}`).join(" | ")}`);
  }
  if (refErrors.length > 0) {
    errorParts.push(`refs: ${refErrors.length} error(s): ${refErrors.map((e) => `${e.id} ${e.message}`).join(" | ")}`);
  }
  const errorSummary = errorParts.length > 0 ? errorParts.join(" || ").slice(0, 500) : null;
  if (errorSummary) result.error = errorSummary;
  if (!dryRun) {
    const { error } = await admin
      .from("google_connections")
      .update({ sync_token: newSyncToken, last_synced_at: runStartISO, status: "active", last_error: errorSummary, claimed_until: null })
      .eq("id", conn.id);
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

  // Service-role only. The pg_cron job (0008) invokes with the service key
  // directly, so require EXACT equality — no unsigned role-claim decode. Rejects
  // anon (role=anon) and user (role=authenticated) tokens.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token || token !== serviceKey) {
    return json({ error: "Forbidden" }, 401);
  }

  const dryRun = new URL(req.url).searchParams.get("dryRun") === "1";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Batch of due connections. dryRun reads read-only (no lease → no mutation); a
  // real run LEASES them atomically (I3: claim_google_sync_connections, for update
  // skip locked) so two overlapping ticks never process the same connection.
  let conns: Connection[] | null = null;
  let connErr: { message: string } | null = null;
  if (dryRun) {
    const r = await admin
      .from("google_connections")
      .select("id, user_id, vault_secret_id, calendar_id, space_id, sync_token, last_synced_at")
      .in("status", ["active", "error"]) // mirror claim_google_sync_connections (0010): error connections self-heal
      .order("last_synced_at", { ascending: true, nullsFirst: true })
      .limit(BATCH_LIMIT);
    conns = r.data as Connection[] | null;
    connErr = r.error;
  } else {
    const r = await admin.rpc("claim_google_sync_connections", { batch: BATCH_LIMIT });
    conns = r.data as Connection[] | null;
    connErr = r.error;
  }
  if (connErr) return json({ error: "Failed to load connections" }, 500);

  // Users fan out with bounded concurrency — they're fully independent (per-user
  // lease, per-user token, per-user rows), so the tick's wall-clock is the slowest
  // user, not the sum. Per-user isolation is preserved INSIDE the worker.
  const results: UserResult[] = await mapWithConcurrency(
    (conns ?? []) as Connection[],
    USER_CONCURRENCY,
    async (conn) => {
      try {
        return await syncUser(admin, conn, clientId, clientSecret, dryRun);
      } catch (e) {
        // Per-user isolation: one failure never blocks the batch. Release the lease
        // so a transient error retries next tick instead of waiting out claimed_until.
        const revoked = e instanceof InvalidGrantError;
        const msg = revoked ? "invalid_grant" : String((e as Error)?.message ?? e).slice(0, 500);
        if (!dryRun) {
          await admin
            .from("google_connections")
            .update({ status: revoked ? "revoked" : "error", last_error: msg, claimed_until: null })
            .eq("id", conn.id);
        }
        return {
          userId: conn.user_id,
          status: revoked ? "revoked" : "error",
          inserted: 0, updated: 0, deleted: 0, tombstoned: 0, pushedNew: 0, pushedUpdated: 0,
          referencesChecked: 0, referencesSynced: 0,
          fullResync: false, error: msg,
        };
      }
    },
  );

  return json({ ok: true, dryRun, count: results.length, users: results });
});
