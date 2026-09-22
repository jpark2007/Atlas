// =====================================================================
// Atlas admin-stats — owner-only dashboard backend (Supabase Edge Function)
//
// POST { code, action, reportId?, newCode?, email? }
//   • Gates every call on a 4–8 digit access code whose SHA-256 hash lives in
//     public.admin_config (constant-time hash compare). Rate-limits WRONG code
//     attempts per IP (6/hour) so the short code can't be brute-forced; a call
//     with the right code is never counted, so using the dashboard never locks
//     you out. All calls share a loose 300/hour/IP burst cap.
//   • "stats"           → real accounts, 7/30-day actives, downloads, reports,
//       signup attribution (0051) by source and by school.
//       Every count comes from an exclusion-aware RPC (0049): the team and the
//       review/test accounts are never counted as users.
//       Also: every bug report (with the account email when the reporter left
//       no contact address), a per-user roster, version spread and week-one
//       retention.
//   • "resolve"         → marks bug_reports.id resolved.
//   • "reopen"          → puts a resolved report back in the open list.
//   • "delete"          → removes a report permanently (spam / duplicates).
//   • "mark_fixed"      → stamps bug_reports.fixed_at (0052).
//   • "unmark_fixed"    → clears it.
//   • "mark_replied"    → stamps bug_reports.replied_at with now.
//   • "change_code"     → verifies the current code, then stores the new code's hash.
//   • "exclude_add"     → adds an email to admin_config.excluded_emails.
//   • "exclude_remove"  → takes one back off the list.
//
// Public from the browser (the landing dashboard has no Supabase session), so
// deploy with `--no-verify-jwt` and pin CORS to the landing origin. Auth is the
// access code (checked here against the DB hash) — not a JWT. No env secret.
// =====================================================================

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  checkRateLimit,
  clientIp,
  rateLimitCount,
  tooManyRequests,
} from "../_shared/rate_limit.ts";
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

interface ReportRow { user_id: string | null; contact_email: string | null; status: string }
interface PingRow { user_id: string; platform: string; app_version: string | null; last_seen_at: string }
interface AuthUser { id: string; email: string | null; created_at: string }

/** Every auth user (id, email, signup), paged through the service-role admin API.
 *  A failed page logs and returns what it has — the page loses emails, not stats. */
async function listAllUsers(supabase: SupabaseClient): Promise<AuthUser[]> {
  const out: AuthUser[] = [];
  const perPage = 1000;
  for (let page = 1; ; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error) {
      console.error("auth listUsers failed:", error.message);
      return out;
    }
    for (const u of data.users) out.push({ id: u.id, email: u.email ?? null, created_at: u.created_at });
    if (data.users.length < perPage) return out;
  }
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

  // Rate-limit BEFORE checking the code so the short (4–8 digit) space can't be
  // walked: 6 wrong codes/hour/IP. The wrong-code counter is only READ here and
  // only charged below when the code is wrong, so the right code is never
  // limited by it. The atomic all-calls cap bounds parallel guess bursts that
  // could otherwise all pass the read before any of them is counted. Keyed by
  // IP (no user identity here).
  const ip = clientIp(req);
  if (await rateLimitCount(supabase, ip, "admin-stats", 3600) >= 6) {
    return tooManyRequests(3600 - (Math.floor(Date.now() / 1000) % 3600), corsHeaders);
  }
  const burst = await checkRateLimit(supabase, ip, "admin-stats-all", 300, 3600);
  if (!burst.allowed) return tooManyRequests(burst.retryAfter, corsHeaders);

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
    const rl = await checkRateLimit(supabase, ip, "admin-stats", 6, 3600);
    if (!rl.allowed) return tooManyRequests(rl.retryAfter, corsHeaders);
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

  // Support bookkeeping (0052): was it fixed, did the reporter hear back.
  const STAMPS: Record<string, Record<string, string | null>> = {
    mark_fixed: { fixed_at: new Date().toISOString() },
    unmark_fixed: { fixed_at: null },
    mark_replied: { replied_at: new Date().toISOString() },
  };
  if (action in STAMPS) {
    if (!reportId) return json({ error: "Missing reportId" }, 400);
    const { error } = await supabase
      .from("bug_reports")
      .update(STAMPS[action])
      .eq("id", reportId);
    if (error) {
      console.error(`${action} failed:`, error.message);
      return json({ error: "Could not update report" }, 500);
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
    authUsers,
    pingRes,
    scanRes,
    canvasRes,
    googleRes,
  ] = await Promise.all([
    supabase.rpc("admin_user_count"),
    supabase.rpc("admin_excluded_count"),
    supabase.rpc("admin_excluded_accounts"),
    supabase.from("site_metrics").select("count").eq("key", "dmg_downloads").maybeSingle(),
    supabase.rpc("admin_actives", { win_days: 7 }),
    supabase.rpc("admin_actives", { win_days: 30 }),
    supabase
      .from("bug_reports")
      .select("id, user_id, title, message, contact_email, log, platform, app_version, status, created_at, resolved_at, fixed_at, replied_at")
      .order("created_at", { ascending: true })
      .limit(1000),
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
    listAllUsers(supabase),
    supabase.from("app_pings").select("user_id, platform, app_version, last_seen_at"),
    supabase.from("syllabus_scans").select("user_id"),
    supabase.from("canvas_connections").select("user_id"),
    supabase.from("google_connections").select("user_id"),
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

  // ── Support + people ──
  // One auth-admin listing covers every email lookup below; no per-report calls.
  const emailById = new Map(authUsers.map((u) => [u.id, u.email ?? null]));
  const reportRows = (reportRes.data ?? []) as ReportRow[];
  const reports = reportRows.map((r) => ({
    ...r,
    email: r.contact_email ?? (r.user_id ? emailById.get(r.user_id) ?? null : null),
  }));

  // Same exclusion as every count: admin_excluded_accounts is the DB predicate's
  // own output, so the roster can't drift from the headline numbers.
  const excludedEmails = new Set(
    ((excludedRes.data ?? []) as { email: string | null }[])
      .map((e) => String(e.email ?? "").toLowerCase()),
  );
  const realUsers = authUsers.filter((u) => !u.email || !excludedEmails.has(u.email.toLowerCase()));
  const realIds = new Set(realUsers.map((u) => u.id));

  const pings = ((pingRes.data ?? []) as PingRow[]).filter((p) => realIds.has(p.user_id));
  const tally = (rows: unknown) => {
    const m = new Map<string, number>();
    for (const r of (rows ?? []) as { user_id: string }[]) m.set(r.user_id, (m.get(r.user_id) ?? 0) + 1);
    return m;
  };
  const scans = tally(scanRes.data);
  const canvas = tally(canvasRes.data);
  const google = tally(googleRes.data);

  const users = realUsers.map((u) => {
    const own = pings.filter((p) => p.user_id === u.id);
    const mine = reportRows.filter((r) => r.user_id === u.id);
    return {
      id: u.id,
      email: u.email ?? null,
      created_at: u.created_at,
      platforms: own.map((p) => ({ platform: p.platform, app_version: p.app_version, last_seen_at: p.last_seen_at })),
      last_seen_at: own.reduce<string | null>((max, p) => (!max || p.last_seen_at > max ? p.last_seen_at : max), null),
      reports_open: mine.filter((r) => r.status === "open").length,
      reports_total: mine.length,
      syllabus_scans: scans.get(u.id) ?? 0,
      canvas_connections: canvas.get(u.id) ?? 0,
      google_connections: google.get(u.id) ?? 0,
    };
  }).sort((a, b) => (a.created_at < b.created_at ? 1 : -1));

  // Version spread: real users per platform + version, seen in the last 30 days.
  // app_pings is keyed (user, platform), so each row is already one user.
  const DAY = 24 * 60 * 60 * 1000;
  const since30 = new Date(Date.now() - 30 * DAY).toISOString();
  const spread = new Map<string, { platform: string; app_version: string | null; n: number }>();
  for (const p of pings) {
    if (p.last_seen_at < since30) continue;
    const key = p.platform + "|" + (p.app_version ?? "");
    const row = spread.get(key) ?? { platform: p.platform, app_version: p.app_version, n: 0 };
    row.n += 1;
    spread.set(key, row);
  }
  const versionSpread = [...spread.values()].sort((a, b) =>
    a.platform.localeCompare(b.platform) || b.n - a.n);

  // Week-one retention: of real users who signed up 7+ days ago, how many were
  // still seen at least 7 days after signing up.
  const eligible = users.filter((u) => Date.parse(u.created_at) <= Date.now() - 7 * DAY);
  const retained = eligible.filter((u) =>
    u.last_seen_at && Date.parse(u.last_seen_at) >= Date.parse(u.created_at) + 7 * DAY);

  return json({
    accounts,
    excludedCount,
    excluded: excludedRes.data ?? [],
    dmgDownloads,
    active7: a7,
    active30: a30,
    openReports: openRes.count ?? 0,
    reports,
    users,
    versionSpread,
    retention: { eligible: eligible.length, retained: retained.length },
    charts: {
      signups: { points: signups.points, priorTotal: signups.priorTotal },
      downloads: { points: downloads },
      actives: { points: activePoints },
    },
    referralCounts: referralRes.data ?? [],
    schoolCounts: schoolRes.data ?? [],
  }, 200);
});
