// =====================================================================
// Atlas waitlist — Supabase Edge Function
//
//
// Accepts POST { "email": "you@example.com" }, validates it, and inserts a
// lowercased row into public.waitlist. Duplicate emails are ignored.
// Deploy with `--no-verify-jwt` so the public form can call it without a key.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let email = "";
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!EMAIL_RE.test(email) || email.length > 320) {
    return json({ error: "Invalid email" }, 422);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Public endpoint — keyed by IP so a script can't flood the table. 5/hour is
  // plenty for a human signing up (and re-trying a typo).
  const rl = await checkRateLimit(supabase, clientIp(req), "waitlist", 5, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  const { error } = await supabase
    .from("waitlist")
    .upsert({ email }, { onConflict: "email", ignoreDuplicates: true });

  if (error) {
    console.error("waitlist insert failed:", error.message);
    return json({ error: "Could not save email" }, 500);
  }

  return json({ ok: true }, 200);
});
