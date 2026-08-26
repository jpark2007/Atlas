// =====================================================================
// Atlas support-request — the website's "get help" form (Edge Function)
//
// Accepts POST { message, email?, subject? } from landing/support.html and
// files it as a row in public.bug_reports with platform "web" and a null
// user_id — the same table the in-app "Report a bug" flow writes to, so web
// requests land in the owner dashboard beside the in-app ones.
//
// RLS gives anon no insert path on bug_reports (by design: clients may only
// file their OWN authenticated report), so this runs on the service role and
// is the only door open to the public.
//
// Deploy with `--no-verify-jwt` so the form can call it without a key.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";
import { corsFor } from "../_shared/cors.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Hidden honeypot, same trick as the waitlist form: real browsers leave it
// empty; bots that fill every input give themselves away.
const HONEYPOT_FIELD = "referral_code";

// Mirrors the table's own check constraints (0037 / 0039) so an over-long body
// is refused with a readable message instead of a Postgres error.
const MAX_MESSAGE = 4000;
const MAX_SUBJECT = 200;

Deno.serve(async (req: Request) => {
  // Per-request: the allowed origin depends on who is calling (see _shared/cors.ts).
  const corsHeaders = corsFor(req);
  const json = (payload: unknown, status: number): Response =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let message = "";
  let email = "";
  let subject = "";
  let honeypot = "";
  try {
    const body = await req.json();
    message = String(body?.message ?? "").trim();
    email = String(body?.email ?? "").trim().toLowerCase();
    subject = String(body?.subject ?? "").trim();
    honeypot = String(body?.[HONEYPOT_FIELD] ?? "").trim();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Honeypot tripped → return the SAME success a real submission gets (never
  // tip off the bot) but write nothing.
  if (honeypot !== "") return json({ ok: true }, 200);

  if (message.length < 2) return json({ error: "Tell us what's happening" }, 422);
  if (message.length > MAX_MESSAGE) {
    return json({ error: "That message is too long — trim it a little" }, 422);
  }
  if (subject.length > MAX_SUBJECT) subject = subject.slice(0, MAX_SUBJECT);
  // Email is optional (someone can report a bug without wanting a reply) but a
  // malformed one is refused rather than stored — an unreachable address in the
  // dashboard is worse than a blank.
  if (email !== "" && (!EMAIL_RE.test(email) || email.length > 320)) {
    return json({ error: "That email doesn't look right" }, 422);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Public endpoint — keyed by IP. 5/hour is plenty for a human asking for help
  // (and re-sending after a typo), and stops a script filling the dashboard.
  const rl = await checkRateLimit(supabase, clientIp(req), "support-request", 5, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  const { error } = await supabase.from("bug_reports").insert({
    user_id: null,               // nobody is signed in on the website
    title: subject || null,
    message,
    contact_email: email || null,
    platform: "web",
  });

  if (error) {
    console.error("support-request insert failed:", error.message);
    return json({ error: "Could not send that. Try again in a moment." }, 500);
  }

  return json({ ok: true }, 200);
});
