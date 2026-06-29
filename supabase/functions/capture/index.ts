/**
 * Atlas — capture Edge Function (Deno)
 *
 * POST /functions/v1/capture
 * Body:   { text: string,
 *           spaces?: [{ name: string,
 *                       projects: (string | { name: string, code?: string, overview?: string })[] }] }
 *          Projects may be bare names (legacy) or objects whose code + short
 *          overview give the model description-aware routing context.
 * Returns: JSON ARRAY of capture items:
 *   [{ kind, title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes? }, ...]
 *
 * The model splits a multi-item paragraph ("essay due thu, gym 3x, dinner sunday")
 * into multiple objects. When `spaces` is supplied, the user's real Space + project
 * names are injected into the prompt so routing uses their actual buckets.
 *
 * Requires:
 *   - Authorization: Bearer <Supabase JWT>  (presence-only check for v1)
 *   - OPENROUTER_API_KEY set as a Supabase Edge Function secret
 *
 * Deploy:  supabase functions deploy capture
 * Secrets: supabase secrets set OPENROUTER_API_KEY=<key>
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// A project is either a bare name (legacy clients) or an object carrying an
// optional short code and description used for description-aware routing.
type ContextProject = string | { name: string; code?: string; overview?: string };
type ContextSpace = { name: string; projects: ContextProject[] };

const DEFAULT_SPACES = ["School", "Work", "Personal", "Health", "Finance", "Other"];

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
    const code = typeof p.code === "string" && p.code.trim().length
      ? ` [${p.code.trim()}]` : "";
    const desc = typeof p.overview === "string" && p.overview.trim().length
      ? ` — ${p.overview.trim()}` : "";
    return `"${name}"${code}${desc}`;
  }
  return null;
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
- "projectName": when an item clearly belongs to one of that space's listed projects \
(match on the name, code, or description), set it to the EXACT project name shown above \
(without the code/description). Otherwise omit it.`;
}

function buildSystemPrompt(spaces: ContextSpace[] | undefined): string {
  const nowISO = new Date().toISOString();
  return `You are Atlas, a personal life-management AI. \
Today's date and time (UTC) is: ${nowISO}. Use this as the reference for ALL relative \
dates ("tomorrow", "next week", "Friday", etc.). \
Given a user's free-text capture, classify it and split it into one or more items. \
A single paragraph can contain MULTIPLE items (e.g. "essay due thursday, gym 3x this \
week, dinner with mom sunday" → three items). Return ONLY a JSON object of the form \
{ "items": [ ... ] } — no markdown, no explanation, just the raw JSON. \
Each element of "items" matches this schema:

{
  "kind": "task" | "event" | "note",
  "title": string,            // concise, actionable title
  "spaceName": string,        // see routing rules below
  "projectName"?: string,     // if the item belongs to a specific project/class
  "dueISO"?: string,          // Full ISO 8601 UTC datetime, e.g. "2026-06-30T00:00:00Z" (tasks)
  "startISO"?: string,        // Full ISO 8601 UTC datetime, e.g. "2026-06-30T09:00:00Z" (events)
  "durationMin"?: number,     // duration in minutes (events, default 60 if not specified)
  "notes"?: string            // extra detail / body text (notes, or longer event notes)
}

Routing:
${spacesBlock(spaces)}

Rules:
- Split distinct to-dos / events / notes into SEPARATE items. A single self-contained
  capture is a one-element array.
- "task"  = something to do (verb phrase, deadline, assignment, chore)
- "event" = a meeting, appointment, session, or time-bound activity
- "note"  = a thought, idea, reference, or piece of information to remember
- If an item is ambiguous, prefer "task".
- Always populate kind, title, and spaceName. All other fields are optional.`;
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

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // Require Authorization header (presence check — RLS handles real auth)
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Missing or invalid Authorization header" }),
      { status: 401, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Parse request body
  let text: string;
  let spaces: ContextSpace[] | undefined;
  try {
    const body = await req.json();
    if (typeof body?.text !== "string" || !body.text.trim()) {
      return new Response(
        JSON.stringify({ error: "Body must contain a non-empty `text` string" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }
    text = body.text.trim();
    if (Array.isArray(body.spaces)) {
      spaces = body.spaces as ContextSpace[];
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

  // Call OpenRouter
  let openRouterResponse: Response;
  try {
    openRouterResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://atlas.app",
        "X-Title": "Atlas Life Manager",
      },
      body: JSON.stringify({
        model: "openai/gpt-4o-mini",
        messages: [
          { role: "system", content: buildSystemPrompt(spaces) },
          { role: "user", content: text },
        ],
        response_format: { type: "json_object" },
        temperature: 0.2,
        max_tokens: 1024,
      }),
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Failed to reach OpenRouter", detail: String(err) }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  if (!openRouterResponse.ok) {
    const errorText = await openRouterResponse.text();
    return new Response(
      JSON.stringify({ error: "OpenRouter error", detail: errorText }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Parse the model's JSON content → a flat array of capture items.
  let items: Record<string, unknown>[];
  try {
    const completion = await openRouterResponse.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "{}";
    items = normalizeItems(JSON.parse(content));
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Could not parse model output as JSON", detail: String(err) }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Always return a JSON ARRAY (possibly empty) so the client can decode uniformly.
  return new Response(
    JSON.stringify(items),
    { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
  );
});
