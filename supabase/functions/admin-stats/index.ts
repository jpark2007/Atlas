// =====================================================================
// Atlas admin-stats — owner-only dashboard backend (Supabase Edge Function)
//
// POST { code, action, reportId?, newCode?, email? }
//   • Gates every call on a 4–8 digit access code whose SHA-256 hash lives in
//     public.admin_config (constant-time hash compare). Rate-limits code
//     attempts per IP so the short code can't be brute-forced.
//   • "stats"           → real accounts, 7/30-day actives, downloads, reports,
//       signup attribution (0051) by source and by school.
//       Every count comes from an exclusion-aware RPC (0049): the team and the
//       review/test accounts are never counted as users.
//   • "resolve"         → marks bug_reports.id resolved.
//   • "reopen"          → puts a resolved report back in the open list.
//   • "delete"          → removes a report permanently (spam / duplicates).
//   • "change_code"     → verifies the current code, then stores the new code's hash.
//   • "exclude_add"     → adds an email to admin_config.excluded_emails.
//   • "exclude_remove"  → takes one back off the list.
//
// Public from the browser (the landing dashboard has no Supabase session), so
// deploy with `--no-verify-jwt` and pin CORS to the landing origin. Auth is the
// access code (checked here against the DB hash) — not a JWT. No env secret.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, clientIp, tooManyRequests } from "../_shared/rate_limit.ts";
import { corsFor } from "../_shared/cors.ts";
import {
  activesSeries,
  dailyCounts,
  isValidCode,
  sha256Hex,
  signupSeries,
  timingSafeEqual,
  type DayCount,
  type SnapshotRow,
} from "../_shared/admin_stats.ts";

// Public endpoint — scope CORS to the landing origin (mirrors waitlist).


/** admin_actives(win_days) → one row: distinct real accounts, and the split. */
interface ActiveCounts { total: number; mac: number; ios: number }
const actives = (rows: unknown): ActiveCounts => {
  const r = (Array.isArray(rows) ? rows[0] : rows) as
    | { total?: number; mac?: number; ios?: number }
    | null;
  return { total: Number(r?.total ?? 0), mac: Number(r?.mac ?? 0), ios: Number(r?.ios ?? 0) };
};

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

  // Rate-limit BEFORE checking the code so the short (4–8 digit) space can't be
  // walked: 6 attempts/hour/IP. Keyed by IP (there's no user identity here).
  const rl = await checkRateLimit(supabase, clientIp(req), "admin-stats", 6, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);

  let code = "";
  let action = "";
  let reportId = "";
  let newCode = "";
  let email = "";
  try {
    const body = await req.json();
    code = String(body?.code ?? "");
    action = String(body?.action ?? "");
    reportId = String(body?.reportId ?? "");
    newCode = String(body?.newCode ?? "");
    email = String(body?.email ?? "").trim();
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

  // ── the exclusion list ──
  // Same code gate as resolve/reopen. The list lives in admin_config as a JSON
  // array; every count in the DB reads it through admin_is_excluded().
  if (action === "exclude_add" || action === "exclude_remove") {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "Enter a valid email address" }, 422);
    }
    const { data: row, error: readErr } = await supabase
      .from("admin_config").select("value").eq("key", "excluded_emails").maybeSingle();
    if (readErr) {
      console.error("excluded_emails read failed:", readErr.message);
      return json({ error: "Could not read the exclusion list" }, 500);
    }
    let list: string[] = [];
    try {
      const parsed = JSON.parse(String(row?.value ?? "[]"));
      if (Array.isArray(parsed)) list = parsed.map((e) => String(e));
    } catch { /* a corrupt value is replaced, not preserved */ }

    const lower = email.toLowerCase();
    const without = list.filter((e) => e.toLowerCase() !== lower);
    const next = action === "exclude_add" ? [...without, email] : without;

    const { error } = await supabase
      .from("admin_config")
      .upsert({ key: "excluded_emails", value: JSON.stringify(next) }, { onConflict: "key" });
    if (error) {
      console.error("excluded_emails write failed:", error.message);
      return json({ error: "Could not update the exclusion list" }, 500);
    }
    return json({ ok: true }, 200);
  }

  // Undo a resolve — a report closed by a mis-click has to be able to come back,
  // otherwise the only recovery is the SQL editor.
  if (action === "reopen") {
    if (!reportId) return json({ error: "Missing reportId" }, 400);
    const { error } = await supabase
      .from("bug_reports")
      .update({ status: "open", resolved_at: null })
      .eq("id", reportId);
    if (error) {
      console.error("reopen failed:", error.message);
      return json({ error: "Could not reopen report" }, 500);
    }
    return json({ ok: true }, 200);
  }

  // Permanent. Resolving is the reversible "put it away"; this is for spam and
  // duplicates that shouldn't sit in the list at all. The dashboard confirms first.
  if (action === "delete") {
    if (!reportId) return json({ error: "Missing reportId" }, 400);
    const { error } = await supabase
      .from("bug_reports")
      .delete()
      .eq("id", reportId);
    if (error) {
      console.error("delete failed:", error.message);
      return json({ error: "Could not delete report" }, 500);
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

  const CHART_DAYS = 90;
  const todayKey = new Date().toISOString().slice(0, 10);
  const windowStart = new Date(Date.now() - CHART_DAYS * 24 * 60 * 60 * 1000)
    .toISOString();

  // Fan out the independent reads. Every user-facing count goes through an
  // exclusion-aware RPC — nothing here counts rows from auth.users directly.
  const [
    countRes,
    excludedCountRes,
    excludedRes,
    metricRes,
    active7Res,
    active30Res,
    reportRes,
    openRes,
    signupRes,
    downloadRes,
    snapshotRes,
    referralRes,
    schoolRes,
  ] = await Promise.all([
    supabase.rpc("admin_user_count"),
    supabase.rpc("admin_excluded_count"),
    supabase.rpc("admin_excluded_accounts"),
    supabase.from("site_metrics").select("count").eq("key", "dmg_downloads").maybeSingle(),
    supabase.rpc("admin_actives", { win_days: 7 }),
    supabase.rpc("admin_actives", { win_days: 30 }),
    supabase
      .from("bug_reports")
      .select("id, title, message, contact_email, log, platform, app_version, status, created_at, resolved_at")
      .order("created_at", { ascending: false })
      .limit(50),
    supabase
      .from("bug_reports")
      .select("id", { count: "exact", head: true })
      .eq("status", "open"),
    supabase.rpc("admin_signup_days"),
    supabase.from("download_events").select("created_at").gte("created_at", windowStart),
    supabase
      .from("metric_snapshots")
      .select("day, mac_active_30d, ios_active_30d")
      .gte("day", windowStart.slice(0, 10))
      .order("day", { ascending: true }),
    supabase.rpc("admin_referral_counts"),
    supabase.rpc("admin_school_counts"),
  ]);

  const accounts = typeof countRes.data === "number" ? countRes.data : 0;
  const excludedCount = typeof excludedCountRes.data === "number" ? excludedCountRes.data : 0;
  const dmgDownloads = Number(metricRes.data?.count ?? 0);
  const a7 = actives(active7Res.data);
  const a30 = actives(active30Res.data);

  // ── Time-series shaping ──
  const signups = signupSeries(
    (signupRes.data ?? []) as DayCount[],
    accounts,
    todayKey,
    CHART_DAYS,
  );
  const downloads = dailyCounts(
    ((downloadRes.data ?? []) as { created_at: string }[]).map((r) => r.created_at),
    todayKey,
    CHART_DAYS,
  );
  const activePoints = activesSeries(
    (snapshotRes.data ?? []) as SnapshotRow[],
    { day: todayKey, mac: a30.mac, ios: a30.ios },
  );

  // ── Fallback history: the nightly cron owns the snapshot; this only fills a
  //    day the job missed. The RPC refuses to overwrite a row stamped 'cron'.
  //    Fire and forget — a failed write costs one day of history, not the page.
  supabase
    .rpc("admin_snapshot_dashboard", {
      p_day: todayKey,
      p_users: accounts,
      p_downloads: dmgDownloads,
      p_mac30: a30.mac,
      p_ios30: a30.ios,
      p_mac7: a7.mac,
      p_ios7: a7.ios,
    })
    .then(({ error }) => {
      if (error) console.error("metric_snapshots fallback upsert failed:", error.message);
    });

  return json({
    accounts,
    excludedCount,
    excluded: excludedRes.data ?? [],
    dmgDownloads,
    active7: a7,
    active30: a30,
    openReports: openRes.count ?? 0,
    reports: reportRes.data ?? [],
    charts: {
      signups: { points: signups.points, priorTotal: signups.priorTotal },
      downloads: { points: downloads },
      actives: { points: activePoints },
    },
    referralCounts: referralRes.data ?? [],
    schoolCounts: schoolRes.data ?? [],
  }, 200);
});
