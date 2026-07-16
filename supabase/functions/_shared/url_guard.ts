/**
 * Atlas — shared SSRF guard for server-side fetches of user-supplied URLs
 * (Deno). The Canvas feed URL is pasted by the user and then fetched with the
 * service role; without this, a malicious paste could point the server at
 * internal metadata endpoints (169.254.169.254), localhost admin panels, or
 * private-network hosts.
 *
 * `assertPublicUrl` rejects a URL whose host resolves to a loopback / private /
 * link-local / reserved address (checking EVERY resolved A/AAAA record, and
 * IP literals directly). `safeFetch` follows redirects MANUALLY, re-validating
 * each hop with the same guard, and bounds the whole operation with an
 * AbortController timeout. Legitimate public hosts (school Canvas domains)
 * resolve to routable addresses and pass untouched.
 */

export class BlockedUrlError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BlockedUrlError";
  }
}

const MAX_REDIRECTS = 3;
const DEFAULT_TIMEOUT_MS = 30_000;

/** Strip surrounding brackets (IPv6 literal) and any zone id from a host. */
function bareHost(host: string): string {
  let h = host.replace(/^\[/, "").replace(/\]$/, "");
  const pct = h.indexOf("%");
  if (pct >= 0) h = h.slice(0, pct);
  return h;
}

/** Return the host as an IP-literal string if it already is one, else null.
 *  Lets us skip DNS (and its net permission) for literal hosts. */
function ipLiteral(host: string): string | null {
  const h = bareHost(host);
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h)) return h; // IPv4
  if (h.includes(":")) return h; // IPv6 (only IP literals contain ':')
  return null;
}

/** True for any IPv4/IPv6 address we must never let the server fetch. Anything
 *  unparseable is treated as unsafe (fail closed). */
export function isPrivateAddress(addr: string): boolean {
  const ip = bareHost(addr).trim().toLowerCase();
  return ip.includes(":") ? isPrivateIPv6(ip) : isPrivateIPv4(ip);
}

function isPrivateIPv4(ip: string): boolean {
  const parts = ip.split(".");
  if (parts.length !== 4) return true;
  const o = parts.map((p) => Number(p));
  if (o.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a, b] = o;
  if (a === 0) return true; // 0.0.0.0/8
  if (a === 10) return true; // 10.0.0.0/8 private
  if (a === 127) return true; // 127.0.0.0/8 loopback
  if (a === 169 && b === 254) return true; // 169.254.0.0/16 link-local (metadata)
  if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12 private
  if (a === 192 && b === 168) return true; // 192.168.0.0/16 private
  if (a === 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
  if (a === 192 && b === 0 && o[2] === 0) return true; // 192.0.0.0/24
  if (a === 198 && (b === 18 || b === 19)) return true; // 198.18.0.0/15 benchmark
  if (a >= 224) return true; // 224/4 multicast + 240/4 reserved
  return false;
}

function isPrivateIPv6(ip: string): boolean {
  const a = bareHost(ip).toLowerCase();
  // Embedded/mapped IPv4 (::ffff:1.2.3.4, ::1.2.3.4) — check the v4 part too.
  const v4 = a.match(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
  if (v4 && isPrivateIPv4(v4[1])) return true;
  if (a === "::" || a === "::1") return true; // unspecified / loopback
  if (/^fe[89ab]/.test(a)) return true; // fe80::/10 link-local
  if (/^f[cd]/.test(a)) return true; // fc00::/7 unique-local
  if (/^ff/.test(a)) return true; // ff00::/8 multicast
  return false;
}

/** All addresses `host` resolves to (both A and AAAA). IP literals are returned
 *  as-is without a DNS lookup. Empty array = does not resolve. */
async function resolveAll(host: string): Promise<string[]> {
  const literal = ipLiteral(host);
  if (literal) return [literal];
  const out: string[] = [];
  for (const rt of ["A", "AAAA"] as const) {
    try {
      out.push(...(await Deno.resolveDns(host, rt)));
    } catch {
      // No records of this type (or lookup failed) — fine, try the other.
    }
  }
  return out;
}

/**
 * Validate a URL for a server-side fetch: it must be https and its host must
 * resolve ONLY to public, routable addresses. Throws BlockedUrlError otherwise.
 * Returns the parsed URL on success.
 */
export async function assertPublicUrl(rawUrl: string): Promise<URL> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new BlockedUrlError("invalid URL");
  }
  if (url.protocol !== "https:") {
    throw new BlockedUrlError("only https URLs are allowed");
  }
  const addrs = await resolveAll(url.hostname);
  if (addrs.length === 0) {
    throw new BlockedUrlError(`host does not resolve: ${url.hostname}`);
  }
  for (const addr of addrs) {
    if (isPrivateAddress(addr)) {
      throw new BlockedUrlError(`host resolves to a disallowed address: ${addr}`);
    }
  }
  return url;
}

/**
 * fetch() with SSRF protection: validates the initial URL and every redirect
 * hop (redirects handled manually, capped at `maxRedirects`), all under a single
 * AbortController deadline. The returned Response's body is still streamed to the
 * caller; the deadline also aborts a stalled body read.
 */
export async function safeFetch(
  rawUrl: string,
  init: RequestInit = {},
  opts: { maxRedirects?: number; timeoutMs?: number } = {},
): Promise<Response> {
  const maxRedirects = opts.maxRedirects ?? MAX_REDIRECTS;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  // Don't let the pending deadline keep the isolate alive after we're done; it
  // stays armed to abort a still-streaming body, but is a no-op once settled.
  if (typeof Deno?.unrefTimer === "function") Deno.unrefTimer(timer);

  try {
    let current = await assertPublicUrl(rawUrl);
    for (let hop = 0; ; hop++) {
      const res = await fetch(current, {
        ...init,
        redirect: "manual",
        signal: controller.signal,
      });
      const loc = res.headers.get("location");
      if (res.status >= 300 && res.status < 400 && loc) {
        if (hop >= maxRedirects) {
          await res.body?.cancel();
          throw new BlockedUrlError("too many redirects");
        }
        const next = new URL(loc, current); // resolve relative Location
        await res.body?.cancel();
        current = await assertPublicUrl(next.toString()); // re-validate each hop
        continue;
      }
      return res;
    }
  } catch (err) {
    clearTimeout(timer);
    throw err;
  }
}
