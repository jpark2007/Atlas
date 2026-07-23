/**
 * Pure helpers for the `capture` function's long-paste fan-out. Kept here (not in
 * index.ts) so they're unit-testable without importing index.ts — which would run
 * its top-level `Deno.serve`. Mirrors the other `_shared/*.ts` + `*_test.ts` pairs.
 *
 * A normal capture is a single model call. A long paste (up to the function's
 * MAX_TEXT_LEN) is split at newline boundaries into ~CHUNK_SIZE pieces parsed in
 * parallel; each later chunk carries a read-only tail of the preceding text so a
 * date / "all times PM" established early still resolves, without re-emitting
 * boundary events.
 */

// Text at or below this length takes the single-call fast path.
export const SINGLE_CALL_LIMIT = 6000;
// Target size per chunk; worst case ~4 chunks given a 20k MAX_TEXT_LEN.
export const CHUNK_SIZE = 6000;
// How much of the preceding text to replay as read-only context per later chunk.
export const CONTEXT_TAIL = 1500;

/**
 * Split capture text for parallel parsing. Text at or below SINGLE_CALL_LIMIT is
 * one chunk. Longer text is broken at NEWLINE boundaries into ~CHUNK_SIZE pieces,
 * never mid-line, so a paragraph/session stays intact.
 */
export function chunkText(text: string): string[] {
  if (text.length <= SINGLE_CALL_LIMIT) return [text];
  const chunks: string[] = [];
  let current = "";
  for (const line of text.split("\n")) {
    if (current.length > 0 && current.length + line.length + 1 > CHUNK_SIZE) {
      chunks.push(current);
      current = "";
    }
    current = current.length > 0 ? `${current}\n${line}` : line;
  }
  if (current.length > 0) chunks.push(current);
  return chunks;
}

/**
 * User content for chunk `i`. Chunk 0 is sent verbatim. Every later chunk is
 * prefixed with a READ-ONLY tail of the preceding text so an early-established
 * date / am-pm default still resolves, with an explicit instruction NOT to emit
 * items for that context (prevents double-emitting boundary events).
 */
export function userContentForChunk(chunks: string[], i: number): string {
  if (i === 0) return chunks[0];
  const context = chunks.slice(0, i).join("\n").slice(-CONTEXT_TAIL);
  return `PRECEDING CONTEXT (for resolving dates, am/pm, and defaults ONLY — do NOT \
emit items for anything in this section): ${context}\n\nTEXT TO PARSE:\n${chunks[i]}`;
}

/**
 * Drop dated events a chunk boundary caused two calls to emit — keyed on
 * (title, startISO). Items without a startISO (tasks/notes) pass through untouched
 * so distinct to-dos are never collapsed.
 */
export function dedupeItems(
  items: Record<string, unknown>[],
): Record<string, unknown>[] {
  const seen = new Set<string>();
  return items.filter((it) => {
    const start = typeof it.startISO === "string" ? it.startISO : "";
    if (!start) return true;
    const key = `${typeof it.title === "string" ? it.title : ""} ${start}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
