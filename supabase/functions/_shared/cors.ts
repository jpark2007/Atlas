// =====================================================================
// Shared CORS for the PUBLIC (no-JWT) functions the landing site calls.
//
// The site moved to www.atlaslm.net (atlaslm.net 308-redirects to www), but
// these functions were still pinned to the old atlaslm.vercel.app origin — so
// every browser call from the live site was blocked. Rather than re-pin to one
// origin and break the next move, reflect the request's Origin when it is one
// of ours, and fall back to the primary domain otherwise.
//
// Still an allow-list, never `*`: only Atlas's own pages may POST here.
// =====================================================================

export const ALLOWED_ORIGINS = [
  "https://www.atlaslm.net",
  "https://atlaslm.net",
  "https://atlaslm.vercel.app",
];

const PRIMARY = ALLOWED_ORIGINS[0];

/// CORS headers for one request. `Vary: Origin` so a cache can't hand the
/// wrong origin's response to the next caller.
export function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes(origin) ? origin : PRIMARY,
    "Vary": "Origin",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
