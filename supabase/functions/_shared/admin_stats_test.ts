import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  activesSeries,
  dailyCounts,
  dayWindow,
  isValidCode,
  platformBreakdown,
  sha256Hex,
  signupSeries,
  snapshotRow,
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

// ── time-series shaping ──

Deno.test("dayWindow returns N ascending UTC day-keys ending today", () => {
  assertEquals(dayWindow("2026-07-17", 3), [
    "2026-07-15",
    "2026-07-16",
    "2026-07-17",
  ]);
  const w = dayWindow("2026-01-01", 2); // crosses year boundary
  assertEquals(w, ["2025-12-31", "2026-01-01"]);
});

Deno.test("dailyCounts zero-fills the window and buckets by UTC day", () => {
  const out = dailyCounts(
    [
      "2026-07-16T09:00:00Z",
      "2026-07-16T23:59:00Z", // same UTC day → 2
      "2026-07-17T00:30:00Z",
      "2026-05-01T00:00:00Z", // outside 3-day window → dropped
    ],
    "2026-07-17",
    3,
  );
  assertEquals(out, [
    { day: "2026-07-15", n: 0 },
    { day: "2026-07-16", n: 2 },
    { day: "2026-07-17", n: 1 },
  ]);
});

Deno.test("signupSeries: cumulative anchors its last point to totalUsers", () => {
  // 10 users total; 3 signed up in the 3-day window, 7 before it.
  const { points, priorTotal } = signupSeries(
    [
      { day: "2026-07-16", n: 2 },
      { day: "2026-07-17", n: 1 },
      { day: "2026-01-01", n: 4 }, // outside window → folded into baseline
    ],
    10,
    "2026-07-17",
    3,
  );
  assertEquals(priorTotal, 7); // 10 - (2 + 1)
  assertEquals(points, [
    { day: "2026-07-15", n: 0, cumulative: 7 },
    { day: "2026-07-16", n: 2, cumulative: 9 },
    { day: "2026-07-17", n: 1, cumulative: 10 }, // == totalUsers
  ]);
});

Deno.test("signupSeries: empty history stays flat at zero", () => {
  const { points, priorTotal } = signupSeries([], 0, "2026-07-17", 2);
  assertEquals(priorTotal, 0);
  assertEquals(points, [
    { day: "2026-07-16", n: 0, cumulative: 0 },
    { day: "2026-07-17", n: 0, cumulative: 0 },
  ]);
});

Deno.test("snapshotRow mirrors the metric_snapshots column shape", () => {
  assertEquals(snapshotRow("2026-07-17", 12, 30, 5, 3), {
    day: "2026-07-17",
    total_users: 12,
    dmg_downloads: 30,
    mac_active_30d: 5,
    ios_active_30d: 3,
  });
});

Deno.test("activesSeries merges today over stored snapshots, sorted, sparse", () => {
  const out = activesSeries(
    [
      { day: "2026-07-15", mac_active_30d: 2, ios_active_30d: 1 },
      { day: "2026-07-17", mac_active_30d: 4, ios_active_30d: 2 }, // stale today
    ],
    { day: "2026-07-17", mac: 5, ios: 3 }, // fresh today wins
  );
  assertEquals(out, [
    { day: "2026-07-15", mac: 2, ios: 1 },
    { day: "2026-07-17", mac: 5, ios: 3 },
  ]);
});
