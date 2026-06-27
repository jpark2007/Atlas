/**
 * Atlas — capture Edge Function (Deno)
 *
 * POST /functions/v1/capture
 * Body:   { text: string }
 * Returns: { kind, title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes? }
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

const SYSTEM_PROMPT = `You are Atlas, a personal life-management AI. \
Given a user's free-text capture, classify it and return ONLY a JSON object matching this schema — \
no markdown, no explanation, just the raw JSON:

{
  "kind": "task" | "event" | "note",
  "title": string,            // concise, actionable title
  "spaceName": string,        // one of: "School", "Work", "Personal", "Health", "Finance", "Other"
  "projectName"?: string,     // if the text mentions a specific project/class
  "dueISO"?: string,          // ISO 8601 UTC if a due date is mentioned (tasks)
  "startISO"?: string,        // ISO 8601 UTC if a start time is mentioned (events)
  "durationMin"?: number,     // duration in minutes (events, default 60 if not specified)
  "notes"?: string            // extra detail / body text (notes, or longer event notes)
}

Rules:
- "task"  = something to do (verb phrase, deadline, assignment, chore)
- "event" = a meeting, appointment, session, or time-bound activity
- "note"  = a thought, idea, reference, or piece of information to remember
- If the text is ambiguous, prefer "task".
- Use today's date as the reference point for relative dates ("Thursday", "next week", etc.).
- Always populate kind, title, and spaceName. All other fields are optional.`;

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
  try {
    const body = await req.json();
    if (typeof body?.text !== "string" || !body.text.trim()) {
      return new Response(
        JSON.stringify({ error: "Body must contain a non-empty `text` string" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }
    text = body.text.trim();
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
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: text },
        ],
        response_format: { type: "json_object" },
        temperature: 0.2,
        max_tokens: 256,
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

  // Parse the model's JSON content
  let captureResult: Record<string, unknown>;
  try {
    const completion = await openRouterResponse.json();
    const content: string = completion?.choices?.[0]?.message?.content ?? "{}";
    captureResult = JSON.parse(content);
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Could not parse model output as JSON", detail: String(err) }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify(captureResult),
    { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
  );
});
