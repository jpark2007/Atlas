import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeSpaceName } from "./canvas_space.ts";

// normalizeSpaceName gates both the POST default and the PATCH space change. Pure:
// no network, no DB — the service-role update is left to the deploy-gate E2E.

Deno.test("normalizeSpaceName: trims a real name", () => {
  assertEquals(normalizeSpaceName("  School "), "School");
  assertEquals(normalizeSpaceName("Personal"), "Personal");
});

Deno.test("normalizeSpaceName: blank / whitespace / non-string → null", () => {
  assertEquals(normalizeSpaceName(""), null);
  assertEquals(normalizeSpaceName("   "), null);
  assertEquals(normalizeSpaceName(undefined), null);
  assertEquals(normalizeSpaceName(null), null);
  assertEquals(normalizeSpaceName(42), null);
});
