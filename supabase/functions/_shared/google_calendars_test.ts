import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { diffSelection, parseCalendarList } from "./google_calendars.ts";

Deno.test("parseCalendarList: maps id/summary/primary, drops id-less + deleted", () => {
  const entries = parseCalendarList({
    items: [
      { id: "primary", summary: "me@school.edu", primary: true },
      { id: "class@group.calendar.google.com", summary: "COS 226" },
      { id: "renamed@group", summary: "raw", summaryOverride: "My Name" },
      { summary: "no id — dropped" },
      { id: "gone@group", summary: "trashed", deleted: true },
    ],
  });
  assertEquals(entries, [
    { calendarId: "primary", summary: "me@school.edu", isPrimary: true },
    { calendarId: "class@group.calendar.google.com", summary: "COS 226", isPrimary: false },
    { calendarId: "renamed@group", summary: "My Name", isPrimary: false },
  ]);
});

Deno.test("parseCalendarList: falls back to id when no summary; handles empty", () => {
  assertEquals(parseCalendarList({ items: [{ id: "abc" }] }), [
    { calendarId: "abc", summary: "abc", isPrimary: false },
  ]);
  assertEquals(parseCalendarList({}), []);
  assertEquals(parseCalendarList(null), []);
});

Deno.test("diffSelection: reports only the changed ids", () => {
  const d = diffSelection(["primary", "a"], ["primary", "b", "c"]);
  assertEquals(d.toSelect.sort(), ["b", "c"]);
  assertEquals(d.toDeselect, ["a"]);
});

Deno.test("diffSelection: no change → empty diffs", () => {
  const d = diffSelection(["primary"], ["primary"]);
  assertEquals(d.toSelect, []);
  assertEquals(d.toDeselect, []);
});
