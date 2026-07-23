import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseICS, extractCourse, matchProject, type Project } from "./ics.ts";

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
