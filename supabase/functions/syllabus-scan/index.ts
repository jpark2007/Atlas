/**
 * Atlas — syllabus-scan Edge Function (Deno)
 *
 * POST /functions/v1/syllabus-scan
 * Body:   { images: [{ data: <base64 image bytes>, mediaType: "image/png" | "image/jpeg" | ... }],
 *           OR
 *           text:  "<the syllabus, pasted>",
 *           termStart?: "YYYY-MM-DD",
 *           termEnd?:   "YYYY-MM-DD",
 *           timezone?:  IANA identifier (default "UTC") }
 *
 * TWO INPUT LANES, ONE PIPELINE. `images` is the original; `text` exists because at
 * least one class's syllabus is an inline Canvas page with nothing to download
 * (handoff §E). Both feed the same prompt, the same model call and the same
 * `normalizeClasses`, so the response contract is identical either way. `images`
 * wins if a caller somehow sends both.
 *
 * Returns: {
 *   "classes": [{
 *     "code"?: "BIO 201",
 *     "name"?: "Cell Biology",
 *     "meetingPattern"?: [{ "weekdays": [2,4], "start": "10:00", "end": "10:50",
 *                           "location"?: "...", "sectionLabel"?: "...", "kind"?: "lecture" }],
 *     "classInfo"?: { "grade_weights": [String], "policies": [String], "office_hours"?: String },
 *     "items": [{ "kind": "task" | "event", "title": String,
 *                 "dueISO"?: ISO8601, "startISO"?: ISO8601, "notes"?: String,
 *                 "dateOnly"?: true, "dateApproximate"?: true }]
 *   }],
 *   "truncated"?: true,
 *   "warnings"?: [String]
 * }
 *
 * `sectionLabel`/`kind` on a block, `dateOnly`/`dateApproximate` on an item and the
 * top-level `warnings` are ADDITIVE: the shipped client decodes with `decodeIfPresent`
 * and ignores keys it doesn't know, so old builds are unaffected.
 *
 * A SCHEDULE document (the weekly-module table or month grid a professor posts apart
 * from the syllabus) goes through this same lane — the prompt recognises it and emits
 * the same draft shape. Its week-range rows come back as bare days flagged
 * `dateApproximate`; its topic and holiday rows are not items at all.
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

// A syllabus is a document, not a document scanner. Twenty pages covers a full
// course packet or a term's week-grid screenshots; more is abuse/accident.
const MAX_IMAGES = 20;

// Total DECODED image bytes across the request. Clients rasterize a PDF page to a
// 1400px-long-edge JPEG (~0.3–0.6 MB), so 15 MB still holds twenty pages and bounds
// both the request body and the model bill.
const MAX_TOTAL_BYTES = 15 * 1024 * 1024;

// A pasted syllabus. 200k characters is a very long course packet and still a fraction
// of the model's window; the floor stops an accidental two-word paste costing a call.
const MAX_TEXT_CHARS = 200_000;
const MIN_TEXT_CHARS = 40;

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

  return `You read a college syllabus or class schedule — as page images, or as the text of
a course page pasted in — and extract its structure.
The user's timezone is "${timezone}". ${termBlock}

Return a JSON OBJECT with this exact shape:
{
  "classes": [
    {
      "code": string,            // course code as printed, e.g. "BIO 201" (omit if absent)
      "name": string,            // course title, e.g. "Cell Biology" (omit if absent)
      "meetingPattern": [        // recurring class meetings (omit if none stated)
        {
          "weekdays": [number],  // 1=Sunday, 2=Monday … 7=Saturday (see the table below)
          "start": "HH:mm",      // LOCAL wall-clock 24h, e.g. "10:00"
          "end": "HH:mm",
          "location": string,    // room/building (omit if absent)
          "sectionLabel": string,// the section this row belongs to as printed,
                                 // e.g. the words next to the row in the table (omit if absent)
          "kind": string         // "lecture" | "recitation" | "lab" | "other" (omit if unclear)
        }
      ],
      "classInfo": {             // static syllabus text, quoted/condensed — never computed
        "grade_weights": [string],  // e.g. "Exams 40%", "Homework 25%"
        "policies": [string],       // AT MOST 8, each "Heading: one-sentence rule"
        "office_hours": string      // the syllabus's own office-hours wording, copied
                                    // from the page (omit if absent)
      },
      "items": [
        {
          "kind": "task" | "event",  // assignment/reading/paper = task; exam/quiz/lab session = event
          "title": string,           // clean noun phrase, NO date words in it
          "dueISO": string,          // tasks: LOCAL wall clock, "YYYY-MM-DDTHH:mm" (no Z, no
                                     // offset), or "YYYY-MM-DD" when no time is stated
          "startISO": string,        // events: LOCAL wall clock in the same shape
          "notes": string,           // chapter numbers, weight, page counts (omit if none)
          "dateApproximate": true    // ONLY when the date came from a week or a date RANGE
                                     // ("Sept 28-Oct 2") rather than a printed day. Omit
                                     // it entirely for every exactly-dated row.
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
- NEVER invent a date, a TIME, or a WEEKDAY. Every hour, minute and day you return must
  be printed in the document. If a date cannot be resolved confidently, omit "dueISO"/
  "startISO" and still emit the item — a dateless item is useful, a wrong one is not.
  If a meeting's days or times are not stated, do not emit that block at all.
- "classInfo" is the syllabus's own words, condensed to short bullets. Do NOT compute
  grades, predict scores, or add advice. Omit any field the syllabus doesn't state.
- "office_hours": copy only what the document prints. If it says to check Canvas, the
  course site, or "by appointment" instead of naming times, return null for it.

Grading table ("grade_weights"):
- Report the CATEGORY TOTAL, never the per-item value. When a row states both a
  category weight and what each item inside it is worth, the leading percentage MUST
  be the category's total. Worked example, from a real grading table:
    "75% | Exams (3 Midterm Exams worth 25% each…)"  → "Exams 75%", NOT "Exams 25%"
    "25% | Discussion Board Questions (…worth 2.5 pts each…)" → "Discussion Board
    Questions 25%"
  The per-item detail may stay in the rest of the line's wording ("Exams 75% (3
  midterms, 25% each)"), but the number that LEADS the line is always the category's.
- A pass/fail or points-only component gets NO invented percentage. "*P/F | Research
  Participation Units (RPU's) 8 points" → "Research Participation Units 8 points".
  Never convert points to a percentage and never guess a weight for a P/F row.

Policies ("policies"):
- Return AT MOST 8 policies. Each one is a single string formatted
  "Heading: one-sentence rule" — a short heading, then the operative rule in ONE
  sentence, using the syllabus's own key terms and numbers.
- PREFER the course-specific, actionable rules: late-work rules and penalties, makeup
  rules, attendance requirements, free-miss or dropped-lowest allowances, extra
  credit, and exam conduct that affects the student's grade.
- SKIP university-wide boilerplate: disability-services procedure and addresses,
  generic academic-integrity statements, university absence-reporting systems,
  dean-of-students referrals, technology requirements. Include one of those ONLY when
  this course adds its own twist that carries a grade consequence.
- Never reproduce paragraphs of the syllabus. If more than 8 qualify, keep the 8 most
  consequential for the student's grade or planning and drop the rest.

Schedule documents (a course calendar posted on its own, apart from the syllabus):
- Many professors post a standalone SCHEDULE — a weekly-module table, a list of rows
  keyed by date range, or a month-grid calendar. Read it with the SAME rules and
  return the SAME shape. It is one class unless it plainly covers several.
- A schedule states no grading table, no policies section, no office hours and often
  no meeting times. Emit ONLY what is printed: no "classInfo" at all when the document
  has no grading/policy/office-hours text, and no "meetingPattern" when it never states
  the class's meeting DAYS AND TIMES. The dates of the rows are not a meeting pattern —
  never infer one from them.
- A row is an item ONLY if it names something the student must DO or ATTEND: an
  assignment, discussion post, quiz, paper, project, exam ("DBQ Module 5 due in
  Canvas", "Midterm 1"). A row that only names the week's TOPIC ("Social Psychology",
  "Sensation & Perception") is NOT an item — never import lecture topics as work. A
  no-class row (a holiday, a break, "Thanksgiving Holiday — No Classes", "Last day of
  class") is not an item either.
- A deliverable row dated by a RANGE or a week ("Sept 28-Oct 2", "Week 5") is due on
  the LAST day of that range. Emit that day as a bare "YYYY-MM-DD" with NO time, and
  set "dateApproximate": true. Put the printed wording in "notes" ("Week 5 · Sept
  28-Oct 2") so the student can see where the date came from. A row with ONE printed
  date is exact — never set "dateApproximate" on it.
- A document-wide deadline sentence ("all work is due by 11:59pm in Canvas") is a
  policy, not a per-row clock time. Leave such rows as bare days; only a time printed
  ON the row is a stated time.
- Exams on a schedule are "event" rows on their printed date. A stated time is kept
  ("Tuesday, Dec 15 @ 4-7pm" → startISO "2026-12-15T16:00"); with no time stated, emit
  the bare day. When the row prints both a generic label and a name ("Exam 1" in one
  column, "Midterm 1" in another), use the more specific name as the title and put the
  other label in "notes".

Meetings ("meetingPattern"):
- It is the RECURRING weekly pattern only. A one-off exam date is an item, not a block.
- ONE BLOCK PER PRINTED ROW. Each distinct combination of days + start/end time +
  location is its own block. NEVER merge two rows whose DAYS differ, and never merge
  rows that differ in time or room. Only the days written on a SINGLE row share a
  block's "weekdays" (a row printed "MWF 9:00–9:50" is one block, [2,4,6]).
- A syllabus often lists SEVERAL SECTIONS of the same course — one lecture plus a
  recitation or lab per section — and the student attends only one of them. Return
  them ALL, as separate blocks, each with its own "sectionLabel" and "kind". Never
  collapse sections together and never guess which one the student is in.
- An "Office:", "Instructor office", or office-hours line is NOT a meeting block. A
  room number next to a professor's name is where they sit, not where the class meets.
  Never turn one into a meeting.
- Weekday numbering is Foundation's, NOT ISO. Use exactly this mapping:
    Sunday=1, Monday=2, Tuesday=3, Wednesday=4, Thursday=5, Friday=6, Saturday=7.
  So "T"/"Tue" = 3, "MW" = [2,4], "MWF" = [2,4,6], "TTh" = [3,5]. Monday is 2, never 1.
  Never emit 0, never emit 8. Check each block against this table before returning it.

- Titles carry no date words: "Essay 1 due Sept 12" → "Essay 1".
- Omit every field you have no evidence for. Return {"classes": []} if the images
  contain no course information at all.`;
}

/**
 * Validate the request body. Returns the scan input — pages OR pasted text — on
 * success, or an error Response carrying the right status (400 shape problems, 413
 * size problems). A body with neither is the 400 it always was.
 */
function validateInput(
  body: Record<string, unknown>,
): { ok: true; images: ScanImage[]; text?: undefined }
  | { ok: true; text: string; images?: undefined }
  | { ok: false; response: Response } {
  if (!Array.isArray(body.images) && typeof body.text === "string") {
    const text = body.text.trim();
    if (text.length < MIN_TEXT_CHARS) {
      return {
        ok: false,
        response: jsonResponse({ error: "`text` is too short to be a syllabus" }, 400),
      };
    }
    if (text.length > MAX_TEXT_CHARS) {
      return {
        ok: false,
        response: jsonResponse({ error: `Text too long (max ${MAX_TEXT_CHARS} characters)` }, 413),
      };
    }
    return { ok: true, text };
  }

  const raw = body.images;
  if (!Array.isArray(raw) || raw.length === 0) {
    return {
      ok: false,
      response: jsonResponse({ error: "Body must contain a non-empty `images` array or a `text` string" }, 400),
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

  let images: ScanImage[] = [];
  let pastedText: string | undefined;
  let termStart: string | undefined;
  let termEnd: string | undefined;
  let timezone = "UTC";
  try {
    const body = await req.json();
    if (!body || typeof body !== "object") {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }
    const validated = validateInput(body as Record<string, unknown>);
    if (!validated.ok) return validated.response;
    images = validated.images ?? [];
    pastedText = validated.text;
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
  // Pasted text is the same call with no image parts.
  const userContent = pastedText
    ? [{
      type: "text",
      text:
        `Extract the class structure from this syllabus, pasted as text from a course page.\n\n${pastedText}`,
    }]
    : [
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
        // Twenty pages of a dense schedule can be hundreds of rows of JSON. Gemini 2.5
        // Flash tops out at 65535 output tokens; sit well under it so a long term's work
        // can't be cut mid-object and lost to the JSON parse.
        max_tokens: 48000,
      }),
    });
  } catch (err) {
    return jsonResponse({ error: "Failed to reach OpenRouter", detail: String(err) }, 502);
  }
  if (!res.ok) {
    return jsonResponse({ error: "OpenRouter error", detail: await res.text() }, 502);
  }

  // Things the user should be told rather than left to find in their calendar —
  // a meeting block dropped for impossible weekdays, a cap that actually bit.
  const warnings: string[] = [];
  let classes: Record<string, unknown>[];
  try {
    const completion = await res.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "{}";
    classes = normalizeClasses(JSON.parse(content), timezone, warnings);
  } catch (err) {
    return jsonResponse({ error: "Could not parse model output as JSON", detail: String(err) }, 502);
  }

  const capped = applyCaps(classes, warnings);
  const payload: Record<string, unknown> = { classes: capped.classes };
  if (capped.truncated) payload.truncated = true;
  if (warnings.length) payload.warnings = warnings;
  return jsonResponse(payload, 200);
});
