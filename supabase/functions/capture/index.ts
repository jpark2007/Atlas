/**
 * Atlas — capture Edge Function (Deno)
 *
 * POST /functions/v1/capture
 * Body:   { text: string,
 *           timezone?: string,                       // IANA id
 *           spaces?: [{ name: string,
 *                       projects: (string | { name, code?, overview?, isClass? })[] }],
 *           deadlines?: [{ id, title, dueISO, projectName? }],  // existing upcoming items
 *           recent?: string[] }                      // last few raw captures
 *          Projects may be bare names (legacy) or objects whose code + short
 *          overview give the model description-aware routing context; `isClass`
 *          marks a School class so "bio lab" routes to BIO 201.
 *          `deadlines` lets a capture REFER to something the user already has
 *          ("the essay") — the model may then answer with an update item instead
 *          of a duplicate. `recent` supplies referents from the last few dumps.
 * Returns: JSON ARRAY of capture items:
 *   [{ kind, title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes?,
 *      confidence? }, ...]
 *   or, for an item that attaches to an existing one:
 *   [{ kind: "update", targetId, title, spaceName, dueISO?, notes?, confidence? }, ...]
 *   A client that doesn't know "update" treats it as an unknown kind and still
 *   saves a task, so nothing is ever lost.
 *
 * The model splits a multi-item paragraph ("essay due thu, gym 3x, dinner sunday")
 * into multiple objects. When `spaces` is supplied, the user's real Space + project
 * names are injected into the prompt so routing uses their actual buckets.
 *
 * Requires:
 *   - Authorization: Bearer <Supabase JWT>  (VERIFIED via auth.getUser — this
 *     endpoint spends money on OpenRouter, so presence-only is not enough)
 *   - OPENROUTER_API_KEY set as a Supabase Edge Function secret
 *
 * Deploy:  supabase functions deploy capture
 * Secrets: supabase secrets set OPENROUTER_API_KEY=<key>
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, tooManyRequests } from "../_shared/rate_limit.ts";
import { chunkText, dedupeItems, userContentForChunk } from "../_shared/capture_chunking.ts";
import { applyClassBackstop, classAliasHint } from "../_shared/capture_class_match.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  // Let browser callers read the truncation signal (URLSession ignores CORS).
  "Access-Control-Expose-Headers": "X-Atlas-Capture-Truncated",
};

// A capture is a short free-text jot; a few thousand chars is generous. Anything
// larger is abuse/accident — reject with 413 before spending an OpenRouter call.
const MAX_TEXT_LEN = 20000;

// Long captures fan out into parallel chunk calls (see _shared/capture_chunking.ts)
// so a big paste "just works" without a user-visible item cap. MAX_ITEMS is a
// defensive abuse bound ONLY — when it actually trims, the client is told via the
// "X-Atlas-Capture-Truncated" header (the body stays a bare JSON array so old
// shipped clients decode it unchanged).
const MAX_ITEMS = 200;

// A project is either a bare name (legacy clients) or an object carrying an
// optional short code and description used for description-aware routing.
type ContextProject =
  | string
  | { name: string; code?: string; overview?: string; isClass?: boolean };
type ContextSpace = { name: string; projects: ContextProject[] };

/** One existing upcoming item the capture may refer to instead of duplicating. */
type ContextDeadline = { id: string; title: string; dueISO: string; projectName?: string };

const DEFAULT_SPACES = ["School", "Work", "Personal", "Health", "Finance", "Other"];

// Defensive caps on the client-supplied context. The clients already cap these
// (AtlasAI.deadlineContext / recentContext); these bounds stop a hand-rolled or
// buggy caller from inflating the prompt (and the bill).
const MAX_DEADLINES = 40;
const MAX_RECENT = 8;
const MAX_RECENT_CHARS = 200;

/**
 * Render one project line for the routing block. Tolerant of both the legacy
 * string shape and the rich object shape ({ name, code?, overview? }). The code
 * and description are context for routing only — never part of `projectName`.
 * Returns null for malformed/blank entries so they're dropped.
 */
function projectLabel(p: ContextProject): string | null {
  if (typeof p === "string") {
    const name = p.trim();
    return name.length ? `"${name}"` : null;
  }
  if (p && typeof p === "object" && typeof p.name === "string" && p.name.trim().length) {
    const name = p.name.trim();
    // The code leads: a capture says "bio lab", never the full project name, so
    // the code is the highest-signal token the model has to match against.
    const code = typeof p.code === "string" && p.code.trim().length
      ? ` [${p.code.trim()}]` : "";
    const cls = p.isClass === true ? " (class)" : "";
    // The short forms a capture actually uses ("chem", "psych") — same table the
    // server-side backstop matches on, so prompt and enforcement agree.
    const aka = p.isClass === true ? classAliasHint(p) : "";
    const desc = typeof p.overview === "string" && p.overview.trim().length
      ? ` — ${p.overview.trim()}` : "";
    return `"${name}"${code}${cls}${aka}${desc}`;
  }
  return null;
}

/**
 * Render the "things you already have" block. Each line carries the id the model
 * must echo back in `targetId` when the capture refers to that item. Omitted
 * entirely when the client sent nothing, so the prompt stays short.
 */
function deadlinesBlock(deadlines: ContextDeadline[]): string {
  if (!deadlines.length) return "";
  const lines = deadlines.map((d) =>
    `    • id=${d.id} · "${d.title}"${d.projectName ? ` · ${d.projectName}` : ""} · due ${d.dueISO}`
  );
  return `

The user ALREADY has these upcoming items:
${lines.join("\n")}
When the capture clearly refers to ONE of them ("finish the essay", "move the bio \
lab to friday", "the midterm is actually thursday") do NOT create a new item. Emit \
an UPDATE item instead:
{ "kind": "update", "targetId": "<the exact id above>", "title": "<that item's title>", \
"spaceName": "<that item's space>", "dueISO"?: <new deadline, only if the capture states one>, \
"notes"?: <detail to attach> }
Only ever use an id copied EXACTLY from the list above. If you are not sure the \
capture means one of these, create a new item as usual — a duplicate is far better \
than editing the wrong thing.`;
}

/** Referents from the user's last few dumps — context only, never new items. */
function recentBlock(recent: string[]): string {
  if (!recent.length) return "";
  const lines = recent.map((t) => `    • ${t}`);
  return `

For reference only, the user's most recent captures (newest first) — use these to \
resolve pronouns and short referents. NEVER create items for this text:
${lines.join("\n")}`;
}

/**
 * Render the Space/Project routing block. When the client sends real buckets we
 * use those (with each project's code + description as routing context);
 * otherwise we fall back to the generic default list so old clients (and direct
 * callers) still work.
 */
function spacesBlock(spaces: ContextSpace[] | undefined): string {
  const valid = (spaces ?? []).filter(
    (s) => s && typeof s.name === "string" && s.name.trim().length > 0,
  );
  if (valid.length === 0) {
    return `- "spaceName": one of: ${DEFAULT_SPACES.map((s) => `"${s}"`).join(", ")}.`;
  }
  const lines = valid.map((s) => {
    const projects = (s.projects ?? [])
      .map(projectLabel)
      .filter((p): p is string => p !== null);
    if (!projects.length) {
      return `    • "${s.name}"`;
    }
    const projLines = projects.map((p) => `        - ${p}`).join("\n");
    return `    • "${s.name}"\n${projLines}`;
  });
  return `- "spaceName": choose the single best match from the user's actual spaces below. \
Use the EXACT name as written. If nothing fits, use the closest one. Each project below \
may include a [CODE] and a — description; use them to route ambiguous items confidently, \
but never copy the code or description into any field.
${lines.join("\n")}
- "projectName": REQUIRED on every item — never omit this key. Set it to the EXACT project \
name shown above (without the code, "aka" list, or description) when the item belongs to \
one of that space's listed projects; otherwise set it to null. Match on the name, the \
[CODE], the "aka" short forms, or the description.
- COURSEWORK MUST CARRY ITS CLASS. Anything that is schoolwork — a lab, writeup, problem \
set, reading, essay, quiz, exam, project, homework — belongs to one of the classes listed \
above. Read the item's own words for the subject ("chem lab writeup" → the chemistry \
class, "psych reading" → the psychology class) and attach that class. Use null ONLY when \
the text genuinely names no subject at all, or names one that fits two of the classes \
equally well.`;
}

/**
 * "Now" rendered in the user's timezone for the prompt, e.g.
 * "Thursday, July 2, 2026, 3:41 PM". Falls back to UTC on a bad identifier
 * (Intl throws RangeError) so a malformed client can't 500 the function.
 */
function localNow(timezone: string): { tz: string; text: string } {
  try {
    const text = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      weekday: "long", year: "numeric", month: "long", day: "numeric",
      hour: "numeric", minute: "2-digit", hour12: true,
    }).format(new Date());
    return { tz: timezone, text };
  } catch {
    return { tz: "UTC", text: new Date().toISOString() };
  }
}

function buildSystemPrompt(
  spaces: ContextSpace[] | undefined,
  timezone: string,
  deadlines: ContextDeadline[] = [],
  recent: string[] = [],
): string {
  const now = localNow(timezone);
  return `You are Atlas, a personal life-management AI. \
The user's timezone is ${now.tz}. Right now, the user's LOCAL date and time is: ${now.text}. \
Resolve ALL dates and times ("tomorrow", "next Friday", "tonight", "at 5:30") in the \
user's LOCAL time first, then convert to UTC for output. \
Given a user's free-text capture, classify it and split it into one or more items. \
A single paragraph can contain MULTIPLE items (e.g. "essay due thursday, gym 3x this \
week, dinner with mom sunday" → three items). Return ONLY a JSON object of the form \
{ "items": [ ... ] } — no markdown, no explanation, just the raw JSON. \
Each element of "items" matches this schema:

{
  "kind": "task" | "event" | "note",
  "title": string,            // concise, actionable title
  "spaceName": string,        // see routing rules below
  "projectName": string|null, // REQUIRED KEY on every item: the exact project/class name
                              // from the routing list, or null. Never leave it out.
  "dueISO"?: string,          // Full ISO 8601 UTC instant converted from the user's local time,
                              // e.g. a 5:30 PM PDT deadline → "2026-07-03T00:30:00Z" (tasks)
  "startISO"?: string,        // Full ISO 8601 UTC instant, converted the same way (events)
  "endISO"?: string,          // Full ISO 8601 UTC instant for the event's END, only when an
                              // explicit end/finish time is stated; else omit and durationMin governs
  "durationMin"?: number,     // duration in minutes (events, default 60 if not specified)
  "isAllDay"?: boolean,       // true for an event on a date with NO stated clock time (all-day)
  "notes"?: string,           // extra detail / body text (notes, or longer event notes)
  "confidence"?: number       // 0–1: how sure you are of kind + routing + date for THIS item.
                              // Be honest — a low number marks the item for a quick fix
                              // instead of silently getting it wrong. Omit if fully sure.
}

Routing:
${spacesBlock(spaces)}${deadlinesBlock(deadlines)}${recentBlock(recent)}

Rules:
- Split distinct to-dos / events / notes into SEPARATE items. A single self-contained
  capture is a one-element array.
- "task"  = something to do (verb phrase, deadline, assignment, chore)
- "event" = a meeting, appointment, session, or time-bound activity
- "note"  = a thought, idea, reference, or piece of information to remember
- "update" = a change to an item the user ALREADY has (only valid when an existing-items
  list appears above, and only with an id copied exactly from it)
- If an item is ambiguous, prefer "task".
- STATED TIMES ARE SACRED. If the user states a clock time ("at 5:30", "by noon",
  "8pm"), it MUST appear in dueISO (tasks) or startISO (events), converted from the
  user's LOCAL time to UTC. NEVER return a date-only/midnight value when a time was stated.
- PRESERVE STATED MINUTES EXACTLY. "3:30" means minute 30 — NEVER round to the hour and
  NEVER alter a stated start or end time. A time range may be written compactly ("3:30-6",
  "3:30–6pm", "2-3"): parse BOTH endpoints, and a single am/pm suffix applies to BOTH
  endpoints (so "3:30-6pm" = 3:30 PM start, 6:00 PM end).
- If a bare clock time has no AM/PM ("at 5:30", "pick up at 7"), pick the reading a
  person plausibly means: when the AM reading falls earlier today than the current LOCAL
  time above, use PM (e.g. if it is already 7 AM local, "5:30 today" and "at 7" mean PM).
- For a bare time with NO AM/PM on a FUTURE date, prefer the daytime reading (roughly
  7 AM–9 PM) unless context clearly indicates otherwise.
- Convert to UTC by ADDING the user's offset from UTC, and let the CALENDAR DATE roll
  forward when the local time is afternoon/evening. For a UTC-behind zone like the
  Americas, a PM local time usually lands on the NEXT UTC day: e.g. 5:30 PM local on
  July 2 in a UTC-7 zone → "2026-07-03T00:30:00Z" (date advances to the 3rd), and 7 PM
  local that day → "2026-07-03T02:00:00Z". Never leave the date on the local day if the
  UTC instant has already crossed midnight. This applies even when the user says "today":
  a deadline "at 5:30 today" still carries the correct UTC date, which may be tomorrow.
- A time-bound errand or commitment ("pick him up at 5:30", "call mom at 8") is an
  "event" starting at that local time — not a floating task with no deadline.
- A deadline WITHOUT a stated time ("due Friday") = that LOCAL day at 00:00 user-local,
  converted to UTC.
- If an event states an explicit END/finish time ("2–3pm", "from 9 to 10:30", "ends at 4"),
  put that end as "endISO" (converted to UTC the same way). Otherwise OMIT endISO and let
  durationMin govern. NEVER invent an end time.
- An event on a DATE with NO stated clock time ("game on Saturday", "trip July 5") is
  all-day: set "isAllDay": true and put that LOCAL day's midnight (UTC-converted) in startISO.
- A pasted SCHEDULE listing several dated sessions (a season, syllabus, itinerary, class
  list) becomes ONE event per listed session — each with its own date/time. Only make items
  for sessions that carry an actual date; never invent dates or times for unlisted ones.
- Whenever a capture would produce many items, emit at most 50; if there are more, keep the
  50 EARLIEST (earliest date/time first).
- TITLES ARE CLEAN. The title must NOT contain the date/time words you parsed into
  dueISO/startISO — strip phrases like "due next friday", "on friday", "at 5:30",
  "tomorrow", "tonight" and leave a bare noun/verb phrase: "essay due next friday" →
  "Essay"; "pick up Sam at 5:30" → "Pick up Sam"; "math exam on friday" → "Math exam".
- Always populate kind, title, spaceName, and projectName (a name or null). All other
  fields are optional.`;
}

/**
 * Coerce whatever the model returned into a flat array of capture objects.
 * Accepts `{ items: [...] }` (the requested shape), a bare array, or a single
 * object (wrapped as a one-element array).
 */
function normalizeItems(parsed: unknown): Record<string, unknown>[] {
  if (Array.isArray(parsed)) {
    return parsed.filter((x): x is Record<string, unknown> =>
      typeof x === "object" && x !== null
    );
  }
  if (parsed && typeof parsed === "object") {
    const obj = parsed as Record<string, unknown>;
    if (Array.isArray(obj.items)) {
      return obj.items.filter((x): x is Record<string, unknown> =>
        typeof x === "object" && x !== null
      );
    }
    // A single capture object (no `items` wrapper) — wrap it.
    if (typeof obj.kind === "string" || typeof obj.title === "string") {
      return [obj];
    }
  }
  return [];
}

type ChunkOutcome =
  | { ok: true; items: Record<string, unknown>[] }
  | { ok: false; response: Response };

/**
 * One OpenRouter call for a single chunk. Returns the normalized items on success,
 * or an error Response (the same 502 taxonomy as before) the caller returns as-is
 * — so ANY chunk failure fails the whole request, never a silent partial result.
 */
async function callModel(
  userContent: string,
  systemPrompt: string,
  openRouterKey: string,
): Promise<ChunkOutcome> {
  const errorBody = (error: string, detail: string): Response =>
    new Response(
      JSON.stringify({ error, detail }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );

  let res: Response;
  try {
    res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://atlas.app",
        "X-Title": "Atlas Life Manager",
      },
      body: JSON.stringify({
        model: "google/gemini-2.5-flash-lite",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
        ],
        response_format: { type: "json_object" },
        temperature: 0.2,
        max_tokens: 8192,
      }),
    });
  } catch (err) {
    return { ok: false, response: errorBody("Failed to reach OpenRouter", String(err)) };
  }

  if (!res.ok) {
    return { ok: false, response: errorBody("OpenRouter error", await res.text()) };
  }

  try {
    const completion = await res.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "{}";
    return { ok: true, items: normalizeItems(JSON.parse(content)) };
  } catch (err) {
    return { ok: false, response: errorBody("Could not parse model output as JSON", String(err)) };
  }
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // ── Real JWT verification: this endpoint spends money on OpenRouter, so the
  // caller must present a valid Supabase token (not just the public anon key,
  // which is a validly-signed JWT that would pass a presence-only check). ──
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return new Response(
      JSON.stringify({ error: "Server not configured" }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    return new Response(
      JSON.stringify({ error: "Missing or invalid Authorization header" }),
      { status: 401, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired token" }),
      { status: 401, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
  const userId = userData.user.id;

  // Rate limit BEFORE the (paid) OpenRouter call, keyed on the VERIFIED user id.
  // 30/min is well above a human capturing notes and caps LLM-cost abuse.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const rl = await checkRateLimit(admin, userId, "capture", 30, 60);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  // Parse request body
  let text: string;
  let spaces: ContextSpace[] | undefined;
  let timezone = "UTC";
  let deadlines: ContextDeadline[] = [];
  let recent: string[] = [];
  try {
    const body = await req.json();
    if (typeof body?.text !== "string" || !body.text.trim()) {
      return new Response(
        JSON.stringify({ error: "Body must contain a non-empty `text` string" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }
    text = body.text.trim();
    if (text.length > MAX_TEXT_LEN) {
      return new Response(
        JSON.stringify({ error: `\`text\` too long (max ${MAX_TEXT_LEN} characters)` }),
        { status: 413, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }
    if (Array.isArray(body.spaces)) {
      spaces = body.spaces as ContextSpace[];
    }
    if (typeof body.timezone === "string" && body.timezone.trim()) {
      timezone = body.timezone.trim();
    }
    // Context is optional and client-supplied: keep only well-formed entries and
    // cap the count, so a malformed caller degrades to "no context" not a 500.
    if (Array.isArray(body.deadlines)) {
      deadlines = (body.deadlines as unknown[])
        .filter((d): d is ContextDeadline =>
          !!d && typeof d === "object" &&
          typeof (d as ContextDeadline).id === "string" &&
          typeof (d as ContextDeadline).title === "string" &&
          typeof (d as ContextDeadline).dueISO === "string"
        )
        .slice(0, MAX_DEADLINES);
    }
    if (Array.isArray(body.recent)) {
      recent = (body.recent as unknown[])
        .filter((t): t is string => typeof t === "string" && t.trim().length > 0)
        .slice(0, MAX_RECENT)
        .map((t) => t.trim().slice(0, MAX_RECENT_CHARS));
    }
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Read the OpenRouter API key from env (never hardcoded)
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!openRouterKey) {
    return new Response(
      JSON.stringify({ error: "OPENROUTER_API_KEY secret not configured" }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Fan out: a normal input is a single call; a long paste is split into chunks
  // parsed in PARALLEL, each later chunk carrying a read-only tail of the prior
  // text as context. Any chunk failure fails the whole request with the existing
  // error taxonomy — no silent partial results.
  const systemPrompt = buildSystemPrompt(spaces, timezone, deadlines, recent);
  const chunks = chunkText(text);
  const outcomes = await Promise.all(
    chunks.map((_, i) =>
      callModel(userContentForChunk(chunks, i), systemPrompt, openRouterKey)
    ),
  );
  const failed = outcomes.find(
    (o): o is { ok: false; response: Response } => !o.ok,
  );
  if (failed) return failed.response;

  // Concatenate in chunk order, then drop any dated event a boundary caused two
  // chunks to emit (identical title + startISO).
  let items = dedupeItems(outcomes.flatMap((o) => (o.ok ? o.items : [])));

  // Deterministic class attribution: snap a returned project name onto the user's
  // exact spelling, and recover the class from the item's own text when the model
  // left it null. Only ever attaches a class the text names UNAMBIGUOUSLY.
  items = applyClassBackstop(items, spaces);

  // Defensive abuse bound ONLY (chunking already removes any normal cap). When it
  // actually trims, flag it via a response header; the body stays a bare array.
  const truncated = items.length > MAX_ITEMS;
  if (truncated) items = items.slice(0, MAX_ITEMS);

  const headers: Record<string, string> = {
    ...CORS_HEADERS,
    "Content-Type": "application/json",
  };
  if (truncated) headers["X-Atlas-Capture-Truncated"] = "1";

  // Always return a JSON ARRAY (possibly empty) so the client can decode uniformly.
  return new Response(JSON.stringify(items), { status: 200, headers });
});
