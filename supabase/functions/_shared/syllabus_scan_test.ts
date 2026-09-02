import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyCaps,
  base64ByteLength,
  isGradeWeightSummaryRow,
  MAX_MEETING_BLOCKS,
  MAX_POLICIES,
  normalizeClasses,
} from "./syllabus_scan.ts";

// The model call is network + money; these cover the pure shaping around it —
// how a raw model payload becomes the response contract, and the caps.

Deno.test("base64ByteLength matches the decoded size", () => {
  assertEquals(base64ByteLength(""), 0);
  assertEquals(base64ByteLength(btoa("a")), 1);
  assertEquals(base64ByteLength(btoa("ab")), 2);
  assertEquals(base64ByteLength(btoa("abc")), 3);
  assertEquals(base64ByteLength(btoa("x".repeat(1000))), 1000);
  // Line-wrapped base64 (some encoders wrap at 76 cols) still measures right.
  const wrapped = btoa("y".repeat(300)).replace(/(.{40})/g, "$1\n");
  assertEquals(base64ByteLength(wrapped), 300);
});

Deno.test("normalizeClasses shapes a full class", () => {
  const out = normalizeClasses({
    classes: [{
      code: " BIO 201 ",
      name: "Cell Biology",
      meetingPattern: [{ weekdays: [2, 4, 6], start: "10:00", end: "10:50", location: "Tech 204" }],
      classInfo: {
        grade_weights: ["Exams 40%", "  "],
        policies: ["No late work"],
        office_hours: "Tue 2-4pm",
      },
      items: [
        { kind: "task", title: "Essay 1", dueISO: "2026-09-12T00:00", notes: "5 pages" },
        { kind: "event", title: "Midterm", startISO: "2026-10-01T10:00" },
      ],
    }],
  }, "America/New_York");
  assertEquals(out, [{
    code: "BIO 201",
    name: "Cell Biology",
    meetingPattern: [{ weekdays: [2, 4, 6], start: "10:00", end: "10:50", location: "Tech 204" }],
    classInfo: { grade_weights: ["Exams 40%"], policies: ["No late work"], office_hours: "Tue 2-4pm" },
    items: [
      { kind: "task", title: "Essay 1", dueISO: "2026-09-13T03:59:00.000Z", notes: "5 pages" },
      { kind: "event", title: "Midterm", startISO: "2026-10-01T14:00:00.000Z" },
    ],
  }]);
});

Deno.test("normalizeClasses drops the syllabus's own grading summary row", () => {
  // The grading table's last line ("TOTAL: 100%") is not a weight. Stored, it renders
  // as a bogus row and the card's total helper adds it in — that's the 200% total.
  const out = normalizeClasses({
    classes: [{
      name: "Chem 101",
      classInfo: {
        grade_weights: [
          "Homework 30%",
          "Exams 70%",
          "TOTAL: 100%",
          "Sum — 100%",
          "Total 100%",
        ],
      },
    }],
  });
  assertEquals(out, [{
    name: "Chem 101",
    classInfo: { grade_weights: ["Homework 30%", "Exams 70%"], policies: [] },
    items: [],
  }]);
});

// Same cases as AtlasCore's ClassInfoFormatTests (testCaseAndWhitespaceVariantsOfSummaryRowAreExcluded,
// testRowWithNoPercentIsNotCountedAndNotASummaryRow) — keep the two lists in step.
Deno.test("isGradeWeightSummaryRow matches case/whitespace variants and rejects a real weight", () => {
  assertEquals(isGradeWeightSummaryRow("TOTAL: 100%"), true);
  assertEquals(isGradeWeightSummaryRow("  total  100%"), true);
  assertEquals(isGradeWeightSummaryRow("Sum: 100%"), true);
  assertEquals(isGradeWeightSummaryRow("SUM 100%"), true);
  assertEquals(isGradeWeightSummaryRow("Midterms 30%"), false);
  assertEquals(isGradeWeightSummaryRow("Participation (see syllabus)"), false);
});

Deno.test("normalizeClasses keeps a dateless item and drops a titleless one", () => {
  const out = normalizeClasses({
    classes: [{ name: "Art", items: [{ title: "Reading week 3" }, { kind: "task" }] }],
  });
  assertEquals(out, [{ name: "Art", items: [{ kind: "task", title: "Reading week 3" }] }]);
});

Deno.test("normalizeClasses omits absent optionals and drops junk blocks", () => {
  // A block with no end time is unusable; a block with weekdays outside 1…7 means the
  // model used some other numbering, so ITS DAYS ARE ALL SUSPECT — the block goes, and
  // the caller is told. (Silently keeping the in-range days is what turned Tuesday
  // recitations into Monday lectures.)
  const warnings: string[] = [];
  const out = normalizeClasses({
    classes: [{
      name: "Math",
      meetingPattern: [{ weekdays: [3], start: "09:00" }, { weekdays: [0, 3, 99], start: "1", end: "2" }],
      classInfo: {},
      items: [],
    }],
  }, "UTC", warnings);
  assertEquals(out, [{ name: "Math", items: [] }]);
  assertEquals(warnings.length, 1);
  assertStringIncludes(warnings[0], "Math");
  assertStringIncludes(warnings[0], "[0,99]");
});

Deno.test("an ISO-numbered Sunday (0) drops the block rather than shifting the week", () => {
  const warnings: string[] = [];
  const out = normalizeClasses({
    classes: [{
      name: "Chem",
      meetingPattern: [
        { weekdays: [0], start: "10:00", end: "10:50" },
        { weekdays: [2.5], start: "11:00", end: "11:50" },
        { weekdays: ["3"], start: "12:00", end: "12:50" },
      ],
      items: [],
    }],
  }, "UTC", warnings);
  assertEquals(out, [{ name: "Chem", items: [] }]);
  assertEquals(warnings.length, 3);
});

Deno.test("normalizeClasses keeps sectionLabel and a known kind, drops an unknown one", () => {
  const out = normalizeClasses({
    classes: [{
      name: "Calc I",
      meetingPattern: [
        { weekdays: [2, 4], start: "14:00", end: "15:20", location: "PH-115",
          sectionLabel: " Sec. 37–39 ", kind: "Lecture" },
        { weekdays: [3], start: "14:00", end: "15:20", location: "SEC-217",
          sectionLabel: "Section 37", kind: "seminar" },
      ],
      items: [],
    }],
  });
  assertEquals(out, [{
    name: "Calc I",
    meetingPattern: [
      { weekdays: [2, 4], start: "14:00", end: "15:20", location: "PH-115",
        sectionLabel: "Sec. 37–39", kind: "lecture" },
      { weekdays: [3], start: "14:00", end: "15:20", location: "SEC-217",
        sectionLabel: "Section 37" },
    ],
    items: [],
  }]);
});

Deno.test("byte-identical meeting blocks collapse into one", () => {
  const out = normalizeClasses({
    classes: [{
      name: "Physics",
      meetingPattern: [
        { weekdays: [2, 4], start: "09:00", end: "09:50", location: "PH-115" },
        { weekdays: [2, 4], start: "09:00", end: "09:50", location: "PH-115" },
        // Same days and times, DIFFERENT room — a real second row, kept.
        { weekdays: [2, 4], start: "09:00", end: "09:50", location: "PH-116" },
      ],
      items: [],
    }],
  });
  assertEquals((out[0].meetingPattern as unknown[]).length, 2);
});

// The failure this whole guard exists for (handoff C1): a Tuesday recitation row and
// an MW lecture row are DIFFERENT rows. Neither may be merged into the other, and
// Tuesday must still be Tuesday (Foundation 3) on the way out.
Deno.test("recitation blocks on [3] survive intact beside the [2,4] lecture", () => {
  const warnings: string[] = [];
  const out = normalizeClasses({
    classes: [{
      code: "MATH 135",
      meetingPattern: [
        { weekdays: [2, 4], start: "14:00", end: "15:20", location: "PH-115",
          sectionLabel: "Sec. 37–39", kind: "lecture" },
        { weekdays: [3], start: "14:00", end: "15:20", location: "SEC-217",
          sectionLabel: "Section 37", kind: "recitation" },
        { weekdays: [3], start: "15:50", end: "17:10", location: "SEC-217",
          sectionLabel: "Section 38", kind: "recitation" },
        { weekdays: [3], start: "17:40", end: "19:00", location: "SEC-217",
          sectionLabel: "Section 39", kind: "recitation" },
      ],
      items: [],
    }],
  }, "America/New_York", warnings);
  assertEquals(warnings, []);
  const blocks = out[0].meetingPattern as Record<string, unknown>[];
  assertEquals(blocks.length, 4);
  assertEquals(blocks.map((b) => b.weekdays), [[2, 4], [3], [3], [3]]);
  assertEquals(blocks.map((b) => b.start), ["14:00", "14:00", "15:50", "17:40"]);
  assertEquals(blocks.map((b) => b.sectionLabel),
    ["Sec. 37–39", "Section 37", "Section 38", "Section 39"]);
});

Deno.test("normalizeClasses tolerates sparse and malformed payloads", () => {
  assertEquals(normalizeClasses({}), []);
  assertEquals(normalizeClasses(null), []);
  assertEquals(normalizeClasses({ classes: "nope" }), []);
  assertEquals(normalizeClasses({ classes: [null, 7, {}] }), []);
  // A bare array (no `classes` wrapper) is accepted.
  assertEquals(normalizeClasses([{ code: "CS 1" }]), [{ code: "CS 1", items: [] }]);
});

Deno.test("applyCaps passes a normal result through untouched", () => {
  const classes = [{ name: "A", items: [{ title: "x" }] }];
  const out = applyCaps(classes);
  assertEquals(out.truncated, false);
  assertEquals(out.classes.length, 1);
  assertEquals((out.classes[0].items as unknown[]).length, 1);
});

Deno.test("applyCaps trims past the class and item budgets", () => {
  const many = Array.from({ length: 25 }, (_, i) => ({ name: `C${i}`, items: [] }));
  const capped = applyCaps(many);
  assertEquals(capped.classes.length, 20);
  assertEquals(capped.truncated, true);

  const heavy = [
    { name: "A", items: Array.from({ length: 150 }, (_, i) => ({ title: `t${i}` })) },
    { name: "B", items: Array.from({ length: 150 }, (_, i) => ({ title: `u${i}` })) },
  ];
  const out = applyCaps(heavy);
  assertEquals(out.truncated, true);
  assertEquals((out.classes[0].items as unknown[]).length, 150);
  assertEquals((out.classes[1].items as unknown[]).length, 50);
});

Deno.test("applyCaps trims meeting blocks past the per-class cap and says so", () => {
  const blocks = Array.from({ length: 12 }, (_, i) => ({
    weekdays: [3], start: `${9 + i}:00`, end: `${9 + i}:50`,
  }));
  const warnings: string[] = [];
  const out = applyCaps([{ code: "MATH 135", meetingPattern: blocks, items: [] }], warnings);
  assertEquals((out.classes[0].meetingPattern as unknown[]).length, MAX_MEETING_BLOCKS);
  assertEquals(out.truncated, true);
  assertEquals(warnings.length, 1);
  assertStringIncludes(warnings[0], "MATH 135");
});

Deno.test("applyCaps trims a flood of policies and says so", () => {
  // The live PSY 101 scan stored 28 policies — pages of prose captured near-verbatim.
  const policies = Array.from({ length: 28 }, (_, i) => `Policy ${i}: some rule.`);
  const warnings: string[] = [];
  const out = applyCaps(
    [{ code: "PSY 101", classInfo: { grade_weights: [], policies }, items: [] }],
    warnings,
  );
  const kept = (out.classes[0].classInfo as Record<string, unknown>).policies as string[];
  assertEquals(kept.length, MAX_POLICIES);
  assertEquals(kept[0], "Policy 0: some rule.");
  assertEquals(out.truncated, true);
  assertEquals(warnings.length, 1);
  assertStringIncludes(warnings[0], "PSY 101");
  assertStringIncludes(warnings[0], "28 policies");
});

Deno.test("an obedient policy list passes through untouched", () => {
  const policies = Array.from({ length: 8 }, (_, i) => `Heading ${i}: the rule.`);
  const warnings: string[] = [];
  const out = applyCaps(
    [{ name: "Intro", classInfo: { grade_weights: [], policies }, items: [] }],
    warnings,
  );
  assertEquals(
    ((out.classes[0].classInfo as Record<string, unknown>).policies as string[]).length,
    8,
  );
  assertEquals(out.truncated, false);
  assertEquals(warnings.length, 0);
});

Deno.test("a class with no classInfo card is left alone by the policy cap", () => {
  const out = applyCaps([{ name: "Schedule only", items: [] }]);
  assertEquals(out.truncated, false);
  assertEquals(out.classes[0].classInfo, undefined);
});

// ── Local wall clock → UTC instant ────────────────────────────────────────────
// The model reports the time the syllabus prints; the conversion happens here.
// A model that did the arithmetic itself kept landing dates 24h early.

/** The item dates of a one-class payload, for compactness below. */
function scanDates(
  items: Record<string, unknown>[],
  timeZone: string,
): Record<string, unknown>[] {
  const out = normalizeClasses({ classes: [{ name: "BIO 201", items }] }, timeZone);
  return (out[0].items as Record<string, unknown>[]);
}

Deno.test("summer dates convert at the DST offset (America/New_York is UTC-4)", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Essay 1", dueISO: "2026-09-12T23:59" }], "America/New_York"),
    [{ kind: "task", title: "Essay 1", dueISO: "2026-09-13T03:59:00.000Z" }],
  );
});

Deno.test("winter dates convert at the standard offset (America/New_York is UTC-5)", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Final paper", dueISO: "2026-12-10T23:59" }], "America/New_York"),
    [{ kind: "task", title: "Final paper", dueISO: "2026-12-11T04:59:00.000Z" }],
  );
});

Deno.test("a stated clock time survives and lands on the stated day", () => {
  const [item] = scanDates(
    [{ kind: "event", title: "Midterm", startISO: "2026-10-08T13:00" }],
    "America/New_York",
  );
  assertEquals(item.startISO, "2026-10-08T17:00:00.000Z");
  // Read back in the student's zone: same day, same clock time — not midnight,
  // not the 7th.
  const local = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/New_York",
    hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit",
  }).format(new Date(item.startISO as string));
  assertEquals(local, "2026-10-08, 13:00");
});

Deno.test("a due date with no stated time is the END of that LOCAL day", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "PS1", dueISO: "2026-09-15" }], "America/New_York"),
    // No stated time = END of that local day (Sept 15, 11:59 PM EDT), not midnight.
    // `dateOnly` carries the fact that no hour was printed, which the instant loses.
    [{ kind: "task", title: "PS1", dueISO: "2026-09-16T03:59:00.000Z", dateOnly: true }],
  );
});

Deno.test("a winter due date with no stated time is 23:59 EST (UTC-5)", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Final paper", dueISO: "2026-12-11" }], "America/New_York"),
    [{ kind: "task", title: "Final paper", dueISO: "2026-12-12T04:59:00.000Z", dateOnly: true }],
  );
});

Deno.test("an EVENT with a date and no time still starts at local midnight", () => {
  assertEquals(
    scanDates([{ kind: "event", title: "Midterm", startISO: "2026-09-15" }], "America/New_York"),
    // Local midnight + `dateOnly`, which is what the client turns into an ALL-DAY event
    // instead of a quiz that reads "12 AM · 1h".
    [{ kind: "event", title: "Midterm", startISO: "2026-09-15T04:00:00.000Z", dateOnly: true }],
  );
});

Deno.test("an absolute value from a disobedient model is never double-converted", () => {
  assertEquals(
    scanDates([{ kind: "event", title: "Lab", startISO: "2026-10-01T14:00:00Z" }], "America/New_York"),
    [{ kind: "event", title: "Lab", startISO: "2026-10-01T14:00:00.000Z" }],
  );
});

Deno.test("an unresolvable date is dropped but the item is kept", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Reading", dueISO: "Week 3" }], "America/New_York"),
    [{ kind: "task", title: "Reading" }],
  );
});

Deno.test("the default timezone (UTC) shifts nothing", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Quiz", dueISO: "2026-09-12T23:59" }], "UTC"),
    [{ kind: "task", title: "Quiz", dueISO: "2026-09-12T23:59:00.000Z" }],
  );
});

// ── Schedule documents ────────────────────────────────────────────────────────
// The weekly-module table a professor posts apart from the syllabus goes through the
// same lane. The PROMPT does the reading (which rows are work, which day a week-range
// row lands on); what is testable here is that the shaping carries its two extra facts
// — "no hour was printed" and "this date was inferred from a range" — and that a
// schedule with no grading text produces no class_info card.

Deno.test("a week-range row keeps its approximate flag and stays date-only", () => {
  assertEquals(
    scanDates([{
      kind: "task",
      title: "DBQ Module 5",
      dueISO: "2026-10-02",
      notes: "Week 5 · Sept 28-Oct 2",
      dateApproximate: true,
    }], "America/New_York"),
    [{
      kind: "task",
      title: "DBQ Module 5",
      // Last day of the range, at the end of that local day.
      dueISO: "2026-10-03T03:59:00.000Z",
      notes: "Week 5 · Sept 28-Oct 2",
      dateOnly: true,
      dateApproximate: true,
    }],
  );
});

Deno.test("an exactly-dated exam is never flagged approximate", () => {
  assertEquals(
    scanDates([{ kind: "event", title: "Midterm 1", startISO: "2026-10-09" }], "America/New_York"),
    [{ kind: "event", title: "Midterm 1", startISO: "2026-10-09T04:00:00.000Z", dateOnly: true }],
  );
});

Deno.test("an exam that printed a time keeps it, and is neither date-only nor approximate", () => {
  assertEquals(
    scanDates([{ kind: "event", title: "Midterm 3", startISO: "2026-12-15T16:00" }],
              "America/New_York"),
    [{ kind: "event", title: "Midterm 3", startISO: "2026-12-15T21:00:00.000Z" }],
  );
});

Deno.test("the approximate flag needs a date to hang on", () => {
  // A row whose range couldn't be grounded is kept, dateless — and "approximately
  // nothing" is not a fact worth shipping.
  assertEquals(
    scanDates([{ kind: "task", title: "DBQ Module 9", dueISO: "Week 9", dateApproximate: true }],
              "America/New_York"),
    [{ kind: "task", title: "DBQ Module 9" }],
  );
});

Deno.test("a schedule document with no grading text gets no class_info card", () => {
  const out = normalizeClasses({
    classes: [{
      name: "General Psychology",
      // What a schedule doc actually returns: rows and nothing else. An empty card
      // from a model trying to fill the shape must not become a card.
      classInfo: { grade_weights: [], policies: [], office_hours: "" },
      meetingPattern: [],
      items: [
        { kind: "task", title: "DBQ Module 3", dueISO: "2026-09-18", dateApproximate: true },
        { kind: "event", title: "Midterm 1", startISO: "2026-10-09" },
      ],
    }],
  }, "America/New_York");
  assertEquals(out.length, 1);
  assertEquals("classInfo" in out[0], false);
  assertEquals("meetingPattern" in out[0], false);
  assertEquals((out[0].items as unknown[]).length, 2);
});
