/**
 * Tests for the SSRF URL guard. IP-literal hosts short-circuit DNS, so these
 * run without network access. `deno test` here should stay green alongside the
 * other _shared tests.
 */
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assertPublicUrl, BlockedUrlError, isPrivateAddress } from "./url_guard.ts";

// ── isPrivateAddress: the range table ──────────────────────────
Deno.test("isPrivateAddress blocks IPv4 private / reserved ranges", () => {
  for (
    const ip of [
      "0.0.0.0",
      "10.1.2.3",
      "127.0.0.1",
      "169.254.169.254", // cloud metadata endpoint
      "172.16.0.1",
      "172.31.255.255",
      "192.168.1.1",
      "100.64.0.1", // CGNAT
      "192.0.0.1",
      "198.18.0.1",
      "224.0.0.1", // multicast
      "255.255.255.255",
    ]
  ) {
    assertEquals(isPrivateAddress(ip), true, `${ip} should be blocked`);
  }
});

Deno.test("isPrivateAddress allows public IPv4", () => {
  for (const ip of ["8.8.8.8", "1.1.1.1", "140.82.112.3", "172.15.0.1", "172.32.0.1"]) {
    assertEquals(isPrivateAddress(ip), false, `${ip} should be allowed`);
  }
});

Deno.test("isPrivateAddress blocks IPv6 loopback / local / mapped", () => {
  for (
    const ip of [
      "::1",
      "::",
      "fe80::1",
      "fc00::1",
      "fd12:3456::1",
      "ff02::1",
      "::ffff:127.0.0.1", // IPv4-mapped loopback
      "::ffff:10.0.0.1", // IPv4-mapped private
    ]
  ) {
    assertEquals(isPrivateAddress(ip), true, `${ip} should be blocked`);
  }
});

Deno.test("isPrivateAddress allows a public IPv6", () => {
  assertEquals(isPrivateAddress("2606:4700:4700::1111"), false); // Cloudflare DNS
});

Deno.test("isPrivateAddress fails closed on garbage", () => {
  assertEquals(isPrivateAddress("not-an-ip"), true);
  assertEquals(isPrivateAddress("999.999.999.999"), true);
});

// ── assertPublicUrl: scheme + literal-host rejection (no DNS) ───
Deno.test("assertPublicUrl rejects non-https", async () => {
  await assertRejects(() => assertPublicUrl("http://8.8.8.8/feed.ics"), BlockedUrlError);
});

Deno.test("assertPublicUrl rejects invalid URL", async () => {
  await assertRejects(() => assertPublicUrl("not a url"), BlockedUrlError);
});

Deno.test("assertPublicUrl rejects private / loopback IP literals", async () => {
  for (
    const u of [
      "https://127.0.0.1/x",
      "https://169.254.169.254/latest/meta-data/",
      "https://10.0.0.5/feed.ics",
      "https://192.168.0.1/",
      "https://[::1]/",
      "https://[fd00::1]/",
    ]
  ) {
    await assertRejects(() => assertPublicUrl(u), BlockedUrlError, "", `should block ${u}`);
  }
});

Deno.test("assertPublicUrl accepts a public IP literal", async () => {
  const url = await assertPublicUrl("https://8.8.8.8/feed.ics");
  assertEquals(url.hostname, "8.8.8.8");
});
