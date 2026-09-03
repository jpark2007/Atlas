// =====================================================================
// Atlas track-download — DMG download counter (Supabase Edge Function)
//
// POST (no body needed). Bumps site_metrics.dmg_downloads by one, at most once
// per visitor per UTC day: the landing "Download for Mac" button fires a
// non-blocking beacon here on click, and a click is cheap to repeat. The
// de-dupe key is sha256(client IP + UTC day), stored in download_hits — the raw
// IP is never written down. Deploy with `--no-verify-jwt`; CORS pinned to the
// landing origin; rate-limited per IP so the counter can't be spammed.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";
import { corsFor } from "../_shared/cors.ts";

/** sha256 → lowercase hex. The de-dupe key is a hash so no visitor IP is stored. */
async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

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

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 30 clicks/hour/IP — generous for a human, a wall for a script.
  const ip = clientIp(req);
  const rl = await checkRateLimit(supabase, ip, "track-download", 30, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  // One count per visitor per UTC day. The insert IS the check: ignoring
  // duplicates returns an empty set when this hash was already seen today, so
  // a repeat click falls straight through to the same ok response.
  const day = new Date().toISOString().slice(0, 10);
  const hash = await sha256Hex(ip + "|" + day);
  const { data: hit, error: hitErr } = await supabase
    .from("download_hits")
    .upsert({ hash, day }, { onConflict: "hash", ignoreDuplicates: true })
    .select("hash");
  if (hitErr) {
    console.error("track-download dedupe failed:", hitErr.message);
    return json({ ok: true }, 200); // never block the download over a counter
  }
  if (!hit || hit.length === 0) return json({ ok: true }, 200); // already counted today

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

  // Also log a timestamped event so downloads can be charted per day. The
  // site_metrics counter above stays the source of truth for the all-time tile.
  const { error: evErr } = await supabase.from("download_events").insert({});
  if (evErr) console.error("track-download event insert failed:", evErr.message);

  return json({ ok: true }, 200);
});
