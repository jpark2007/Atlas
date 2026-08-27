import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseICS, parseICSDate, resolveTZID, extractCourse, matchProject, type Project } from "./ics.ts";

// The ICS parser + Canvas course-routing helpers moved out of canvas-sync (0040)
// so canvas-sync and feeds-sync parse identically. Pure functions — unit-tested
// here; the service-role upsert paths are left to the deploy-gate E2E.

Deno.test("parseICS: extracts VEVENTs with unfolded/escaped fields", () => {
  const ics = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "UID:event-assignment-123",
    "SUMMARY:Read chapter\\, then quiz [CS 101]",
    "DTSTART;VALUE=DATE:20260901",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:event-cal-456",
    "SUMMARY:Lecture",
    "DTSTART:20260902T140000Z",
    "DTEND:20260902T150000Z",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");

  const events = parseICS(ics);
  assertEquals(events.length, 2);
  assertEquals(events[0].uid, "event-assignment-123");
  assertEquals(events[0].summary, "Read chapter, then quiz [CS 101]");
  assertEquals(events[0].dtstart, { iso: "2026-09-01T00:00:00.000Z", allDay: true });
  assertEquals(events[1].dtstart, { iso: "2026-09-02T14:00:00.000Z", allDay: false });
  assertEquals(events[1].dtend, { iso: "2026-09-02T15:00:00.000Z", allDay: false });
});

Deno.test("parseICS: RFC 5545 line unfolding joins continuations", () => {
  const ics = [
    "BEGIN:VEVENT",
    "UID:u1",
    "SUMMARY:A very long ",
    " title that folded",
    "DTSTART:20260101T000000Z",
    "END:VEVENT",
  ].join("\r\n");
  const events = parseICS(ics);
  assertEquals(events[0].summary, "A very long title that folded");
});

// ── Timezones ────────────────────────────────────────────────────────────────
// Exchange-published registrar feeds write Windows zone names, which Intl rejects.
// Before the mapping the wall clock fell through and was read as UTC — 4-5 hours off,
// enough to roll the date.

/** One VEVENT with the given DTSTART line, plus optional VCALENDAR-scope lines. */
function feed(dtstart: string, calendarLines: string[] = []): string {
  return [
    "BEGIN:VCALENDAR",
    ...calendarLines,
    "BEGIN:VEVENT",
    "UID:u1",
    "SUMMARY:Lecture",
    dtstart,
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");
}

Deno.test("resolveTZID: Windows names map to IANA, IANA passes through", () => {
  assertEquals(resolveTZID("Eastern Standard Time"), "America/New_York");
  assertEquals(resolveTZID("(UTC-05:00) Eastern Time (US & Canada)"), "America/New_York");
  assertEquals(resolveTZID("(UTC-05:00) Eastern Time (US and Canada)"), "America/New_York");
  assertEquals(resolveTZID("Pacific Standard Time"), "America/Los_Angeles");
  assertEquals(resolveTZID("America/Chicago"), "America/Chicago");
  assertEquals(resolveTZID("Not A Zone At All"), "Not A Zone At All");
});

Deno.test("parseICSDate: a Windows TZID resolves to the right instant", () => {
  // Sept 1 is daylight time in New York (UTC-4): 09:00 local → 13:00Z.
  const events = parseICS(feed("DTSTART;TZID=Eastern Standard Time:20260901T090000"));
  assertEquals(events[0].dtstart, { iso: "2026-09-01T13:00:00.000Z", allDay: false });

  // Jan 15 is standard time (UTC-5): 09:00 local → 14:00Z. Same TZID, right offset.
  const winter = parseICS(feed("DTSTART;TZID=Eastern Standard Time:20260115T090000"));
  assertEquals(winter[0].dtstart, { iso: "2026-01-15T14:00:00.000Z", allDay: false });
});

Deno.test("parseICSDate: the Outlook display form resolves too", () => {
  // Quoted because the param value contains a comma-free but paren/space-laden name.
  const events = parseICS(feed('DTSTART;TZID="(UTC-05:00) Eastern Time (US & Canada)":20260115T090000'));
  assertEquals(events[0].dtstart, { iso: "2026-01-15T14:00:00.000Z", allDay: false });
});

Deno.test("parseICSDate: a Windows TZID near midnight no longer rolls the date", () => {
  // The bug that mattered: 21:00 Pacific read as UTC became the NEXT day.
  const events = parseICS(feed("DTSTART;TZID=Pacific Standard Time:20260115T210000"));
  assertEquals(events[0].dtstart, { iso: "2026-01-16T05:00:00.000Z", allDay: false });
});

Deno.test("parseICSDate: a floating time uses the calendar's declared zone", () => {
  // A floating 09:00 means 9am wall clock. X-WR-TIMEZONE is the only thing that tells
  // the server which wall — the same reading ICSFile.swift gives it on the client.
  const events = parseICS(feed("DTSTART:20260115T090000", ["X-WR-TIMEZONE:America/New_York"]));
  assertEquals(events[0].dtstart, { iso: "2026-01-15T14:00:00.000Z", allDay: false });

  // A Windows name in X-WR-TIMEZONE is mapped the same way a TZID is.
  const win = parseICS(feed("DTSTART:20260115T090000", ["X-WR-TIMEZONE:Eastern Standard Time"]));
  assertEquals(win[0].dtstart, { iso: "2026-01-15T14:00:00.000Z", allDay: false });
});

Deno.test("parseICSDate: a floating time with no declared zone stays UTC", () => {
  // The documented fallback: the server has no reader to be local to.
  const events = parseICS(feed("DTSTART:20260115T090000"));
  assertEquals(events[0].dtstart, { iso: "2026-01-15T09:00:00.000Z", allDay: false });
});

Deno.test("parseICSDate: an unknown TZID degrades instead of throwing", () => {
  const events = parseICS(feed("DTSTART;TZID=Middle Earth Standard Time:20260115T090000"));
  assertEquals(events[0].dtstart, { iso: "2026-01-15T09:00:00.000Z", allDay: false });

  // Directly, too — no throw, and an all-day value is untouched by any of this.
  assertEquals(parseICSDate("20260115T090000", new Map([["TZID", "Nowhere/Nothing"]])),
    { iso: "2026-01-15T09:00:00.000Z", allDay: false });
  assertEquals(parseICSDate("20260115", new Map([["VALUE", "DATE"], ["TZID", "Eastern Standard Time"]])),
    { iso: "2026-01-15T00:00:00.000Z", allDay: true });
});

Deno.test("extractCourse: splits trailing [COURSE] bracket", () => {
  assertEquals(extractCourse("Essay due [ENG 205]"), { title: "Essay due", code: "ENG 205" });
  assertEquals(extractCourse("No bracket here"), { title: "No bracket here", code: null });
});

Deno.test("matchProject: explicit link > code > exact name", () => {
  const projects: Project[] = [
    { id: "p1", space_name: "School", name: "Intro CS", code: "CS101", canvas_course: null },
    { id: "p2", space_name: "School", name: "English", code: "ENG205", canvas_course: "ENG 205 [linked]" },
  ];
  // primary: normalized code match
  assertEquals(matchProject("CS 101", projects)?.id, "p1");
  // secondary: exact (case-insensitive) name
  assertEquals(matchProject("english", projects)?.id, "p2");
  // explicit user link wins outright
  assertEquals(matchProject("ENG 205 [linked]", projects)?.id, "p2");
  // no match
  assertEquals(matchProject("BIO 300", projects), null);
  assertEquals(matchProject(null, projects), null);
});
