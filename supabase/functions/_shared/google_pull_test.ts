import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { InvalidGrantError, isChanged } from "./google_pull.ts";

// isChanged is the pull's recency gate (the notes analogue of the calendar C2
// storm guard). Pure: no network, no DB. Network code (mintAccessToken /
// pullDocNoteReference) is left to the E2E — mocking fetch/supabase here would
// test the mocks, not the pull.

Deno.test("isChanged: never-baselined always pulls", () => {
  // ref.modified_time null ⇒ storedMs = -Infinity (not finite) ⇒ pull regardless.
  assertEquals(isChanged(1_000, -Infinity), true);
  assertEquals(isChanged(NaN, -Infinity), true); // even with no Drive modifiedTime
});

Deno.test("isChanged: strictly-newer Drive pulls", () => {
  assertEquals(isChanged(2_000, 1_000), true);
});

Deno.test("isChanged: equal or older Drive is a no-op", () => {
  assertEquals(isChanged(1_000, 1_000), false); // equal (post-writeback re-baseline)
  assertEquals(isChanged(500, 1_000), false); // older
});

Deno.test("isChanged: NaN Drive time with an existing baseline does not pull", () => {
  // A Doc with no modifiedTime but a stored baseline must not re-pull every tick.
  assertEquals(isChanged(NaN, 1_000), false);
});

Deno.test("InvalidGrantError is a throwable Error subclass (revoked-connection branch)", () => {
  const e = new InvalidGrantError("invalid_grant");
  assertEquals(e instanceof InvalidGrantError, true);
  assertEquals(e instanceof Error, true);
  assertEquals(e.message, "invalid_grant");
});
