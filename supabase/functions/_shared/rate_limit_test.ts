import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { checkRateLimit, clientIp, jwtSubject, tooManyRequests } from "./rate_limit.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// The window arithmetic itself lives in the SQL RPC (rate_limit_hit, 0033) and is
// exercised by the deploy E2E. These cover the helper's TS logic: how it forwards
// budgets, interprets the RPC's row, fails OPEN, and keys callers. `admin` is
// mocked — no network, no DB.

/** A fake SupabaseClient whose .rpc returns a scripted result and records the call. */
function fakeAdmin(
  result: { data: unknown; error: { message: string } | null },
): { admin: SupabaseClient; calls: { fn: string; args: unknown }[] } {
  const calls: { fn: string; args: unknown }[] = [];
  const admin = {
    // deno-lint-ignore no-explicit-any
    rpc(fn: string, args: unknown): any {
      calls.push({ fn, args });
      return Promise.resolve(result);
    },
  } as unknown as SupabaseClient;
  return { admin, calls };
}

Deno.test("checkRateLimit: under budget → allowed, forwards budget + window", async () => {
  const { admin, calls } = fakeAdmin({
    data: [{ allowed: true, retry_after: 0 }],
    error: null,
  });
  const res = await checkRateLimit(admin, "user-1", "capture", 30, 60);
  assertEquals(res, { allowed: true, retryAfter: 0 });
  assertEquals(calls[0].fn, "rate_limit_hit");
  assertEquals(calls[0].args, {
    p_key: "user-1",
    p_endpoint: "capture",
    p_limit: 30,
    p_window_seconds: 60,
  });
});

Deno.test("checkRateLimit: over budget → blocked with retryAfter", async () => {
  const { admin } = fakeAdmin({
    data: [{ allowed: false, retry_after: 42 }],
    error: null,
  });
  assertEquals(await checkRateLimit(admin, "ip-9", "waitlist", 5, 3600), {
    allowed: false,
    retryAfter: 42,
  });
});

Deno.test("checkRateLimit: RPC error → fails OPEN (never self-DoS)", async () => {
  const { admin } = fakeAdmin({ data: null, error: { message: "boom" } });
  assertEquals(await checkRateLimit(admin, "user-1", "capture", 30, 60), {
    allowed: true,
    retryAfter: 0,
  });
});

Deno.test("checkRateLimit: tolerates a bare object (not wrapped in an array)", async () => {
  const { admin } = fakeAdmin({ data: { allowed: false, retry_after: 7 }, error: null });
  assertEquals(await checkRateLimit(admin, "k", "e", 1, 60), {
    allowed: false,
    retryAfter: 7,
  });
});

Deno.test("tooManyRequests: 429 + friendly body + Retry-After header (min 1)", async () => {
  const res = tooManyRequests(0, { "Access-Control-Allow-Origin": "*" });
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After"), "1"); // clamped up from 0
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  const body = await res.json();
  assertEquals(typeof body.error, "string");
});

Deno.test("clientIp: first hop of X-Forwarded-For, else fallback", () => {
  assertEquals(
    clientIp(new Request("https://x", { headers: { "x-forwarded-for": "1.2.3.4, 5.6.7.8" } })),
    "1.2.3.4",
  );
  assertEquals(clientIp(new Request("https://x")), "unknown");
});

Deno.test("jwtSubject: extracts sub, null on garbage", () => {
  // {"sub":"abc"} base64url as the payload segment.
  const payload = btoa(JSON.stringify({ sub: "abc" })).replace(/=+$/, "");
  assertEquals(jwtSubject(`h.${payload}.sig`), "abc");
  assertEquals(jwtSubject("not-a-jwt"), null);
  assertEquals(jwtSubject(""), null);
});
