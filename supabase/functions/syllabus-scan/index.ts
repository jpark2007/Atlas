/**
 * Atlas — syllabus-scan Edge Function (Deno)
 *
 * POST /functions/v1/syllabus-scan
 * Body:   { images: [{ data: <base64 image bytes>, mediaType: "image/png" | "image/jpeg" | ... }],
 *           termStart?: "YYYY-MM-DD",
 *           termEnd?:   "YYYY-MM-DD",
 *           timezone?:  IANA identifier (default "UTC") }
 *
 * Returns: {
 *   "classes": [{
 *     "code"?: "BIO 201",
 *     "name"?: "Cell Biology",
 *     "meetingPattern"?: [{ "weekdays": [2,4], "start": "10:00", "end": "10:50", "location"?: "..." }],
 *     "classInfo"?: { "grade_weights": [String], "policies": [String], "office_hours"?: String },
 *     "items": [{ "kind": "task" | "event", "title": String,
 *                 "dueISO"?: ISO8601, "startISO"?: ISO8601, "notes"?: String }]
 *   }],
 *   "truncated"?: true
 * }
 *
 * `dueISO`/`startISO` on the wire are full UTC instants, as they have always been.
 * The MODEL answers in the student's LOCAL wall clock and `_shared/syllabus_scan.ts`
 * does the timezone/DST conversion in code (`localToUtcISO`) — asking a model to do
 * that arithmetic itself reliably landed dates a day early. The change is entirely
 * inside the function; shipped clients see the same shape.
 *
 * This endpoint COMMITS NOTHING. It returns a draft the client shows in the
 * review list (Phase 1 spec: draft → review → commit); the client writes the
 * accepted rows itself. `weekdays` uses Foundation's numbering (1 = Sunday …
 * 7 = Saturday) and `start`/`end` are LOCAL wall-clock "HH:mm", matching the
 * `MeetingBlock` jsonb shape stored in `projects.meeting_pattern`.
 *
 * IMAGES ONLY. PDFs are not accepted: keeping one lane means one code path and
 * one cost profile, so the CLIENT rasterizes each PDF page to a PNG/JPEG and
 * sends the pages as images (macOS: `PDFPage.thumbnail(of:for:)` / CGContext).
 *
 * Requires:
 *   - Authorization: Bearer <Supabase JWT>  (VERIFIED via auth.getUser — a scan
 *     is the most expensive call Atlas makes, so presence-only is not enough)
 *   - OPENROUTER_API_KEY set as a Supabase Edge Function secret (same secret the
 *     `capture` function uses)
 *
 * Deploy:  supabase functions deploy syllabus-scan
 * Secrets: supabase secrets set OPENROUTER_API_KEY=<key>
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, tooManyRequests } from "../_shared/rate_limit.ts";
import { applyCaps, base64ByteLength, normalizeClasses } from "../_shared/syllabus_scan.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// A syllabus is a handful of pages, not a document scanner. Ten pages covers a
// long syllabus or a week-grid screenshot set; more is abuse/accident.
const MAX_IMAGES = 10;

// Total DECODED image bytes across the request. 15 MB is generous for ten
// screenshot-sized pages and bounds both the request body and the model bill.
const MAX_TOTAL_BYTES = 15 * 1024 * 1024;

const ALLOWED_MEDIA_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/heic",
  "image/heif",
]);

// Vision model. `capture` uses gemini-2.5-flash-lite for short text; a syllabus
// page is dense OCR + date reasoning, so the scan steps up to full flash while
// staying in the same gemini family (one provider, one key, one prompt style).
const MODEL = "google/gemini-2.5-flash";

interface ScanImage {
  data: string;
  mediaType: string;
}

function jsonResponse(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json", ...extra },
  });
}

/**
 * The scan prompt. Dates are grounded on the term window + the user's timezone:
 * a syllabus says "Week 3" or "Sept 12" and only the term window turns that into
 * a real instant. When the term window can't settle it, the item is KEPT with no
 * date — the review list lets the user fill it in — never guessed.
 */
function buildSystemPrompt(termStart: string | undefined,
                           termEnd: string | undefined,
                           timezone: string): string {
  const termBlock = termStart || termEnd
    ? `Term window: ${termStart ?? "(unknown start)"} → ${termEnd ?? "(unknown end)"}.
Use it to resolve relative references ("Week 3", "the Monday after break") into real
dates, counting from the term start. If the reference is ambiguous or the window is
missing, OMIT the date but KEEP the item.`
    : `No term window was provided. Use only dates the document states outright; for
relative references ("Week 3") OMIT the date but KEEP the item.`;

  return `You read a college syllabus or class-schedule image and extract its structure.
The user's timezone is "${timezone}". ${termBlock}

Return a JSON OBJECT with this exact shape:
{
  "classes": [
    {
      "code": string,            // course code as printed, e.g. "BIO 201" (omit if absent)
      "name": string,            // course title, e.g. "Cell Biology" (omit if absent)
      "meetingPattern": [        // recurring class meetings (omit if none stated)
        {
          "weekdays": [number],  // 1=Sunday, 2=Monday … 7=Saturday. "MWF" = [2,4,6]
          "start": "HH:mm",      // LOCAL wall-clock 24h, e.g. "10:00"
          "end": "HH:mm",
          "location": string     // room/building (omit if absent)
        }
      ],
      "classInfo": {             // static syllabus text, quoted/condensed — never computed
        "grade_weights": [string],  // e.g. "Exams 40%", "Homework 25%"
        "policies": [string],       // late work, attendance, academic-integrity notes
        "office_hours": string      // e.g. "Tue 2–4pm, Rm 312" (omit if absent)
      },
      "items": [
        {
          "kind": "task" | "event",  // assignment/reading/paper = task; exam/quiz/lab session = event
          "title": string,           // clean noun phrase, NO date words in it
          "dueISO": string,          // tasks: LOCAL wall clock, "YYYY-MM-DDTHH:mm" (no Z, no
                                     // offset), or "YYYY-MM-DD" when no time is stated
          "startISO": string,        // events: LOCAL wall clock in the same shape
          "notes": string            // chapter numbers, weight, page counts (omit if none)
        }
      ]
    }
  ]
}

Rules:
- One entry in "classes" per distinct course found. Most scans are ONE class; a
  timetable screenshot may contain several. Never invent a second class.
- Every class MUST have an "items" array (use [] when the page lists no work).
- Assignments, readings, papers, problem sets → "task" with "dueISO".
  Exams, quizzes, midterms, finals, labs, presentations → "event" with "startISO".
- A stated clock time is SACRED: copy it into "dueISO"/"startISO" exactly as the
  syllabus prints it ("due Sept 12 at 11:59pm" → "2026-09-12T23:59"). Never round it,
  never turn it into midnight.
- NEVER do timezone arithmetic. Write every date and time as the student reads it off
  their own calendar and clock — no "Z", no offset, no rolling the date forward. The
  server converts to UTC. A due date with NO stated time is just "YYYY-MM-DD".
- NEVER invent a date. If a date cannot be resolved confidently, omit "dueISO"/
  "startISO" and still emit the item — a dateless item is useful, a wrong one is not.
- "meetingPattern" is the RECURRING weekly pattern only. A one-off exam date is an
  item, not a meeting block. Merge days sharing a time into one block's "weekdays".
- "classInfo" is the syllabus's own words, condensed to short bullets. Do NOT compute
  grades, predict scores, or add advice. Omit any field the syllabus doesn't state.
- Titles carry no date words: "Essay 1 due Sept 12" → "Essay 1".
- Omit every field you have no evidence for. Return {"classes": []} if the images
  contain no course information at all.`;
}

/**
 * Validate the request body. Returns the images on success or an error Response
 * carrying the right status (400 shape problems, 413 size problems).
 */
function validateImages(
  body: Record<string, unknown>,
): { ok: true; images: ScanImage[] } | { ok: false; response: Response } {
  const raw = body.images;
  if (!Array.isArray(raw) || raw.length === 0) {
    return {
      ok: false,
      response: jsonResponse({ error: "Body must contain a non-empty `images` array" }, 400),
    };
  }
  if (raw.length > MAX_IMAGES) {
    return {
      ok: false,
      response: jsonResponse({ error: `Too many pages (max ${MAX_IMAGES})` }, 413),
    };
  }

  const images: ScanImage[] = [];
  let totalBytes = 0;
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") {
      return { ok: false, response: jsonResponse({ error: "Each image must be an object" }, 400) };
    }
    const img = entry as Record<string, unknown>;
    const data = typeof img.data === "string" ? img.data.trim() : "";
    const mediaType = typeof img.mediaType === "string" ? img.mediaType.trim().toLowerCase() : "";
    if (!data) {
      return { ok: false, response: jsonResponse({ error: "Each image needs base64 `data`" }, 400) };
    }
    if (mediaType === "application/pdf") {
      return {
        ok: false,
        response: jsonResponse({
          error: "PDF is not accepted — rasterize each page to PNG/JPEG and send the pages as images",
        }, 400),
      };
    }
    if (!ALLOWED_MEDIA_TYPES.has(mediaType)) {
      return {
        ok: false,
        response: jsonResponse({
          error: `Unsupported mediaType "${mediaType}" (allowed: ${[...ALLOWED_MEDIA_TYPES].join(", ")})`,
        }, 400),
      };
    }
    totalBytes += base64ByteLength(data);
    if (totalBytes > MAX_TOTAL_BYTES) {
      return {
        ok: false,
        response: jsonResponse({
          error: `Images too large (max ${Math.floor(MAX_TOTAL_BYTES / (1024 * 1024))} MB total)`,
        }, 413),
      };
    }
    images.push({ data, mediaType });
  }
  return { ok: true, images };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── Real JWT verification: a vision scan is the most expensive call Atlas
  // makes, so the caller must present a valid Supabase token (not just the anon
  // key, which is a validly-signed JWT that a presence-only check would pass). ──
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: "Server not configured" }, 500);
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    return jsonResponse({ error: "Missing or invalid Authorization header" }, 401);
  }
  const authClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }
  const userId = userData.user.id;

  // Rate limit BEFORE the (paid) OpenRouter call, keyed on the VERIFIED user id.
  // 10/hour: a student scans a few syllabi at the start of a term, not per minute.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const rl = await checkRateLimit(admin, userId, "syllabus-scan", 10, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, CORS_HEADERS);

  let images: ScanImage[];
  let termStart: string | undefined;
  let termEnd: string | undefined;
  let timezone = "UTC";
  try {
    const body = await req.json();
    if (!body || typeof body !== "object") {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }
    const validated = validateImages(body as Record<string, unknown>);
    if (!validated.ok) return validated.response;
    images = validated.images;
    if (typeof body.termStart === "string" && body.termStart.trim()) termStart = body.termStart.trim();
    if (typeof body.termEnd === "string" && body.termEnd.trim()) termEnd = body.termEnd.trim();
    if (typeof body.timezone === "string" && body.timezone.trim()) timezone = body.timezone.trim();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!openRouterKey) {
    return jsonResponse({ error: "OPENROUTER_API_KEY secret not configured" }, 500);
  }

  // One multimodal call carrying every page, so a syllabus split across pages is
  // read as ONE document (a per-page fan-out would split a table across calls).
  const userContent = [
    {
      type: "text",
      text: images.length === 1
        ? "Extract the class structure from this syllabus/schedule image."
        : `Extract the class structure from these ${images.length} pages of one syllabus/schedule.`,
    },
    ...images.map((img) => ({
      type: "image_url",
      image_url: { url: `data:${img.mediaType};base64,${img.data}` },
    })),
  ];

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
        model: MODEL,
        messages: [
          { role: "system", content: buildSystemPrompt(termStart, termEnd, timezone) },
          { role: "user", content: userContent },
        ],
        response_format: { type: "json_object" },
        temperature: 0.1,
        max_tokens: 16384,
      }),
    });
  } catch (err) {
    return jsonResponse({ error: "Failed to reach OpenRouter", detail: String(err) }, 502);
  }
  if (!res.ok) {
    return jsonResponse({ error: "OpenRouter error", detail: await res.text() }, 502);
  }

  let classes: Record<string, unknown>[];
  try {
    const completion = await res.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "{}";
    classes = normalizeClasses(JSON.parse(content), timezone);
  } catch (err) {
    return jsonResponse({ error: "Could not parse model output as JSON", detail: String(err) }, 502);
  }

  const capped = applyCaps(classes);
  const payload: Record<string, unknown> = { classes: capped.classes };
  if (capped.truncated) payload.truncated = true;
  return jsonResponse(payload, 200);
});
