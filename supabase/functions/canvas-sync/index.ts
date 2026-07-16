/**
 * Atlas — canvas-sync Edge Function (Deno)  ·  the Canvas ICS pull runner
 *
 * Invoked by pg_cron (0012) every 15 minutes with the service-role key. It leases
 * a batch of due canvas_connections rows (claim_canvas_sync_users, 0012 — oldest
 * last_synced_at first, single-flight via `for update skip locked`) and for each:
 *   PULL  Canvas feed → Supabase. A conditional GET of the user's ICS feed URL
 *         (If-None-Match/If-Modified-Since from the stored etag/last_modified;
 *         304 → nothing changed, done). On 200, parse the ICS in TypeScript and
 *         upsert by (user_id, canvas_uid):
 *           • assignment-style VEVENTs (UID contains "assignment") → TASKS,
 *             due_date = DTSTART.
 *           • every other VEVENT → EVENTS, start/end = DTSTART/DTEND.
 *
 * Canvas is READ-ONLY — there is NO push path (we never write to Canvas), and a
 * UID vanishing from the feed is NOT a deletion (Canvas hides past items
 * routinely) so rows are never deleted or reaped.
 *
 * USER-DATA-SAFE upserts (design §4). A brand-new UID inserts the full row;
 * an existing UID updates ONLY the feed-owned fields (title + due for tasks;
 * title + start/end for events) and NEVER touches space_name, project_id, notes,
 * done/status, or scheduled_at. So a task completed in Atlas stays completed even
 * if Canvas re-lists it, and a user's re-filing/notes survive every sync.
 *
 * Course→project routing (ports the client matcher, commit a0e36ac): the course
 * code in the SUMMARY's trailing "[...]" is normalized (strip spaces, uppercase)
 * and matched to the user's projects — primary on projects.code, secondary on an
 * exact case-insensitive projects.name. A match files the item under that project
 * (project_id + its space); no match files it under the connection's space_name
 * with no project (the always-works "floor").
 *
 * Cross-function guard: a Canvas EVENT row is inserted with google_origin=true so
 * the google-sync runner (0006–0010) NEVER exports it to the user's Google
 * Calendar. google_origin is the "must never push to Google" authority bit (0007);
 * a Canvas row has a null google_event_id so no google-sync delete/patch path ever
 * matches it either. Without this, a user with BOTH connections would see every
 * Canvas event pushed into Google as an Atlas-created event. (tasks are untouched
 * by google-sync, so no equivalent guard is needed there.)
 *
 * Auth: service-role only. The bearer token MUST equal SUPABASE_SERVICE_ROLE_KEY
 * or be a service_role JWT (rejects anon / user JWTs). The cron is the caller.
 *
 * Modes:  POST /functions/v1/canvas-sync            → run (reads feed + writes DB; leases users)
 *         POST /functions/v1/canvas-sync?dryRun=1   → read feed + log intended writes,
 *                                                      write NOTHING (DB or connection
 *                                                      rows — and does NOT lease).
 *
 * Env (all SUPABASE_* auto-injected):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *
 * Deploy: supabase functions deploy canvas-sync --project-ref jxrmozhgsebwtbdleyxp
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { safeFetch } from "../_shared/url_guard.ts";

const BATCH_LIMIT = 20; // connections processed per invocation (oldest first)

// Bounds on ONE Canvas feed per tick so a pathological/hostile feed can't blow the
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
// re-paste, so the connection is parked 'revoked' (excluded from the claim RPC)
// rather than 'error' (which self-heals). Mirrors google-sync's InvalidGrantError.
class RevokedError extends Error {}

// ── ICS parsing (RFC 5545 subset Canvas emits) ──────────────────

/** RFC 5545 line unfolding: a continuation line begins with SPACE or TAB; join it
 *  to the previous logical line, dropping that one leading whitespace char. */
function unfold(raw: string): string[] {
  const physical = raw.split(/\r\n|\r|\n/);
  const out: string[] = [];
  for (const line of physical) {
    if (out.length > 0 && (line.startsWith(" ") || line.startsWith("\t"))) {
      out[out.length - 1] += line.slice(1);
    } else {
      out.push(line);
    }
  }
  return out;
}

/** RFC 5545 TEXT unescape: \\n / \\N → newline, \\, → comma, \\; → semicolon,
 *  \\\\ → backslash. Single pass so an escaped backslash never re-triggers. */
function unescapeText(v: string): string {
  let out = "";
  for (let i = 0; i < v.length; i++) {
    if (v[i] === "\\" && i + 1 < v.length) {
      const n = v[i + 1];
      if (n === "n" || n === "N") out += "\n";
      else if (n === "," || n === ";" || n === "\\") out += n;
      else out += n; // unknown escape → keep the escaped char literally
      i++;
    } else {
      out += v[i];
    }
  }
  return out;
}

interface PropLine {
  name: string;
  params: Map<string, string>;
  value: string;
}

/** Parse one unfolded content line "NAME;PARAM=VAL;…:VALUE" into name/params/value.
 *  Splits on the first colon and semicolons that are NOT inside a quoted string. */
function parseLine(line: string): PropLine | null {
  let inQuote = false;
  let colon = -1;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') inQuote = !inQuote;
    else if (c === ":" && !inQuote) { colon = i; break; }
  }
  if (colon === -1) return null;
  const left = line.slice(0, colon);
  const value = line.slice(colon + 1);

  const parts: string[] = [];
  let cur = "";
  inQuote = false;
  for (const c of left) {
    if (c === '"') { inQuote = !inQuote; cur += c; }
    else if (c === ";" && !inQuote) { parts.push(cur); cur = ""; }
    else cur += c;
  }
  parts.push(cur);

  const name = parts[0].toUpperCase();
  const params = new Map<string, string>();
  for (let i = 1; i < parts.length; i++) {
    const eq = parts[i].indexOf("=");
    if (eq > 0) {
      params.set(parts[i].slice(0, eq).toUpperCase(), parts[i].slice(eq + 1).replace(/^"|"$/g, ""));
    }
  }
  return { name, params, value };
}

/** Offset (localWall − UTC) in ms of `tzid` at the instant `utcDate`. Uses Intl
 *  formatToParts to read the zone's wall-clock, then differences it against UTC. */
function tzOffsetMs(tzid: string, utcDate: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tzid, hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const p: Record<string, string> = {};
  for (const part of dtf.formatToParts(utcDate)) p[part.type] = part.value;
  let hour = Number(p.hour);
  if (hour === 24) hour = 0; // some engines render midnight as 24
  const asUTC = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), hour, Number(p.minute), Number(p.second));
  return asUTC - utcDate.getTime();
}

/** Wall-clock time in `tzid` → the UTC instant. Two-pass to land DST transitions
 *  correctly. Returns null if the TZID is unknown (Intl throws). */
function zonedWallToUTC(y: number, mo: number, d: number, h: number, mi: number, s: number, tzid: string): Date | null {
  try {
    const guess = Date.UTC(y, mo - 1, d, h, mi, s);
    let utc = guess - tzOffsetMs(tzid, new Date(guess));
    utc = guess - tzOffsetMs(tzid, new Date(utc)); // refine across a DST edge
    return new Date(utc);
  } catch {
    return null;
  }
}

interface ICSDate {
  iso: string;
  allDay: boolean;
}

/**
 * Parse a DTSTART/DTEND value + params into a UTC ISO instant.
 *   • VALUE=DATE "YYYYMMDD"            → all-day → UTC midnight of that date
 *                                        (the app's server all-day convention,
 *                                        identical to google-sync's interval()).
 *   • "YYYYMMDDTHHMMSSZ"               → exact UTC instant.
 *   • TZID=Zone; "YYYYMMDDTHHMMSS"     → wall time resolved through the zone → UTC.
 *   • floating "YYYYMMDDTHHMMSS"       → no tz on the server → read as UTC.
 */
function parseICSDate(value: string, params: Map<string, string>): ICSDate | null {
  const m = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
  if (!m) return null;
  const [, y, mo, d, hh, mi, ss, z] = m;
  const isDate = params.get("VALUE") === "DATE" || !hh;
  if (isDate) {
    return { iso: `${y}-${mo}-${d}T00:00:00.000Z`, allDay: true };
  }
  if (z === "Z") {
    return { iso: new Date(`${y}-${mo}-${d}T${hh}:${mi}:${ss}Z`).toISOString(), allDay: false };
  }
  const tzid = params.get("TZID");
  if (tzid) {
    const inst = zonedWallToUTC(Number(y), Number(mo), Number(d), Number(hh), Number(mi), Number(ss), tzid);
    if (inst) return { iso: inst.toISOString(), allDay: false };
  }
  // Floating: no Z, no (valid) TZID. The server has no per-user tz — read as UTC.
  return { iso: new Date(`${y}-${mo}-${d}T${hh}:${mi}:${ss}Z`).toISOString(), allDay: false };
}

interface VEvent {
  uid?: string;
  summary?: string;
  description?: string;
  location?: string;
  url?: string;
  dtstart?: ICSDate | null;
  dtend?: ICSDate | null;
}

/** ICS text → the VEVENTs it contains (only the fields Canvas populates). */
function parseICS(raw: string): VEvent[] {
  const events: VEvent[] = [];
  let cur: VEvent | null = null;
  for (const line of unfold(raw)) {
    if (line === "BEGIN:VEVENT") { cur = {}; continue; }
    if (line === "END:VEVENT") { if (cur) events.push(cur); cur = null; continue; }
    if (!cur) continue;
    const p = parseLine(line);
    if (!p) continue;
    switch (p.name) {
      case "UID":         cur.uid = p.value.trim(); break;
      case "SUMMARY":     cur.summary = unescapeText(p.value); break;
      case "DESCRIPTION": cur.description = unescapeText(p.value); break;
      case "LOCATION":    cur.location = unescapeText(p.value); break;
      case "URL":         cur.url = p.value.trim(); break;
      case "DTSTART":     cur.dtstart = parseICSDate(p.value, p.params); break;
      case "DTEND":       cur.dtend = parseICSDate(p.value, p.params); break;
    }
  }
  return events;
}

// ── Course → project routing (ports the client matcher, a0e36ac) ─
interface Project {
  id: string;
  space_name: string;
  name: string;
  code: string | null;
  canvas_course: string | null; // explicit course link (0032); overrides code/name match
}

/** normalize a course code the way the client matcher did: strip whitespace, uppercase. */
function normalizeCode(s: string): string {
  return s.replace(/\s+/g, "").toUpperCase();
}

/** Split a Canvas SUMMARY "Title [COURSE CODE]" into a clean title + the bracket. */
function extractCourse(summary: string): { title: string; code: string | null } {
  const m = summary.match(/\s*\[([^\]]+)\]\s*$/);
  if (!m || m.index === undefined) return { title: summary.trim(), code: null };
  return { title: summary.slice(0, m.index).trim(), code: m[1].trim() };
}

/** Match a bracket course label to a project. An explicit user link (0032:
 *  projects.canvas_course, set from this same feed label in the Mac class picker)
 *  wins outright; otherwise the auto match — code first (normalized), then exact
 *  name. The explicit link is how a course whose bracket matches no code/name still
 *  files under the right class. */
function matchProject(label: string | null, projects: Project[]): Project | null {
  if (!label) return null;
  for (const p of projects) {
    if (p.canvas_course && p.canvas_course === label) return p; // explicit user link
  }
  const nc = normalizeCode(label);
  const nn = label.toLowerCase().trim();
  for (const p of projects) {
    if (p.code && normalizeCode(p.code) === nc) return p; // primary: code
  }
  for (const p of projects) {
    if (p.name.toLowerCase().trim() === nn) return p;       // secondary: exact name
  }
  return null;
}

// ── Types ────────────────────────────────────────────────────────
interface Connection {
  user_id: string;
  vault_secret_id: string | null;
  space_name: string;
  last_synced_at: string | null;
  etag: string | null;
  last_modified: string | null;
}

interface UserResult {
  userId: string;
  status: string;
  notModified: boolean;
  tasksInserted: number;
  tasksUpdated: number;
  eventsInserted: number;
  eventsUpdated: number;
  error?: string;
}

// ── One user's sync ─────────────────────────────────────────────
async function syncUser(admin: SupabaseClient, conn: Connection, dryRun: boolean): Promise<UserResult> {
  const userId = conn.user_id;
  const runStartISO = new Date().toISOString();
  const result: UserResult = {
    userId,
    status: "active",
    notModified: false,
    tasksInserted: 0,
    tasksUpdated: 0,
    eventsInserted: 0,
    eventsUpdated: 0,
  };

  if (!conn.vault_secret_id) throw new Error("connection has no vault_secret_id");

  // 1. Decrypt the feed URL (service-role Vault read).
  const { data: feedUrl, error: secretErr } = await admin.rpc("read_canvas_secret", { secret_id: conn.vault_secret_id });
  if (secretErr || !feedUrl) throw new Error("vault read failed");

  // 2. Conditional GET. Canvas feeds are big and change rarely; a 304 is the common case.
  //    safeFetch guards against SSRF (the feed URL is user-pasted): it rejects any
  //    host resolving to a private/loopback/link-local address, re-validates each
  //    redirect hop, and bounds the whole fetch with a 30s timeout.
  const reqHeaders: Record<string, string> = {};
  if (conn.etag) reqHeaders["If-None-Match"] = conn.etag;
  if (conn.last_modified) reqHeaders["If-Modified-Since"] = conn.last_modified;
  const res = await safeFetch(feedUrl as string, { headers: reqHeaders }, { timeoutMs: 30_000 });

  if (res.status === 304) {
    result.notModified = true;
    if (!dryRun) {
      const { error } = await admin
        .from("canvas_connections")
        .update({ last_synced_at: runStartISO, status: "active", last_error: null, claimed_until: null })
        .eq("user_id", userId);
      if (error) throw new Error(`connection update failed: ${error.message}`);
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

  // Cap events processed per tick. This is a safety ceiling well above any real
  // Canvas feed; beyond it the extras are dropped for this run and the count is
  // reported in the connection's last_error (a >2000-item feed is anomalous).
  let vevents = parseICS(feedText);
  let eventsOverCap = 0;
  if (vevents.length > MAX_ICS_EVENTS) {
    eventsOverCap = vevents.length - MAX_ICS_EVENTS;
    vevents = vevents.slice(0, MAX_ICS_EVENTS);
  }

  // 3. Load the user's projects once for course routing.
  const { data: projRows, error: projErr } = await admin
    .from("projects")
    .select("id, space_name, name, code, canvas_course")
    .eq("user_id", userId);
  if (projErr) throw new Error(`projects select failed: ${projErr.message}`);
  const projects = (projRows ?? []) as Project[];

  // 4. Map feed → per-table payloads keyed by canvas_uid. Assignment-style UIDs → tasks.
  interface TaskPayload { title: string; due_date: string; space_name: string; project_id: string | null; canvas_course: string | null; allDay: boolean }
  interface EventPayload { title: string; start_at: string; end_at: string; is_all_day: boolean; space_name: string; project_id: string | null; canvas_course: string | null }
  const taskByUid = new Map<string, TaskPayload>();
  const eventByUid = new Map<string, EventPayload>();

  for (const ve of vevents) {
    if (!ve.uid || !ve.dtstart) continue; // unusable without a stable key + a time
    const { title, code } = extractCourse(ve.summary ?? "");
    const matched = matchProject(code, projects);
    const spaceName = matched ? matched.space_name : conn.space_name;
    const projectId = matched ? matched.id : null;
    const cleanTitle = title || "Untitled";

    if (/assignment/i.test(ve.uid)) {
      taskByUid.set(ve.uid, { title: cleanTitle, due_date: ve.dtstart.iso, space_name: spaceName, project_id: projectId, canvas_course: code, allDay: ve.dtstart.allDay });
    } else {
      const endISO = ve.dtend?.iso ?? ve.dtstart.iso; // no DTEND → zero-length at start
      eventByUid.set(ve.uid, { title: cleanTitle, start_at: ve.dtstart.iso, end_at: endISO, is_all_day: ve.dtstart.allDay, space_name: spaceName, project_id: projectId, canvas_course: code });
    }
  }

  // Per-item isolation: one bad row is recorded and skipped, never failing the run.
  const itemErrors: string[] = [];
  if (eventsOverCap > 0) {
    itemErrors.push(`${eventsOverCap} feed item(s) over the ${MAX_ICS_EVENTS}/tick cap were skipped`);
  }

  // 5a. TASKS — split new UIDs (full insert) vs existing (feed-owned fields only).
  const taskUids = [...taskByUid.keys()];
  const existingTaskUids = new Set<string>();
  if (taskUids.length > 0) {
    const { data: rows, error } = await admin
      .from("tasks")
      .select("id, canvas_uid")
      .eq("user_id", userId)
      .in("canvas_uid", taskUids);
    if (error) throw new Error(`tasks select failed: ${error.message}`);
    for (const r of (rows ?? []) as { id: string; canvas_uid: string }[]) existingTaskUids.add(r.canvas_uid);

    const taskInserts: Record<string, unknown>[] = [];
    for (const [uid, t] of taskByUid) {
      if (existingTaskUids.has(uid)) {
        // USER-DATA-SAFE: update ONLY feed-owned fields — title, due_date, and
        // canvas_course (the course label; deterministic from the feed, backfills
        // pre-0032 rows so the picker/remap can see them). space_name/project_id/
        // done/status/notes/scheduled_at are user territory and are never touched.
        result.tasksUpdated++;
        if (!dryRun) {
          const { error: uErr } = await admin
            .from("tasks")
            .update({ title: t.title, due_date: t.due_date, canvas_course: t.canvas_course })
            .eq("user_id", userId)
            .eq("canvas_uid", uid);
          if (uErr) itemErrors.push(`task ${uid}: ${uErr.message}`.slice(0, 160));
        }
      } else {
        taskInserts.push({
          id: crypto.randomUUID(),
          user_id: userId,
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
      // ignoreDuplicates ⇒ ON CONFLICT DO NOTHING: a UID that raced in stays untouched
      // (its user data preserved) — the update branch above owns field changes.
      const { error: iErr } = await admin.from("tasks").upsert(taskInserts, { onConflict: "user_id,canvas_uid", ignoreDuplicates: true });
      if (iErr) throw new Error(`tasks insert failed: ${iErr.message}`);
    }
  }

  // 5b. EVENTS — same split. Inserts carry google_origin=true (never export to Google).
  const eventUids = [...eventByUid.keys()];
  const existingEventUids = new Set<string>();
  if (eventUids.length > 0) {
    const { data: rows, error } = await admin
      .from("events")
      .select("id, canvas_uid")
      .eq("user_id", userId)
      .in("canvas_uid", eventUids);
    if (error) throw new Error(`events select failed: ${error.message}`);
    for (const r of (rows ?? []) as { id: string; canvas_uid: string }[]) existingEventUids.add(r.canvas_uid);

    const eventInserts: Record<string, unknown>[] = [];
    for (const [uid, e] of eventByUid) {
      if (existingEventUids.has(uid)) {
        // USER-DATA-SAFE: update ONLY feed-owned fields — title, start/end, and
        // canvas_course (backfills pre-0032 rows). is_all_day/space/project/notes untouched.
        result.eventsUpdated++;
        if (!dryRun) {
          const { error: uErr } = await admin
            .from("events")
            .update({ title: e.title, start_at: e.start_at, end_at: e.end_at, canvas_course: e.canvas_course })
            .eq("user_id", userId)
            .eq("canvas_uid", uid);
          if (uErr) itemErrors.push(`event ${uid}: ${uErr.message}`.slice(0, 160));
        }
      } else {
        eventInserts.push({
          id: crypto.randomUUID(),
          user_id: userId,
          space_name: e.space_name,
          project_id: e.project_id,
          title: e.title,
          subtitle: "Canvas",
          start_at: e.start_at,
          end_at: e.end_at,
          is_all_day: e.is_all_day,
          canvas_uid: uid,
          canvas_course: e.canvas_course,
          google_origin: true, // guard: google-sync must never push a Canvas event to Google
        });
      }
    }
    result.eventsInserted = eventInserts.length;
    if (!dryRun && eventInserts.length > 0) {
      const { error: iErr } = await admin.from("events").upsert(eventInserts, { onConflict: "user_id,canvas_uid", ignoreDuplicates: true });
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
      .from("canvas_connections")
      .update({
        last_synced_at: runStartISO,
        etag: newEtag,
        last_modified: newLastModified,
        status: "active",
        last_error: errorSummary,
        claimed_until: null,
      })
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
  if (!supabaseUrl || !serviceKey) return json({ error: "Server not configured" }, 500);

  // Service-role only (mirrors google-sync). The pg_cron job (0012) invokes with
  // the service key directly, so require EXACT equality — no unsigned role-claim
  // decode. Rejects anon + user tokens.
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token || token !== serviceKey) {
    return json({ error: "Forbidden" }, 401);
  }

  const dryRun = new URL(req.url).searchParams.get("dryRun") === "1";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // dryRun reads read-only (no lease → no mutation); a real run LEASES atomically
  // (claim_canvas_sync_users, for update skip locked) so overlapping ticks never
  // process the same user.
  let conns: Connection[] | null = null;
  let connErr: { message: string } | null = null;
  if (dryRun) {
    const r = await admin
      .from("canvas_connections")
      .select("user_id, vault_secret_id, space_name, last_synced_at, etag, last_modified")
      .in("status", ["active", "error"])
      .order("last_synced_at", { ascending: true, nullsFirst: true })
      .limit(BATCH_LIMIT);
    conns = r.data as Connection[] | null;
    connErr = r.error;
  } else {
    const r = await admin.rpc("claim_canvas_sync_users", { batch: BATCH_LIMIT });
    conns = r.data as Connection[] | null;
    connErr = r.error;
  }
  if (connErr) return json({ error: "Failed to load connections" }, 500);

  const results: UserResult[] = [];
  for (const conn of (conns ?? []) as Connection[]) {
    try {
      results.push(await syncUser(admin, conn, dryRun));
    } catch (e) {
      // Per-user isolation: one failure never blocks the batch. Release the lease so
      // a transient error retries next tick; a revoked feed URL parks until re-pasted.
      const revoked = e instanceof RevokedError;
      const msg = revoked ? "feed_url_revoked" : String((e as Error)?.message ?? e).slice(0, 500);
      if (!dryRun) {
        await admin
          .from("canvas_connections")
          .update({ status: revoked ? "revoked" : "error", last_error: msg, claimed_until: null })
          .eq("user_id", conn.user_id);
      }
      results.push({
        userId: conn.user_id,
        status: revoked ? "revoked" : "error",
        notModified: false,
        tasksInserted: 0, tasksUpdated: 0, eventsInserted: 0, eventsUpdated: 0,
        error: msg,
      });
    }
  }

  return json({ ok: true, dryRun, count: results.length, users: results });
});
