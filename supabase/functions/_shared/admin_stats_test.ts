import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isValidCode,
  platformBreakdown,
  sha256Hex,
  timingSafeEqual,
} from "./admin_stats.ts";

Deno.test("platformBreakdown counts distinct users per platform", () => {
  const out = platformBreakdown([
    { user_id: "a", platform: "macos" },
    { user_id: "a", platform: "macos" }, // dup user → counted once
    { user_id: "b", platform: "macos" },
    { user_id: "a", platform: "ios" }, // same user, other platform → separate bucket
    { user_id: "c", platform: "ios" },
  ]);
  assertEquals(out.mac, 2);
  assertEquals(out.mobile, 2);
  assertEquals(out.byPlatform, { macos: 2, ios: 2 });
});

Deno.test("platformBreakdown ignores blank rows and is case-insensitive", () => {
  const out = platformBreakdown([
    { user_id: "", platform: "macos" },
    { user_id: "a", platform: "" },
    { user_id: "b", platform: "MacOS" },
  ]);
  assertEquals(out.mac, 1);
  assertEquals(out.mobile, 0);
});

Deno.test("platformBreakdown empty input", () => {
  const out = platformBreakdown([]);
  assertEquals(out, { mac: 0, mobile: 0, byPlatform: {} });
});

Deno.test("timingSafeEqual matches only identical strings", () => {
  assertEquals(timingSafeEqual("123456", "123456"), true);
  assertEquals(timingSafeEqual("123456", "123457"), false);
  assertEquals(timingSafeEqual("123456", "12345"), false);
  assertEquals(timingSafeEqual("", ""), true);
});

Deno.test("sha256Hex matches the migration's seeded hash of 2026", async () => {
  assertEquals(
    await sha256Hex("2026"),
    "158a323a7ba44870f23d96f1516dd70aa48e9a72db4ebb026b0a89e212a208ab",
  );
});

Deno.test("isValidCode accepts 4–8 digits only", () => {
  assertEquals(isValidCode("2026"), true);
  assertEquals(isValidCode("12345678"), true);
  assertEquals(isValidCode("123"), false); // too short
  assertEquals(isValidCode("123456789"), false); // too long
  assertEquals(isValidCode("12a4"), false); // non-digit
  assertEquals(isValidCode(""), false);
});
