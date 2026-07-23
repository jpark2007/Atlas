/**
 * Atlas — feeds-sync Edge Function (Deno)  ·  the multi-feed ICS pull runner
 *
 * The generalization of canvas-sync (0012 → 0040): one runner over N calendar
 * feeds per user (Canvas OR generic ICS — Schoology, a personal .ics, …), stored
 * in calendar_feeds (0040). Invoked by pg_cron (feeds-sync-every-15m, 0040) with
 * the service-role key. It leases a batch of due feeds (claim_calendar_feed_sync —
 * oldest last_synced_at first, single-flight via `for update skip locked`) and for
 * each does a conditional GET of the feed URL (If-None-Match / If-Modified-Since
 * from the stored etag/last_modified; 304 → nothing changed, done), then on 200
 * parses the ICS and upserts by (user_id, feed_id, canvas_uid):
 *
 *   feed_type='canvas'  → keep the Canvas split: assignment-style UIDs → TASKS
 *                         (due_date = DTSTART), other VEVENTs → EVENTS. SUMMARY
 *                         "[COURSE]" is extracted and routed to a matching project.
 *   feed_type='ics'     → EVERY VEVENT → an EVENT. No task split, no course routing;
 *                         project_id is null and everything lands in the feed's space.
 *
 * A feed is READ-ONLY — there is NO push path, and a UID vanishing from the feed is
 * NOT a deletion (feeds hide past items routinely) so rows are never deleted/reaped.
 *
 * USER-DATA-SAFE upserts (design §4). A brand-new UID inserts the full row; an
 * existing UID updates ONLY the feed-owned fields (title + due for tasks; title +
 * start/end — and canvas_course for canvas — for events) and NEVER touches
 * space_name, project_id, notes, done/status, or scheduled_at. Every insert stamps
 * feed_id + feed_type; the event subtitle is the FEED's display_name (not a
 * hardcoded "Canvas").
 *
 * Cross-function guard: every EVENT insert carries google_origin=true so the
 * google-sync runner (0006–0010) NEVER exports it to the user's Google Calendar
 * (a feed row also has a null google_event_id so no google-sync patch/delete path
 * matches it). Tasks are untouched by google-sync, so no equivalent guard is needed.
 *
 * Auth: service-role only. The bearer token MUST equal SUPABASE_SERVICE_ROLE_KEY or
 * the dedicated CRON_SECRET (the pg_cron caller's vault-stored credential can differ
 * in format from the platform-injected service key — accepting BOTH is what keeps the
 * cron from silently 401'ing every sync, the exact outage of commit 83df39a).
 *
 * Modes:  POST /functions/v1/feeds-sync            → run (reads feeds + writes DB; leases)
 *         POST /functions/v1/feeds-sync?dryRun=1   → read feeds + log intended writes,
 *                                                     write NOTHING (and does NOT lease).
 *
 * Env (auto-injected):  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy feeds-sync --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { safeFetch } from "../_shared/url_guard.ts";
import {
  parseICS,
  extractCourse,
  matchProject,
  type Project,
} from "../_shared/ics.ts";

const BATCH_LIMIT = 20; // feeds processed per invocation (oldest first)

// Bounds on ONE feed per tick so a pathological/hostile feed can't blow the
// function's memory or time budget. A real student's semester feed is well under
// both: a few hundred KB, a few hundred events.
const MAX_FEED_BYTES = 5 * 1024 * 1024; // 5 MB of ICS text
const MAX_ICS_EVENTS = 2000;            // events parsed/written per feed per tick

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

// A bad/reset feed URL — the capability token was rotated by the user. Needs a
// re-paste, so the feed is parked 'revoked' (excluded from the claim RPC) rather
// than 'error' (which self-heals). Mirrors google-sync's InvalidGrantError.
class RevokedError extends Error {}

// ── Types ────────────────────────────────────────────────────────
interface Feed {
  id: string;
  user_id: string;
  feed_type: string; // 'canvas' | 'ics'
  display_name: string;
  space_name: string;
  vault_secret_id: string | null;
  last_synced_at: string | null;
  etag: string | null;
  last_modified: string | null;
}

interface FeedResult {
  feedId: string;
  userId: string;
  feedType: string;
  status: string;
  notModified: boolean;
  tasksInserted: number;
  tasksUpdated: number;
  eventsInserted: number;
  eventsUpdated: number;
  error?: string;
}

// ── One feed's sync ─────────────────────────────────────────────
async function syncFeed(admin: SupabaseClient, feed: Feed, dryRun: boolean): Promise<FeedResult> {
  const userId = feed.user_id;
  const feedId = feed.id;
  const isCanvas = feed.feed_type === "canvas";
  const runStartISO = new Date().toISOString();
  const result: FeedResult = {
    feedId,
    userId,
    feedType: feed.feed_type,
    status: "active",
    notModified: false,
    tasksInserted: 0,
    tasksUpdated: 0,
    eventsInserted: 0,
    eventsUpdated: 0,
  };

  if (!feed.vault_secret_id) throw new Error("feed has no vault_secret_id");

  // 1. Decrypt the feed URL (service-role Vault read).
  const { data: feedUrl, error: secretErr } = await admin.rpc("read_canvas_secret", { secret_id: feed.vault_secret_id });
  if (secretErr || !feedUrl) throw new Error("vault read failed");

  // 2. Conditional GET. safeFetch guards against SSRF (the feed URL is user-pasted):
  //    it rejects any host resolving to a private/loopback/link-local address,
  //    re-validates each redirect hop, and bounds the whole fetch with a 30s timeout.
  const reqHeaders: Record<string, string> = {};
  if (feed.etag) reqHeaders["If-None-Match"] = feed.etag;
  if (feed.last_modified) reqHeaders["If-Modified-Since"] = feed.last_modified;
  const res = await safeFetch(feedUrl as string, { headers: reqHeaders }, { timeoutMs: 30_000 });

  if (res.status === 304) {
    result.notModified = true;
    if (!dryRun) {
      const { error } = await admin
        .from("calendar_feeds")
        .update({ last_synced_at: runStartISO, status: "active", last_error: null, claimed_until: null })
        .eq("id", feedId);
      if (error) throw new Error(`feed update failed: ${error.message}`);
    }
    return result;
  }
  if (res.status === 401 || res.status === 403 || res.status === 404 || res.status === 410) {
    throw new RevokedError(`feed fetch ${res.status}`); // capability URL reset → needs re-paste
  }
  if (!res.ok) throw new Error(`feed fetch ${res.status}: ${(await res.text()).slice(0, 200)}`);

  const newEtag = res.headers.get("etag");
  const newLastModified = res.headers.get("last-modified");

  // Cap the feed body — refuse an absurdly large ICS rather than buffering it all.
  const declaredLen = Number(res.headers.get("content-length"));
  if (Number.isFinite(declaredLen) && declaredLen > MAX_FEED_BYTES) {
    await res.body?.cancel();
    throw new Error(`feed too large: ${declaredLen} bytes`);
  }
  const feedText = await res.text();
  if (feedText.length > MAX_FEED_BYTES) {
    throw new Error(`feed too large: ${feedText.length} bytes`);
  }

  // Cap events processed per tick. Safety ceiling well above any real feed; beyond
  // it the extras are dropped for this run and the count is reported in last_error.
  let vevents = parseICS(feedText);
  let eventsOverCap = 0;
  if (vevents.length > MAX_ICS_EVENTS) {
    eventsOverCap = vevents.length - MAX_ICS_EVENTS;
    vevents = vevents.slice(0, MAX_ICS_EVENTS);
  }

  // 3. Canvas feeds route to projects via the SUMMARY "[COURSE]"; generic ICS feeds
  //    never route (project_id null), so their projects load is skipped.
  let projects: Project[] = [];
  if (isCanvas) {
    const { data: projRows, error: projErr } = await admin
      .from("projects")
      .select("id, space_name, name, code, canvas_course")
      .eq("user_id", userId);
    if (projErr) throw new Error(`projects select failed: ${projErr.message}`);
    projects = (projRows ?? []) as Project[];
  }

  // 4. Map feed → per-table payloads keyed by canvas_uid.
  interface TaskPayload { title: string; due_date: string; space_name: string; project_id: string | null; canvas_course: string | null }
  interface EventPayload { title: string; start_at: string; end_at: string; is_all_day: boolean; space_name: string; project_id: string | null; canvas_course: string | null }
  const taskByUid = new Map<string, TaskPayload>();
  const eventByUid = new Map<string, EventPayload>();

  for (const ve of vevents) {
    if (!ve.uid || !ve.dtstart) continue; // unusable without a stable key + a time

    if (isCanvas) {
      const { title, code } = extractCourse(ve.summary ?? "");
      const matched = matchProject(code, projects);
      const spaceName = matched ? matched.space_name : feed.space_name;
      const projectId = matched ? matched.id : null;
      const cleanTitle = title || "Untitled";
      if (/assignment/i.test(ve.uid)) {
        taskByUid.set(ve.uid, { title: cleanTitle, due_date: ve.dtstart.iso, space_name: spaceName, project_id: projectId, canvas_course: code });
      } else {
        const endISO = ve.dtend?.iso ?? ve.dtstart.iso; // no DTEND → zero-length at start
        eventByUid.set(ve.uid, { title: cleanTitle, start_at: ve.dtstart.iso, end_at: endISO, is_all_day: ve.dtstart.allDay, space_name: spaceName, project_id: projectId, canvas_course: code });
      }
    } else {
      // Generic ICS: every VEVENT is an EVENT in the feed's space, no course routing.
      const cleanTitle = (ve.summary ?? "").trim() || "Untitled";
      const endISO = ve.dtend?.iso ?? ve.dtstart.iso;
      eventByUid.set(ve.uid, { title: cleanTitle, start_at: ve.dtstart.iso, end_at: endISO, is_all_day: ve.dtstart.allDay, space_name: feed.space_name, project_id: null, canvas_course: null });
    }
  }

  // Per-item isolation: one bad row is recorded and skipped, never failing the run.
  const itemErrors: string[] = [];
  if (eventsOverCap > 0) {
    itemErrors.push(`${eventsOverCap} feed item(s) over the ${MAX_ICS_EVENTS}/tick cap were skipped`);
  }

  // 5a. TASKS (canvas only) — split new UIDs (full insert) vs existing (feed-owned only).
  const taskUids = [...taskByUid.keys()];
  if (taskUids.length > 0) {
    const { data: rows, error } = await admin
      .from("tasks")
      .select("id, canvas_uid")
      .eq("user_id", userId)
      .eq("feed_id", feedId)
      .in("canvas_uid", taskUids);
    if (error) throw new Error(`tasks select failed: ${error.message}`);
    const existingTaskUids = new Set<string>();
    for (const r of (rows ?? []) as { id: string; canvas_uid: string }[]) existingTaskUids.add(r.canvas_uid);

    const taskInserts: Record<string, unknown>[] = [];
    for (const [uid, t] of taskByUid) {
      if (existingTaskUids.has(uid)) {
        // USER-DATA-SAFE: update ONLY feed-owned fields — title, due_date, canvas_course.
        result.tasksUpdated++;
        if (!dryRun) {
          const { error: uErr } = await admin
            .from("tasks")
            .update({ title: t.title, due_date: t.due_date, canvas_course: t.canvas_course })
            .eq("user_id", userId)
            .eq("feed_id", feedId)
            .eq("canvas_uid", uid);
          if (uErr) itemErrors.push(`task ${uid}: ${uErr.message}`.slice(0, 160));
        }
      } else {
        taskInserts.push({
          id: crypto.randomUUID(),
          user_id: userId,
          feed_id: feedId,
          feed_type: feed.feed_type,
          space_name: t.space_name,
          project_id: t.project_id,
          title: t.title,
          due_date: t.due_date,
          canvas_uid: uid,
          canvas_course: t.canvas_course,
        });
      }
    }
    result.tasksInserted = taskInserts.length;
    if (!dryRun && taskInserts.length > 0) {
      const { error: iErr } = await admin.from("tasks").upsert(taskInserts, { onConflict: "user_id,feed_id,canvas_uid", ignoreDuplicates: true });
      if (iErr) throw new Error(`tasks insert failed: ${iErr.message}`);
    }
  }

  // 5b. EVENTS — same split. Inserts carry google_origin=true (never export to Google)
  //     and subtitle = the feed's display_name.
  const eventUids = [...eventByUid.keys()];
  if (eventUids.length > 0) {
    const { data: rows, error } = await admin
      .from("events")
      .select("id, canvas_uid")
      .eq("user_id", userId)
      .eq("feed_id", feedId)
      .in("canvas_uid", eventUids);
    if (error) throw new Error(`events select failed: ${error.message}`);
    const existingEventUids = new Set<string>();
    for (const r of (rows ?? []) as { id: string; canvas_uid: string }[]) existingEventUids.add(r.canvas_uid);

    const eventInserts: Record<string, unknown>[] = [];
    for (const [uid, e] of eventByUid) {
      if (existingEventUids.has(uid)) {
        // USER-DATA-SAFE: update ONLY feed-owned fields — title, start/end (+ canvas_course
        // for canvas). is_all_day/space/project/notes untouched.
        result.eventsUpdated++;
        if (!dryRun) {
          const patch: Record<string, unknown> = { title: e.title, start_at: e.start_at, end_at: e.end_at };
          if (isCanvas) patch.canvas_course = e.canvas_course;
          const { error: uErr } = await admin
            .from("events")
            .update(patch)
            .eq("user_id", userId)
            .eq("feed_id", feedId)
            .eq("canvas_uid", uid);
          if (uErr) itemErrors.push(`event ${uid}: ${uErr.message}`.slice(0, 160));
        }
      } else {
        eventInserts.push({
          id: crypto.randomUUID(),
          user_id: userId,
          feed_id: feedId,
          feed_type: feed.feed_type,
          space_name: e.space_name,
          project_id: e.project_id,
          title: e.title,
          subtitle: feed.display_name, // the feed's name (NOT a hardcoded "Canvas")
          start_at: e.start_at,
          end_at: e.end_at,
          is_all_day: e.is_all_day,
          canvas_uid: uid,
          canvas_course: e.canvas_course,
          google_origin: true, // guard: google-sync must never push a feed event to Google
        });
      }
    }
    result.eventsInserted = eventInserts.length;
    if (!dryRun && eventInserts.length > 0) {
      const { error: iErr } = await admin.from("events").upsert(eventInserts, { onConflict: "user_id,feed_id,canvas_uid", ignoreDuplicates: true });
      if (iErr) throw new Error(`events insert failed: ${iErr.message}`);
    }
  }

  // 6. Advance the conditional-GET cache + release the lease. Per-item update errors
  //    don't fail the run — they're summarized in last_error (status stays active).
  const errorSummary = itemErrors.length > 0
    ? `${itemErrors.length} item error(s): ${itemErrors.join(" | ")}`.slice(0, 500)
    : null;
  if (errorSummary) result.error = errorSummary;
  if (!dryRun) {
    const { error } = await admin
      .from("calendar_feeds")
      .update({
        last_synced_at: runStartISO,
        etag: newEtag,
        last_modified: newLastModified,
        status: "active",
        last_error: errorSummary,
        claimed_until: null,
      })
      .eq("id", feedId);
    if (error) throw new Error(`feed update failed: ${error.message}`);
  }

  return result;
}

// ── HTTP entry ──────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Server not configured" }, 500);

  // Service-role only. The pg_cron job invokes with a token from Vault, so require
  // EXACT equality — no unsigned role-claim decode. Rejects anon + user tokens. The
  // platform-injected SUPABASE_SERVICE_ROLE_KEY format can differ from the vault-stored
  // cron credential, so cron auth ALSO accepts the dedicated CRON_SECRET. Accepting
  // BOTH is critical — missing it silently 401s all sync (the outage of commit 83df39a).
  const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token || (token !== serviceKey && !(cronSecret && token === cronSecret))) {
    return json({ error: "Forbidden" }, 401);
  }

  const dryRun = new URL(req.url).searchParams.get("dryRun") === "1";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // dryRun reads read-only (no lease → no mutation); a real run LEASES atomically
  // (claim_calendar_feed_sync, for update skip locked) so overlapping ticks never
  // process the same feed.
  let feeds: Feed[] | null = null;
  let feedsErr: { message: string } | null = null;
  if (dryRun) {
    const r = await admin
      .from("calendar_feeds")
      .select("id, user_id, feed_type, display_name, space_name, vault_secret_id, last_synced_at, etag, last_modified")
      .in("status", ["active", "error"])
      .order("last_synced_at", { ascending: true, nullsFirst: true })
      .limit(BATCH_LIMIT);
    feeds = r.data as Feed[] | null;
    feedsErr = r.error;
  } else {
    const r = await admin.rpc("claim_calendar_feed_sync", { batch: BATCH_LIMIT });
    feeds = r.data as Feed[] | null;
    feedsErr = r.error;
  }
  if (feedsErr) return json({ error: "Failed to load feeds" }, 500);

  const results: FeedResult[] = [];
  for (const feed of (feeds ?? []) as Feed[]) {
    try {
      results.push(await syncFeed(admin, feed, dryRun));
    } catch (e) {
      // Per-feed isolation: one failure never blocks the batch. Release the lease so
      // a transient error retries next tick; a revoked feed URL parks until re-pasted.
      const revoked = e instanceof RevokedError;
      const msg = revoked ? "feed_url_revoked" : String((e as Error)?.message ?? e).slice(0, 500);
      if (!dryRun) {
        await admin
          .from("calendar_feeds")
          .update({ status: revoked ? "revoked" : "error", last_error: msg, claimed_until: null })
          .eq("id", feed.id);
      }
      results.push({
        feedId: feed.id,
        userId: feed.user_id,
        feedType: feed.feed_type,
        status: revoked ? "revoked" : "error",
        notModified: false,
        tasksInserted: 0, tasksUpdated: 0, eventsInserted: 0, eventsUpdated: 0,
        error: msg,
      });
    }
  }

  return json({ ok: true, dryRun, count: results.length, feeds: results });
});
