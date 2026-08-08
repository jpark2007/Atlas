/**
 * Pure helpers that turn the capture model's LOCAL wall-clock output into the
 * UTC-instant wire contract the clients already decode — plus the deterministic
 * repair pass over each item. Kept here (not in index.ts) so it's unit-testable
 * without importing index.ts, mirroring the other `_shared/*.ts` + `*_test.ts`
 * pairs.
 *
 * Why: the model used to be told to do the UTC arithmetic itself ("ADD the
 * user's offset", "let the calendar date roll forward"). A cheap model fails
 * that multi-step math often, and every failure lands the event on the wrong
 * day or hour. Now the model only reports the wall clock it read out of the
 * text ("2026-08-11T17:30") and THIS module does the timezone math with real
 * IANA/DST data via Intl.
 *
 * The wire format is unchanged: `dueISO` / `startISO` / `endISO` still leave the
 * function as full UTC instants, so already-shipped clients benefit with no update.
 */

/** "2026-08-11", "2026-08-11T17:30", "2026-08-11T17:30:00", "2026-08-11 17:30". */
const NAIVE_RE = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/;
/** Already an absolute instant: trailing "Z" or "+09:00" / "-0700". */
const ABSOLUTE_RE = /(Z|[+-]\d{2}:?\d{2})$/i;

const KINDS = new Set(["task", "event", "note"]);
/** A duration longer than a day is never a timed block — clamp it. */
const MAX_DURATION_MIN = 1440;
/** An end more than this far past the start is model garbage, not a long trip. */
const MAX_SPAN_MS = 31 * 24 * 60 * 60 * 1000;

/**
 * Offset (ms) to ADD to a UTC instant to get the wall clock in `timeZone`.
 * Derived by formatting the instant in the zone and reading it back as if it
 * were UTC — the standard Intl trick, correct across DST because it asks about
 * one specific instant.
 */
function tzOffsetMs(instantMs: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(new Date(instantMs));
  const p: Record<string, string> = {};
  for (const part of parts) p[part.type] = part.value;
  const asUTC = Date.UTC(
    Number(p.year), Number(p.month) - 1, Number(p.day),
    Number(p.hour) % 24, Number(p.minute), Number(p.second),
  );
  return asUTC - instantMs;
}

/**
 * Convert a timezone-naive local wall clock ("2026-08-11T17:30") in `timeZone`
 * to a UTC ISO instant. A value that is ALREADY absolute (ends in Z/offset) is
 * normalized but not shifted, so a model that ignores the instruction and emits
 * UTC still works. A date-only value means that local day's midnight.
 *
 * Returns null for anything unparseable. Two offset passes so a DST transition
 * between the naive guess and the true instant resolves correctly.
 */
export function localToUtcISO(value: unknown, timeZone: string): string | null {
  if (typeof value !== "string") return null;
  const s = value.trim();
  if (!s) return null;

  if (ABSOLUTE_RE.test(s)) {
    const t = Date.parse(s);
    return Number.isNaN(t) ? null : new Date(t).toISOString();
  }

  const m = NAIVE_RE.exec(s);
  if (!m) return null;
  const naive = Date.UTC(
    Number(m[1]), Number(m[2]) - 1, Number(m[3]),
    Number(m[4] ?? 0), Number(m[5] ?? 0), Number(m[6] ?? 0),
  );
  if (Number.isNaN(naive)) return null;

  try {
    let utc = naive - tzOffsetMs(naive, timeZone);
    utc = naive - tzOffsetMs(utc, timeZone);
    return new Date(utc).toISOString();
  } catch {
    // Bad IANA identifier — treat the wall clock as UTC rather than 500.
    return new Date(naive).toISOString();
  }
}

/** "YYYY-MM-DD" for `instantMs` as seen in `timeZone`. */
function formatLocalDate(instantMs: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(instantMs));
  const p: Record<string, string> = {};
  for (const part of parts) p[part.type] = part.value;
  return `${p.year}-${p.month}-${p.day}`;
}

/** The local calendar date of a naive OR absolute value, as "YYYY-MM-DD". */
function localDatePart(value: string, timeZone: string): string | null {
  const m = NAIVE_RE.exec(value.trim());
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const t = Date.parse(value);
  if (Number.isNaN(t)) return null;
  try {
    return formatLocalDate(t, timeZone);
  } catch {
    return formatLocalDate(t, "UTC");
  }
}

/** The local "HH:MM" of a naive OR absolute value, or null if date-only/unparseable. */
function localTimePart(value: string, timeZone: string): string | null {
  const m = NAIVE_RE.exec(value.trim());
  if (m) return m[4] === undefined ? null : `${m[4].padStart(2, "0")}:${m[5]}`;
  const t = Date.parse(value);
  if (Number.isNaN(t)) return null;
  try {
    return new Intl.DateTimeFormat("en-GB", {
      timeZone, hourCycle: "h23", hour: "2-digit", minute: "2-digit",
    }).format(new Date(t));
  } catch {
    return null;
  }
}

/**
 * The user's local date today, "YYYY-MM-DD". Exported for the prompt's
 * relative-date anchor and for the eval harness's fixed reference "now".
 */
export function localToday(now: Date, timeZone: string): string {
  try {
    return formatLocalDate(now.getTime(), timeZone);
  } catch {
    return formatLocalDate(now.getTime(), "UTC");
  }
}

/**
 * A compact table of the next `days` local dates with weekday names, so the
 * model never has to compute "next Friday" — it looks the date up. This is the
 * cheapest available fix for relative-date errors.
 */
export function dateAnchorBlock(now: Date, timeZone: string, days = 14): string {
  const today = localToday(now, timeZone);
  const [y, m, d] = today.split("-").map(Number);
  const base = Date.UTC(y, m - 1, d);
  const weekday = new Intl.DateTimeFormat("en-US", { timeZone: "UTC", weekday: "long" });
  const lines: string[] = [];
  for (let i = 0; i < days; i++) {
    const at = new Date(base + i * 86400000);
    const label = i === 0 ? "  (today)" : i === 1 ? "  (tomorrow)" : "";
    lines.push(`  ${at.toISOString().slice(0, 10)}  ${weekday.format(at)}${label}`);
  }
  return lines.join("\n");
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * Match `name` against the user's real space names case-insensitively and return
 * the EXACT canonical spelling. Unknown names pass through — the clients already
 * resolve fuzzily and fall back to a default space.
 */
function canonicalSpace(name: string, spaceNames: string[]): string {
  const lower = name.toLowerCase();
  return spaceNames.find((s) => s.toLowerCase() === lower) ?? name;
}

export type NormalizeOptions = { timeZone: string; spaceNames?: string[] };

/**
 * Convert + repair the model's raw items into the wire shape. Deterministic, so
 * these invariants hold no matter how the model misbehaves:
 *
 *  - only known keys survive; a blank title drops the item entirely
 *  - `kind` is always task|event|note (anything else → task)
 *  - `spaceName` uses the user's exact spelling when it matches one of theirs
 *  - `dueISO`/`startISO`/`endISO` are UTC instants converted from local time
 *  - an all-day item's start (and multi-day end) sit on local midnight, and the
 *    end is the LAST day of the span (clients treat it as inclusive)
 *  - an `event` whose start landed on local midnight is all-day, not a meeting
 *    at 00:00 — this is what a "stated time produced midnight" failure looks like
 *  - `endISO` is dropped unless it is after the start and within a sane span
 *  - `durationMin` is a positive integer ≤ one day, and absent on all-day items
 *  - a task carrying only a start, or an event carrying only a due, gets the
 *    other field filled in so neither client silently loses the date
 */
export function normalizeCaptureItems(
  items: Record<string, unknown>[],
  opts: NormalizeOptions,
): Record<string, unknown>[] {
  const tz = opts.timeZone;
  const spaceNames = opts.spaceNames ?? [];
  const out: Record<string, unknown>[] = [];

  for (const raw of items) {
    if (!raw || typeof raw !== "object") continue;
    const title = str(raw.title);
    if (!title) continue;

    const kindRaw = str(raw.kind).toLowerCase();
    const kind = KINDS.has(kindRaw) ? kindRaw : "task";

    const item: Record<string, unknown> = {
      kind,
      title,
      spaceName: canonicalSpace(str(raw.spaceName), spaceNames),
    };
    const project = str(raw.projectName);
    if (project) item.projectName = project;
    const notes = str(raw.notes);
    if (notes) item.notes = notes;

    // Fill the sibling date field before conversion so nothing is lost.
    let startLocal = str(raw.startISO);
    let dueLocal = str(raw.dueISO);
    const endLocal = str(raw.endISO);
    if (kind === "task" && !dueLocal && startLocal) dueLocal = startLocal;
    if (kind === "event" && !startLocal && dueLocal) startLocal = dueLocal;

    // All-day: explicitly flagged, or an event whose start has no clock time /
    // sits at local midnight with no real end time.
    const startTime = startLocal ? localTimePart(startLocal, tz) : null;
    const endTime = endLocal ? localTimePart(endLocal, tz) : null;
    let allDay = raw.isAllDay === true;
    if (
      kind === "event" && startLocal && !allDay &&
      (startTime === null || startTime === "00:00") &&
      (endTime === null || endTime === "00:00")
    ) {
      allDay = true;
    }

    if (allDay && startLocal) {
      const startDay = localDatePart(startLocal, tz);
      const endDay = endLocal ? localDatePart(endLocal, tz) : null;
      if (startDay) {
        item.isAllDay = true;
        item.startISO = localToUtcISO(`${startDay}T00:00`, tz);
        // A multi-day span keeps its LAST day; a same-day span drops the end.
        if (endDay && endDay > startDay) {
          item.endISO = localToUtcISO(`${endDay}T00:00`, tz);
        }
        if (kind === "task") item.dueISO = item.startISO;
      }
    } else {
      const start = startLocal ? localToUtcISO(startLocal, tz) : null;
      const due = dueLocal ? localToUtcISO(dueLocal, tz) : null;
      if (start) item.startISO = start;
      if (due) item.dueISO = due;

      const end = endLocal ? localToUtcISO(endLocal, tz) : null;
      if (start && end) {
        const span = Date.parse(end) - Date.parse(start);
        if (span > 0 && span <= MAX_SPAN_MS) item.endISO = end;
      }

      const dur = Math.round(Number(raw.durationMin));
      if (Number.isFinite(dur) && dur > 0) {
        item.durationMin = Math.min(dur, MAX_DURATION_MIN);
      }
    }

    out.push(item);
  }

  return out;
}
