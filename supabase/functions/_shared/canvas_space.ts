/**
 * canvas-connect destination-space normalization. Pure (no network / DB) so it's
 * unit-testable the way `google_pull`'s `isChanged` is. Returns the trimmed space
 * name that routes unmatched Canvas feed items, or null when the input isn't a
 * non-empty string. POST treats null as the 'School' default; PATCH rejects it
 * (400) — a space change with no space is a no-op.
 */
export function normalizeSpaceName(input: unknown): string | null {
  return typeof input === "string" && input.trim() ? input.trim() : null;
}
