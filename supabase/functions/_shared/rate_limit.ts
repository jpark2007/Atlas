/**
 * Atlas — shared rate limiter (Deno). One helper, DB-backed (0033), used by
 * every user-facing / public edge function to block hammering without getting in
 * a normal user's way.
 *
 * `checkRateLimit` is a single atomic RPC (public.rate_limit_hit): it counts the
 * request for the current fixed window and reports whether the caller is still
 * under budget. It FAILS OPEN — a limiter/DB hiccup allows the request rather
 * than taking the endpoint down. On a block, respond with `tooManyRequests`.
 *
 * Keying: authenticated endpoints pass the verified user id; the public waitlist
 * passes `clientIp(req)`. Presence-only endpoints (capture) can pass the JWT
 * `sub` via `jwtSubject` when no verified id is available.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface RateLimitResult {
  allowed: boolean;
  retryAfter: number; // seconds until the window resets (0 when allowed)
}

/**
 * Count one request against (key, endpoint) and report if it's within `limit`
 * per `windowSeconds`. Fails OPEN on any RPC error.
 */
export async function checkRateLimit(
  admin: SupabaseClient,
  key: string,
  endpoint: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const { data, error } = await admin.rpc("rate_limit_hit", {
    p_key: key,
    p_endpoint: endpoint,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error(`rate_limit_hit failed (${endpoint}): ${error.message}`);
    return { allowed: true, retryAfter: 0 }; // fail open — never self-DoS
  }
  // The RPC returns a single-row table; supabase-js hands it back as an array.
  const row = (Array.isArray(data) ? data[0] : data) as
    | { allowed?: boolean; retry_after?: number }
    | undefined;
  return {
    allowed: row?.allowed ?? true,
    retryAfter: typeof row?.retry_after === "number" ? row.retry_after : 0,
  };
}

/** A friendly 429 with a Retry-After header. */
export function tooManyRequests(
  retryAfter: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      error: "Too many requests — please slow down and try again in a moment.",
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(Math.max(1, Math.trunc(retryAfter))),
      },
    },
  );
}

/** Best-effort client IP from the proxy headers (the waitlist keys by this). */
export function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff && xff.trim()) return xff.split(",")[0].trim();
  return req.headers.get("cf-connecting-ip")?.trim() || "unknown";
}

/** The `sub` (user id) claim of a Supabase JWT WITHOUT verifying the signature —
 *  only for rate-limit keying on presence-only endpoints (capture), never for
 *  authorization. Returns null if it doesn't decode. */
export function jwtSubject(token: string): string | null {
  try {
    const seg = token.split(".")[1];
    if (!seg) return null;
    let b64 = seg.replace(/-/g, "+").replace(/_/g, "/");
    b64 += "=".repeat((4 - (b64.length % 4)) % 4);
    const payload = JSON.parse(atob(b64));
    return typeof payload?.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}
