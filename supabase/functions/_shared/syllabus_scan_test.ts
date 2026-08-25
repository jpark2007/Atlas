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
        { kind: "task", title: "Essay 1", dueISO: "2026-09-12T04:00:00Z", notes: "5 pages" },
        { kind: "event", title: "Midterm", startISO: "2026-10-01T14:00:00Z" },
      ],
    }],
  });
  assertEquals(out, [{
    code: "BIO 201",
    name: "Cell Biology",
    meetingPattern: [{ weekdays: [2, 4, 6], start: "10:00", end: "10:50", location: "Tech 204" }],
    classInfo: { grade_weights: ["Exams 40%"], policies: ["No late work"], office_hours: "Tue 2-4pm" },
    items: [
      { kind: "task", title: "Essay 1", dueISO: "2026-09-12T04:00:00Z", notes: "5 pages" },
      { kind: "event", title: "Midterm", startISO: "2026-10-01T14:00:00Z" },
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
