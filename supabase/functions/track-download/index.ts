// =====================================================================
// Atlas track-download — DMG download counter (Supabase Edge Function)
//
// POST (no body needed). Bumps site_metrics.dmg_downloads by one. Public and
// dumb by design: the landing "Download for Mac" button fires a non-blocking
// beacon here on click. Deploy with `--no-verify-jwt`; CORS pinned to the
// landing origin; rate-limited per IP so the counter can't be spammed.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://atlaslm.vercel.app",
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
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 30 clicks/hour/IP — generous for a human, a wall for a script.
  const rl = await checkRateLimit(supabase, clientIp(req), "track-download", 30, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  // Read-modify-write through the service role. A lost race just undercounts by
  // one, which is fine for a vanity download counter — no RPC/locking needed.
  const { data, error: readErr } = await supabase
    .from("site_metrics").select("count").eq("key", "dmg_downloads").maybeSingle();
  if (readErr) {
    console.error("track-download read failed:", readErr.message);
    return json({ ok: true }, 200); // never block the download over a counter
  }
  const next = Number(data?.count ?? 0) + 1;
  const { error: upErr } = await supabase
    .from("site_metrics")
    .upsert({ key: "dmg_downloads", count: next }, { onConflict: "key" });
  if (upErr) console.error("track-download write failed:", upErr.message);

  return json({ ok: true }, 200);
});
