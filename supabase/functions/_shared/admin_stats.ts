/**
 * Atlas — owner-dashboard pure helpers (Deno). Kept side-effect-free so they can
 * be unit-tested without a DB: the admin-stats function does the I/O, these do
 * the counting.
 */

/** A minimal app_pings row shape (only the fields the breakdown needs). */
export interface PingRow {
  user_id: string;
  platform: string;
}

/** Distinct-user counts per platform, plus a Mac/mobile roll-up for the tiles.
 *  A user active on two platforms counts once per platform (distinct user id
 *  within each platform bucket). */
export function platformBreakdown(rows: PingRow[]): {
  mac: number;
  mobile: number;
  byPlatform: Record<string, number>;
} {
  const seen: Record<string, Set<string>> = {};
  for (const r of rows) {
    const p = (r.platform || "").toLowerCase();
    if (!p || !r.user_id) continue;
    (seen[p] ??= new Set()).add(r.user_id);
  }
  const byPlatform: Record<string, number> = {};
  for (const [p, users] of Object.entries(seen)) byPlatform[p] = users.size;

  // "mobile" = anything that isn't the Mac app (ios today; room for others).
  const mac = byPlatform["macos"] ?? 0;
  let mobile = 0;
  for (const [p, n] of Object.entries(byPlatform)) if (p !== "macos") mobile += n;

  return { mac, mobile, byPlatform };
}

/** Constant-time string compare — avoids leaking the code hash through
 *  early-exit timing. Both operands are fixed-length SHA-256 hex, so the length
 *  short-circuit reveals nothing. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** SHA-256 → lowercase hex, matching what the migration seeds and Postgres would
 *  produce. Used to compare an entered code against the stored hash without ever
 *  persisting plaintext. */
export async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** A valid access code is 4–8 digits (the initial "2026" is 4; future codes may
 *  be longer). Rejects anything non-numeric so the code space stays predictable. */
export function isValidCode(code: string): boolean {
  return /^\d{4,8}$/.test(code);
}

// ─────────────────────────────────────────────────────────────
// Time-series shaping for the dashboard charts. Pure + UTC-only:
// every "day" is a YYYY-MM-DD key derived from the ISO timestamp's
// date part, so bucketing never depends on the server's timezone.
// ─────────────────────────────────────────────────────────────

export interface DayCount {
  day: string;
  n: number;
}
export interface CumPoint {
  day: string;
  n: number;
  cumulative: number;
}
export interface SnapshotRow {
  day: string;
  mac_active_30d: number;
  ios_active_30d: number;
}
export interface ActivePoint {
  day: string;
  mac: number;
  ios: number;
}

/** The UTC date part (YYYY-MM-DD) of an ISO timestamp or date string. */
export function dayKey(iso: string): string {
  return String(iso).slice(0, 10);
}

/** The last `days` UTC day-keys ending at (and including) `todayKey`, ascending. */
export function dayWindow(todayKey: string, days: number): string[] {
  const DAY = 86400000;
  const end = Date.parse(todayKey + "T00:00:00Z");
  const out: string[] = [];
  for (let i = days - 1; i >= 0; i--) {
    out.push(new Date(end - i * DAY).toISOString().slice(0, 10));
  }
  return out;
}

/** Bucket ISO timestamps into per-day counts across a fixed, zero-filled window. */
export function dailyCounts(
  timestamps: string[],
  todayKey: string,
  days: number,
): DayCount[] {
  const counts: Record<string, number> = {};
  for (const t of timestamps) {
    const k = dayKey(t);
    counts[k] = (counts[k] ?? 0) + 1;
  }
  return dayWindow(todayKey, days).map((day) => ({ day, n: counts[day] ?? 0 }));
}

/** Cumulative signups across the window. The running total is anchored so the
 *  final point equals `totalUsers` exactly: everything older than the window is
 *  folded into `priorTotal` (totalUsers minus the signups that fall inside it),
 *  which also absorbs any deleted-user drift. `dayRows` are the per-day counts
 *  from admin_signup_days(); rows outside the window are ignored (already in the
 *  baseline). */
export function signupSeries(
  dayRows: DayCount[],
  totalUsers: number,
  todayKey: string,
  days: number,
): { points: CumPoint[]; priorTotal: number } {
  const byDay: Record<string, number> = {};
  for (const r of dayRows) byDay[dayKey(r.day)] = (Number(r.n) || 0);

  const window = dayWindow(todayKey, days);
  let inWindow = 0;
  for (const d of window) inWindow += byDay[d] ?? 0;
  const priorTotal = Math.max(0, totalUsers - inWindow);

  let running = priorTotal;
  const points = window.map((day) => {
    const n = byDay[day] ?? 0;
    running += n;
    return { day, n, cumulative: running };
  });
  return { points, priorTotal };
}

/** The metric_snapshots row to upsert for today. Shape mirrors the table columns
 *  (updated_at is added at write time by the caller). */
export function snapshotRow(
  todayKey: string,
  totalUsers: number,
  dmgDownloads: number,
  mac: number,
  ios: number,
): {
  day: string;
  total_users: number;
  dmg_downloads: number;
  mac_active_30d: number;
  ios_active_30d: number;
} {
  return {
    day: todayKey,
    total_users: totalUsers,
    dmg_downloads: dmgDownloads,
    mac_active_30d: mac,
    ios_active_30d: ios,
  };
}

/** Mac vs iOS actives over time from stored snapshots, with today's freshly
 *  computed values merged in (so the chart shows today even on the first-ever
 *  open, before the upsert is read back). Sparse by design — pre-history days
 *  genuinely have no snapshot, so they're absent rather than zero-filled. */
export function activesSeries(
  rows: SnapshotRow[],
  today: { day: string; mac: number; ios: number },
): ActivePoint[] {
  const byDay: Record<string, { mac: number; ios: number }> = {};
  for (const r of rows) {
    byDay[dayKey(r.day)] = {
      mac: Number(r.mac_active_30d) || 0,
      ios: Number(r.ios_active_30d) || 0,
    };
  }
  byDay[today.day] = { mac: today.mac, ios: today.ios };
  return Object.keys(byDay)
    .sort()
    .map((day) => ({ day, mac: byDay[day].mac, ios: byDay[day].ios }));
}
