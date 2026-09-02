/**
 * Atlas — syllabus-scan pure helpers (Deno).
 *
 * The size accounting and output shaping the `syllabus-scan` function performs
 * around its (paid, network) model call, split out so they're unit-testable
 * without a request. The function itself owns auth, rate limiting, prompt, and
 * the OpenRouter call.
 */

import { deadlineToUtcISO, localToUtcISO } from "./capture_normalize.ts";

// Defensive output bounds only — a real syllabus is one class with tens of items.
export const MAX_CLASSES = 20;
export const MAX_ITEMS = 200;
// A lecture plus every recitation/lab section of one course still fits in 8; more
// than that is a parse gone wrong, not a timetable.
export const MAX_MEETING_BLOCKS = 8;
// The prompt asks for at most 8 distilled policies. A model that ignores it returns
// pages of near-verbatim prose (one live scan stored 28), which buries the rules that
// actually affect a grade. 12 leaves the obedient answer untouched and still stops a
// flood.
export const MAX_POLICIES = 12;

/** The meeting kinds the prompt asks for; anything else is dropped as noise. */
const MEETING_KINDS = new Set(["lecture", "recitation", "lab", "other"]);

/**
 * A syllabus's own summary row in the grading table ("Total: 100%", "Sum — 100%").
 * It isn't a weight: stored alongside the real rows it renders as a bogus line and
 * doubles the card's computed total, so it's dropped before it's ever stored.
 * Matches `ClassInfoFormat.isSummaryRow` in
 * `AtlasCore/Sources/AtlasCore/ClassInfoFormat.swift` (same "total"/"sum" prefix
 * rule) — keep the two in step. Covered together with `isGradeWeightSummaryRow
 * matches case/whitespace variants and rejects a real weight` in
 * `syllabus_scan_test.ts` and `ClassInfoFormatTests.testCaseAndWhitespaceVariantsOfSummaryRowAreExcluded`
 * in `AtlasCore/Tests/AtlasCoreTests/ClassInfoFormatTests.swift`.
 */
export function isGradeWeightSummaryRow(line: string): boolean {
  const label = line
    .trim()
    .replace(/[\d.,\s]*%$/, "")            // trailing "100%"
    .replace(/^[\s\-–—:·]+|[\s\-–—:·]+$/g, "")
    .toLowerCase();
  return label.startsWith("total") || label.startsWith("sum");
}

/**
 * Whether the model wrote a bare calendar day ("2026-09-24") rather than an instant.
 * The response converts every date to a UTC instant, so this is the only place the
 * fact that no clock time was stated can be captured before it's lost.
 */
function isBareDay(value: unknown): boolean {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim());
}

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
 *
 * The model reports item dates as LOCAL wall clock in `timeZone` ("2026-09-12T23:59");
 * a due date with no stated time resolves to the end of that local day (23:59);
 * `localToUtcISO` does the timezone/DST arithmetic here, in code, and the wire
 * contract stays what it always was — a full UTC instant. A model that ignores
 * the instruction and emits an absolute value passes through unshifted, never
 * double-converted. An unparseable date is dropped, keeping the item: the review
 * list lets the user fill it in, and a wrong date is worse than none.
 *
 * `warnings`, when passed, collects the things a caller should be told about
 * rather than left to discover in their calendar — chiefly a meeting block whose
 * weekdays aren't the numbering the prompt asked for, which historically was
 * clamped in silence and turned Tuesday recitations into Monday lectures.
 */
export function normalizeClasses(
  parsed: unknown,
  timeZone = "UTC",
  warnings?: string[],
): Record<string, unknown>[] {
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

    // Meeting blocks: both times required. A weekday outside 1…7 means the model
    // answered in some other numbering (ISO Mon=1…Sun=7 is the usual slip), so the
    // WHOLE block is untrustworthy — dropping it loudly beats silently keeping a
    // block whose days are shifted by one.
    const label = code ?? name ?? "an unidentified class";
    const blocks = (Array.isArray(c.meetingPattern) ? c.meetingPattern : [])
      .map((b) => {
        if (!b || typeof b !== "object") return null;
        const mb = b as Record<string, unknown>;
        const start = str(mb.start);
        const end = str(mb.end);
        if (!start || !end) return null;
        const rawDays = Array.isArray(mb.weekdays) ? mb.weekdays : [];
        const bad = rawDays.filter((d) =>
          typeof d !== "number" || !Number.isInteger(d) || d < 1 || d > 7
        );
        if (bad.length) {
          warnings?.push(
            `Dropped a meeting block for ${label}: weekday ${
              JSON.stringify(bad)
            } is outside 1 (Sunday)…7 (Saturday), so the whole block's days are unreliable.`,
          );
          return null;
        }
        const block: Record<string, unknown> = { weekdays: rawDays as number[], start, end };
        const location = str(mb.location);
        if (location) block.location = location;
        const sectionLabel = str(mb.sectionLabel);
        if (sectionLabel) block.sectionLabel = sectionLabel;
        const kind = str(mb.kind)?.toLowerCase();
        if (kind && MEETING_KINDS.has(kind)) block.kind = kind;
        return block;
      })
      .filter((b): b is Record<string, unknown> => b !== null);
    // Two rows that agree on days, times and room are one meeting stated twice.
    const seen = new Set<string>();
    const unique = blocks.filter((b) => {
      const key = JSON.stringify([b.weekdays, b.start, b.end, b.location ?? null]);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    if (unique.length) cls.meetingPattern = unique;

    // Class info card: only emitted when it actually carries something.
    const info = (c.classInfo && typeof c.classInfo === "object")
      ? c.classInfo as Record<string, unknown>
      : {};
    const gradeWeights = strArray(info.grade_weights ?? info.gradeWeights)
      .filter((line) => !isGradeWeightSummaryRow(line));
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
        // A due date with no stated time is the END of that local day, not its
        // midnight (see `deadlineToUtcISO`); a start time is taken literally.
        const dueISO = deadlineToUtcISO(str(it.dueISO), timeZone);
        const startISO = localToUtcISO(str(it.startISO), timeZone);
        const notes = str(it.notes);
        if (dueISO) item.dueISO = dueISO;
        if (startISO) item.startISO = startISO;
        if (notes) item.notes = notes;
        // The wire carries instants, so "the syllabus named a DAY, not an hour" can only
        // survive as its own flag — and it has to, because a dateless exam commits as an
        // ALL-DAY event rather than inventing midnight and an hour of length.
        if ((dueISO || startISO) && isBareDay(it.dueISO ?? it.startISO)) item.dateOnly = true;
        // A schedule doc's week rows ("Sept 28-Oct 2") are dated at the end of the range:
        // a real deadline, but one the student should see is inferred. Only meaningful
        // on a row that actually got a date.
        if ((dueISO || startISO) && it.dateApproximate === true) item.dateApproximate = true;
        return item;
      })
      .filter((i): i is Record<string, unknown> => i !== null);

    // A class with no identity AND no content is noise.
    if (
      !code && !name && !unique.length && !cls.classInfo &&
      (cls.items as unknown[]).length === 0
    ) continue;
    out.push(cls);
  }
  return out;
}

/**
 * Apply the defensive output bounds. Returns the trimmed list + whether it trimmed,
 * pushing any cap it actually hit into `warnings` so the user is told rather than
 * quietly handed a short list.
 */
export function applyCaps(
  classes: Record<string, unknown>[],
  warnings?: string[],
): { classes: Record<string, unknown>[]; truncated: boolean } {
  let truncated = classes.length > MAX_CLASSES;
  const kept = classes.slice(0, MAX_CLASSES);
  let budget = MAX_ITEMS;
  for (const cls of kept) {
    const blocks = cls.meetingPattern as unknown[] | undefined;
    if (blocks && blocks.length > MAX_MEETING_BLOCKS) {
      warnings?.push(
        `${cls.code ?? cls.name ?? "An unidentified class"} returned ${blocks.length} meeting blocks; kept the first ${MAX_MEETING_BLOCKS}.`,
      );
      cls.meetingPattern = blocks.slice(0, MAX_MEETING_BLOCKS);
      truncated = true;
    }
    const info = cls.classInfo as Record<string, unknown> | undefined;
    const policies = info?.policies as unknown[] | undefined;
    if (policies && policies.length > MAX_POLICIES) {
      warnings?.push(
        `${cls.code ?? cls.name ?? "An unidentified class"} returned ${policies.length} policies; kept the first ${MAX_POLICIES}.`,
      );
      info!.policies = policies.slice(0, MAX_POLICIES);
      truncated = true;
    }
    const items = (cls.items as unknown[]) ?? [];
    if (items.length > budget) {
      cls.items = items.slice(0, Math.max(budget, 0));
      truncated = true;
    }
    budget -= (cls.items as unknown[]).length;
  }
  return { classes: kept, truncated };
}
