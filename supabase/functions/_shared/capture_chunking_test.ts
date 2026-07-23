/**
 * Tests for the capture long-paste fan-out helpers. Pure string logic — no
 * network — so `deno test` here stays green alongside the other _shared tests.
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chunkText,
  CHUNK_SIZE,
  dedupeItems,
  SINGLE_CALL_LIMIT,
  userContentForChunk,
} from "./capture_chunking.ts";

// ── chunkText: fast path ───────────────────────────────────────
Deno.test("chunkText returns a single chunk for normal input", () => {
  const text = "essay due thursday, gym 3x, dinner sunday";
  assertEquals(chunkText(text), [text]);
});

Deno.test("chunkText keeps input at the limit as one chunk", () => {
  const text = "x".repeat(SINGLE_CALL_LIMIT);
  assertEquals(chunkText(text).length, 1);
});

// ── chunkText: splitting ───────────────────────────────────────
Deno.test("chunkText splits long text at newline boundaries, never mid-line", () => {
  // Lines just under half CHUNK_SIZE so two fit per chunk; enough to exceed one chunk.
  const line = "a".repeat(CHUNK_SIZE / 2 - 10);
  const lines = Array.from({ length: 6 }, () => line);
  const text = lines.join("\n");
  const chunks = chunkText(text);
  // Every chunk under the size budget, and each line survives intact.
  for (const c of chunks) {
    if (c.length > CHUNK_SIZE) throw new Error("chunk exceeded CHUNK_SIZE");
  }
  // Reassembling the chunks reproduces the original text exactly (no loss/dupe).
  assertEquals(chunks.join("\n"), text);
});

// ── userContentForChunk: context preamble ──────────────────────
Deno.test("userContentForChunk sends chunk 0 verbatim", () => {
  const chunks = ["first", "second"];
  assertEquals(userContentForChunk(chunks, 0), "first");
});

Deno.test("userContentForChunk prefixes later chunks with read-only preceding context", () => {
  const chunks = ["all times are PM. mon 3:30", "tue 4, wed 5"];
  const out = userContentForChunk(chunks, 1);
  // Carries the instruction not to emit for the context, and the actual chunk.
  if (!out.includes("do NOT")) throw new Error("missing no-emit instruction");
  if (!out.includes("TEXT TO PARSE:")) throw new Error("missing parse marker");
  if (!out.includes("tue 4, wed 5")) throw new Error("missing chunk body");
  if (!out.includes("PM")) throw new Error("missing preceding context");
});

// ── dedupeItems: boundary events ───────────────────────────────
Deno.test("dedupeItems drops a dated event two chunks emitted twice", () => {
  const items = [
    { kind: "event", title: "Practice", startISO: "2026-07-05T00:00:00Z" },
    { kind: "event", title: "Practice", startISO: "2026-07-05T00:00:00Z" },
  ];
  assertEquals(dedupeItems(items).length, 1);
});

Deno.test("dedupeItems keeps same-title events at different times", () => {
  const items = [
    { kind: "event", title: "Practice", startISO: "2026-07-05T00:00:00Z" },
    { kind: "event", title: "Practice", startISO: "2026-07-06T00:00:00Z" },
  ];
  assertEquals(dedupeItems(items).length, 2);
});

Deno.test("dedupeItems never collapses tasks/notes (no startISO)", () => {
  const items = [
    { kind: "task", title: "Read" },
    { kind: "task", title: "Read" },
  ];
  assertEquals(dedupeItems(items).length, 2);
});
