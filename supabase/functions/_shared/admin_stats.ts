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
