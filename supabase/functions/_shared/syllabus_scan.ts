/**
 * Atlas — syllabus-scan pure helpers (Deno).
 *
 * The size accounting and output shaping the `syllabus-scan` function performs
 * around its (paid, network) model call, split out so they're unit-testable
 * without a request. The function itself owns auth, rate limiting, prompt, and
 * the OpenRouter call.
 */

// Defensive output bounds only — a real syllabus is one class with tens of items.
export const MAX_CLASSES = 20;
export const MAX_ITEMS = 200;

/** Byte length of a base64 payload, without allocating the decoded bytes. */
export function base64ByteLength(b64: string): number {
  const clean = b64.replace(/\s/g, "");
  if (!clean.length) return 0;
  const padding = clean.endsWith("==") ? 2 : clean.endsWith("=") ? 1 : 0;
  return Math.floor((clean.length * 3) / 4) - padding;
}

/**
 * Coerce the model's class list into the exact response contract, so the client
 * decodes ONE stable shape no matter how the model phrased its JSON. Anything
 * unusable (a block missing times, an item missing a title) is dropped rather
 * than passed through as a half-item the review list can't render.
 */
export function normalizeClasses(parsed: unknown): Record<string, unknown>[] {
  const raw = Array.isArray(parsed)
    ? parsed
    : (parsed && typeof parsed === "object" &&
        Array.isArray((parsed as Record<string, unknown>).classes))
    ? (parsed as { classes: unknown[] }).classes
    : [];

  const str = (v: unknown): string | undefined =>
    typeof v === "string" && v.trim().length ? v.trim() : undefined;
  const strArray = (v: unknown): string[] =>
    Array.isArray(v) ? v.map(str).filter((s): s is string => !!s) : [];

  const out: Record<string, unknown>[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const c = entry as Record<string, unknown>;
    const cls: Record<string, unknown> = {};

    const code = str(c.code);
    const name = str(c.name);
    if (code) cls.code = code;
    if (name) cls.name = name;

    // Meeting blocks: both times required, weekdays clamped to 1…7.
    const blocks = (Array.isArray(c.meetingPattern) ? c.meetingPattern : [])
      .map((b) => {
        if (!b || typeof b !== "object") return null;
        const mb = b as Record<string, unknown>;
        const start = str(mb.start);
        const end = str(mb.end);
        if (!start || !end) return null;
        const weekdays = (Array.isArray(mb.weekdays) ? mb.weekdays : [])
          .filter((d): d is number => typeof d === "number" && d >= 1 && d <= 7);
        const block: Record<string, unknown> = { weekdays, start, end };
        const location = str(mb.location);
        if (location) block.location = location;
        return block;
      })
      .filter((b): b is Record<string, unknown> => b !== null);
    if (blocks.length) cls.meetingPattern = blocks;

    // Class info card: only emitted when it actually carries something.
    const info = (c.classInfo && typeof c.classInfo === "object")
      ? c.classInfo as Record<string, unknown>
      : {};
    const gradeWeights = strArray(info.grade_weights ?? info.gradeWeights);
    const policies = strArray(info.policies);
    const officeHours = str(info.office_hours ?? info.officeHours);
    if (gradeWeights.length || policies.length || officeHours) {
      const card: Record<string, unknown> = { grade_weights: gradeWeights, policies };
      if (officeHours) card.office_hours = officeHours;
      cls.classInfo = card;
    }

    // Items: a title is mandatory; kind defaults to "task".
    cls.items = (Array.isArray(c.items) ? c.items : [])
      .map((i) => {
        if (!i || typeof i !== "object") return null;
        const it = i as Record<string, unknown>;
        const title = str(it.title);
        if (!title) return null;
        const item: Record<string, unknown> = {
          kind: it.kind === "event" ? "event" : "task",
          title,
        };
        const dueISO = str(it.dueISO);
        const startISO = str(it.startISO);
        const notes = str(it.notes);
        if (dueISO) item.dueISO = dueISO;
        if (startISO) item.startISO = startISO;
        if (notes) item.notes = notes;
        return item;
      })
      .filter((i): i is Record<string, unknown> => i !== null);

    // A class with no identity AND no content is noise.
    if (
      !code && !name && !blocks.length && !cls.classInfo &&
      (cls.items as unknown[]).length === 0
    ) continue;
    out.push(cls);
  }
  return out;
}

/** Apply the defensive output bounds. Returns the trimmed list + whether it trimmed. */
export function applyCaps(
  classes: Record<string, unknown>[],
): { classes: Record<string, unknown>[]; truncated: boolean } {
  let truncated = classes.length > MAX_CLASSES;
  const kept = classes.slice(0, MAX_CLASSES);
  let budget = MAX_ITEMS;
  for (const cls of kept) {
    const items = (cls.items as unknown[]) ?? [];
    if (items.length > budget) {
      cls.items = items.slice(0, Math.max(budget, 0));
      truncated = true;
    }
    budget -= (cls.items as unknown[]).length;
  }
  return { classes: kept, truncated };
}
