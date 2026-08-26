import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { applyCaps, base64ByteLength, normalizeClasses } from "./syllabus_scan.ts";

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

Deno.test("normalizeClasses keeps a dateless item and drops a titleless one", () => {
  const out = normalizeClasses({
    classes: [{ name: "Art", items: [{ title: "Reading week 3" }, { kind: "task" }] }],
  });
  assertEquals(out, [{ name: "Art", items: [{ kind: "task", title: "Reading week 3" }] }]);
});

Deno.test("normalizeClasses omits absent optionals and drops junk blocks", () => {
  const out = normalizeClasses({
    classes: [{
      name: "Math",
      meetingPattern: [{ weekdays: [3], start: "09:00" }, { weekdays: [0, 3, 99], start: "1", end: "2" }],
      classInfo: {},
      items: [],
    }],
  });
  assertEquals(out, [{
    name: "Math",
    meetingPattern: [{ weekdays: [3], start: "1", end: "2" }],
    items: [],
  }]);
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
    [{ kind: "task", title: "PS1", dueISO: "2026-09-16T03:59:00.000Z" }],
  );
});

Deno.test("a winter due date with no stated time is 23:59 EST (UTC-5)", () => {
  assertEquals(
    scanDates([{ kind: "task", title: "Final paper", dueISO: "2026-12-11" }], "America/New_York"),
    [{ kind: "task", title: "Final paper", dueISO: "2026-12-12T04:59:00.000Z" }],
  );
});

Deno.test("an EVENT with a date and no time still starts at local midnight", () => {
  assertEquals(
    scanDates([{ kind: "event", title: "Midterm", startISO: "2026-09-15" }], "America/New_York"),
    [{ kind: "event", title: "Midterm", startISO: "2026-09-15T04:00:00.000Z" }],
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
