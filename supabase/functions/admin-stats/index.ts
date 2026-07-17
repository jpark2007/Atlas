// =====================================================================
// Atlas admin-stats — owner-only dashboard backend (Supabase Edge Function)
//
// POST { code, action: "stats" | "resolve" | "change_code", reportId?, newCode? }
//   • Gates every call on a 4–8 digit access code whose SHA-256 hash lives in
//     public.admin_config (constant-time hash compare). Rate-limits code
//     attempts per IP so the short code can't be brute-forced.
//   • "stats"       → { totalUsers, dmgDownloads, mac, mobile, byPlatform, reports }
//   • "resolve"     → marks bug_reports.id resolved.
//   • "change_code" → verifies the current code, then stores the new code's hash.
//
// Public from the browser (the landing dashboard has no Supabase session), so
// deploy with `--no-verify-jwt` and pin CORS to the landing origin. Auth is the
// access code (checked here against the DB hash) — not a JWT. No env secret.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";
import {
  activesSeries,
  dailyCounts,
  isValidCode,
  platformBreakdown,
  sha256Hex,
  signupSeries,
  snapshotRow,
  timingSafeEqual,
  type DayCount,
  type PingRow,
  type SnapshotRow,
} from "../_shared/admin_stats.ts";

// Public endpoint — scope CORS to the landing origin (mirrors waitlist).
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

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Rate-limit BEFORE checking the code so the short (4–8 digit) space can't be
  // walked: 6 attempts/hour/IP. Keyed by IP (there's no user identity here).
  const rl = await checkRateLimit(supabase, clientIp(req), "admin-stats", 6, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  let code = "";
  let action = "";
  let reportId = "";
  let newCode = "";
  try {
    const body = await req.json();
    code = String(body?.code ?? "");
    action = String(body?.action ?? "");
    reportId = String(body?.reportId ?? "");
    newCode = String(body?.newCode ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Verify the entered code against the stored hash (constant-time).
  const { data: cfg, error: cfgErr } = await supabase
    .from("admin_config").select("value").eq("key", "dash_code_hash").maybeSingle();
  if (cfgErr || !cfg?.value) {
    console.error("admin_config read failed:", cfgErr?.message);
    return json({ error: "Server misconfigured" }, 500);
  }
  const enteredHash = await sha256Hex(code);
  if (!timingSafeEqual(enteredHash, String(cfg.value))) {
    return json({ error: "Invalid code" }, 401);
  }

  if (action === "change_code") {
    if (!isValidCode(newCode)) {
      return json({ error: "New code must be 4–8 digits" }, 422);
    }
    const { error } = await supabase
      .from("admin_config")
      .update({ value: await sha256Hex(newCode) })
      .eq("key", "dash_code_hash");
    if (error) {
      console.error("change_code failed:", error.message);
      return json({ error: "Could not change code" }, 500);
    }
    return json({ ok: true }, 200);
  }

  if (action === "resolve") {
    if (!reportId) return json({ error: "Missing reportId" }, 400);
    const { error } = await supabase
      .from("bug_reports")
      .update({ status: "resolved", resolved_at: new Date().toISOString() })
      .eq("id", reportId);
    if (error) {
      console.error("resolve failed:", error.message);
      return json({ error: "Could not resolve report" }, 500);
    }
    return json({ ok: true }, 200);
  }

  if (action !== "stats") return json({ error: "Unknown action" }, 400);

  const since = new Date(Date.now() - THIRTY_DAYS_MS).toISOString();
  const CHART_DAYS = 90;
  const todayKey = new Date().toISOString().slice(0, 10);
  const windowStart = new Date(Date.now() - CHART_DAYS * 24 * 60 * 60 * 1000)
    .toISOString();

  // Fan out the independent reads.
  const [
    countRes,
    metricRes,
    pingRes,
    reportRes,
    signupRes,
    downloadRes,
    snapshotRes,
  ] = await Promise.all([
    supabase.rpc("admin_user_count"),
    supabase.from("site_metrics").select("count").eq("key", "dmg_downloads").maybeSingle(),
    supabase.from("app_pings").select("user_id, platform").gte("last_seen_at", since),
    supabase
      .from("bug_reports")
      .select("id, message, platform, app_version, status, created_at, resolved_at")
      .order("created_at", { ascending: false })
      .limit(50),
    supabase.rpc("admin_signup_days"),
    supabase.from("download_events").select("created_at").gte("created_at", windowStart),
    supabase
      .from("metric_snapshots")
      .select("day, mac_active_30d, ios_active_30d")
      .gte("day", windowStart.slice(0, 10))
      .order("day", { ascending: true }),
  ]);

  const totalUsers = typeof countRes.data === "number" ? countRes.data : 0;
  const dmgDownloads = Number(metricRes.data?.count ?? 0);
  const { mac, mobile, byPlatform } = platformBreakdown(
    (pingRes.data ?? []) as PingRow[],
  );
  const ios = byPlatform["ios"] ?? 0;

  // ── Time-series shaping ──
  const signups = signupSeries(
    (signupRes.data ?? []) as DayCount[],
    totalUsers,
    todayKey,
    CHART_DAYS,
  );
  const downloads = dailyCounts(
    ((downloadRes.data ?? []) as { created_at: string }[]).map((r) => r.created_at),
    todayKey,
    CHART_DAYS,
  );
  const actives = activesSeries(
    (snapshotRes.data ?? []) as SnapshotRow[],
    { day: todayKey, mac, ios },
  );

  // ── Self-populating history: record today's snapshot on every open. Fire and
  //    forget — a failed write only skips one day of history, never the response.
  const snap = snapshotRow(todayKey, totalUsers, dmgDownloads, mac, ios);
  supabase
    .from("metric_snapshots")
    .upsert({ ...snap, updated_at: new Date().toISOString() }, { onConflict: "day" })
    .then(({ error }) => {
      if (error) console.error("metric_snapshots upsert failed:", error.message);
    });

  return json({
    totalUsers,
    dmgDownloads,
    mac,
    mobile,
    byPlatform,
    reports: reportRes.data ?? [],
    charts: {
      signups: { points: signups.points, priorTotal: signups.priorTotal },
      downloads: { points: downloads },
      actives: { points: actives },
    },
  }, 200);
});
