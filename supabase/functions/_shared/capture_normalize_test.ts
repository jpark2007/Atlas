/**
 * Tests for the capture local→UTC conversion and the deterministic repair pass.
 * Pure Intl/date math — no network — so `deno test` here stays green alongside
 * the other _shared tests.
 *
 * Reference facts these cases lean on (US DST 2026: Mar 8 → Nov 1):
 *   America/Los_Angeles = UTC-8 (PST) / UTC-7 (PDT)
 *   Asia/Tokyo          = UTC+9 year round (no DST)
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dateAnchorBlock,
  localToday,
  localToUtcISO,
  normalizeCaptureItems,
} from "./capture_normalize.ts";

const LA = "America/Los_Angeles";
const TOKYO = "Asia/Tokyo";

// ── localToUtcISO: UTC-behind zone ─────────────────────────────
Deno.test("localToUtcISO shifts an afternoon PDT wall clock onto the next UTC day", () => {
  assertEquals(localToUtcISO("2026-08-11T17:30", LA), "2026-08-12T00:30:00.000Z");
});

Deno.test("localToUtcISO keeps a morning PDT wall clock on the same UTC day", () => {
  assertEquals(localToUtcISO("2026-08-11T09:00", LA), "2026-08-11T16:00:00.000Z");
});

Deno.test("localToUtcISO uses PST (UTC-8) outside daylight time", () => {
  assertEquals(localToUtcISO("2026-01-15T17:30", LA), "2026-01-16T01:30:00.000Z");
});

// ── localToUtcISO: UTC-ahead zone ──────────────────────────────
Deno.test("localToUtcISO handles a UTC-ahead zone", () => {
  assertEquals(localToUtcISO("2026-08-11T17:30", TOKYO), "2026-08-11T08:30:00.000Z");
});

Deno.test("localToUtcISO rolls a Tokyo midnight BACK to the previous UTC day", () => {
  assertEquals(localToUtcISO("2026-08-11T00:00", TOKYO), "2026-08-10T15:00:00.000Z");
});

// ── localToUtcISO: DST boundaries ──────────────────────────────
Deno.test("localToUtcISO resolves both sides of the spring-forward transition", () => {
  // 2026-03-08 02:00 local: clocks jump 2 → 3. 01:30 is PST, 03:30 is PDT.
  assertEquals(localToUtcISO("2026-03-08T01:30", LA), "2026-03-08T09:30:00.000Z");
  assertEquals(localToUtcISO("2026-03-08T03:30", LA), "2026-03-08T10:30:00.000Z");
});

Deno.test("localToUtcISO resolves the fall-back day", () => {
  // 2026-11-01 02:00 local: clocks fall 2 → 1. 00:30 is unambiguously PDT.
  assertEquals(localToUtcISO("2026-11-01T00:30", LA), "2026-11-01T07:30:00.000Z");
  // Later that day is unambiguously PST.
  assertEquals(localToUtcISO("2026-11-01T15:00", LA), "2026-11-01T23:00:00.000Z");
});

// ── localToUtcISO: tolerant inputs ─────────────────────────────
Deno.test("localToUtcISO treats a date-only value as that local day's midnight", () => {
  assertEquals(localToUtcISO("2026-08-11", LA), "2026-08-11T07:00:00.000Z");
});

Deno.test("localToUtcISO passes an already-absolute instant through unshifted", () => {
  assertEquals(localToUtcISO("2026-08-12T00:30:00Z", LA), "2026-08-12T00:30:00.000Z");
  assertEquals(localToUtcISO("2026-08-11T17:30:00-07:00", LA), "2026-08-12T00:30:00.000Z");
});

Deno.test("localToUtcISO accepts a space separator and seconds", () => {
  assertEquals(localToUtcISO("2026-08-11 17:30:45", LA), "2026-08-12T00:30:45.000Z");
});

Deno.test("localToUtcISO returns null for junk and non-strings", () => {
  assertEquals(localToUtcISO("next friday", LA), null);
  assertEquals(localToUtcISO("", LA), null);
  assertEquals(localToUtcISO(undefined, LA), null);
  assertEquals(localToUtcISO(42, LA), null);
});

Deno.test("localToUtcISO falls back to UTC on a bad timezone instead of throwing", () => {
  assertEquals(localToUtcISO("2026-08-11T17:30", "Not/AZone"), "2026-08-11T17:30:00.000Z");
});

// ── localToday / dateAnchorBlock ───────────────────────────────
Deno.test("localToday reports the user's local date, not the UTC date", () => {
  // 2026-08-12T04:00Z is still Aug 11 in Los Angeles and already Aug 12 in Tokyo.
  const now = new Date("2026-08-12T04:00:00Z");
  assertEquals(localToday(now, LA), "2026-08-11");
  assertEquals(localToday(now, TOKYO), "2026-08-12");
});

Deno.test("dateAnchorBlock anchors today/tomorrow and names each weekday", () => {
  const block = dateAnchorBlock(new Date("2026-08-12T04:00:00Z"), LA, 3);
  assertEquals(block.split("\n").length, 3);
  assertEquals(block.includes("2026-08-11  Tuesday  (today)"), true);
  assertEquals(block.includes("2026-08-12  Wednesday  (tomorrow)"), true);
  assertEquals(block.includes("2026-08-13  Thursday"), true);
});

// ── normalizeCaptureItems: conversion ──────────────────────────
const opts = { timeZone: LA, spaceNames: ["School", "Personal", "Health"] };

Deno.test("normalizeCaptureItems converts a timed event's local start and end", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Study group", spaceName: "School",
    startISO: "2026-08-11T15:30", endISO: "2026-08-11T18:00",
  }], opts);
  assertEquals(it.startISO, "2026-08-11T22:30:00.000Z");
  assertEquals(it.endISO, "2026-08-12T01:00:00.000Z");
  assertEquals(it.isAllDay, undefined);
});

Deno.test("normalizeCaptureItems converts a task deadline", () => {
  const [it] = normalizeCaptureItems([{
    kind: "task", title: "Essay", spaceName: "School", dueISO: "2026-08-13T23:59",
  }], opts);
  assertEquals(it.dueISO, "2026-08-14T06:59:00.000Z");
});

Deno.test("normalizeCaptureItems preserves stated minutes exactly", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Pick up Sam", spaceName: "Personal",
    startISO: "2026-08-11T17:30",
  }], opts);
  assertEquals(it.startISO, "2026-08-12T00:30:00.000Z");
});

// ── normalizeCaptureItems: all-day + multi-day spans ───────────
Deno.test("normalizeCaptureItems puts an all-day event on local midnight", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Game", spaceName: "Personal",
    startISO: "2026-08-15", isAllDay: true,
  }], opts);
  assertEquals(it.isAllDay, true);
  assertEquals(it.startISO, "2026-08-15T07:00:00.000Z");
  assertEquals(it.endISO, undefined);
  assertEquals(it.durationMin, undefined);
});

Deno.test("normalizeCaptureItems keeps a multi-day all-day span's last day", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Conference", spaceName: "School",
    startISO: "2026-08-11", endISO: "2026-08-15", isAllDay: true,
  }], opts);
  assertEquals(it.isAllDay, true);
  assertEquals(it.startISO, "2026-08-11T07:00:00.000Z");
  assertEquals(it.endISO, "2026-08-15T07:00:00.000Z");
});

Deno.test("normalizeCaptureItems keeps a multi-WEEK all-day span", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Spring break", spaceName: "School",
    startISO: "2026-03-07", endISO: "2026-03-15", isAllDay: true,
  }], opts);
  // Span crosses the Mar 8 DST change: PST start, PDT end. Both are local midnight.
  assertEquals(it.startISO, "2026-03-07T08:00:00.000Z");
  assertEquals(it.endISO, "2026-03-15T07:00:00.000Z");
});

Deno.test("normalizeCaptureItems drops an all-day end that is not after the start", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Trip", spaceName: "Personal",
    startISO: "2026-08-15", endISO: "2026-08-15", isAllDay: true,
  }], opts);
  assertEquals(it.endISO, undefined);
});

Deno.test("normalizeCaptureItems treats a midnight event as all-day, not a 00:00 meeting", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Trip", spaceName: "Personal",
    startISO: "2026-08-15T00:00", durationMin: 60,
  }], opts);
  assertEquals(it.isAllDay, true);
  assertEquals(it.startISO, "2026-08-15T07:00:00.000Z");
  assertEquals(it.durationMin, undefined);
});

Deno.test("normalizeCaptureItems leaves a real overnight event timed", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "New Year party", spaceName: "Personal",
    startISO: "2026-12-31T22:00", endISO: "2027-01-01T01:00",
  }], opts);
  assertEquals(it.isAllDay, undefined);
  assertEquals(it.startISO, "2027-01-01T06:00:00.000Z");
  assertEquals(it.endISO, "2027-01-01T09:00:00.000Z");
});

Deno.test("normalizeCaptureItems does NOT all-day a midnight task deadline", () => {
  const [it] = normalizeCaptureItems([{
    kind: "task", title: "Pset", spaceName: "School", dueISO: "2026-08-14",
  }], opts);
  assertEquals(it.isAllDay, undefined);
  assertEquals(it.dueISO, "2026-08-14T07:00:00.000Z");
});

// ── normalizeCaptureItems: repairs ─────────────────────────────
Deno.test("normalizeCaptureItems drops an end at or before the start", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Meeting", spaceName: "Personal",
    startISO: "2026-08-11T15:00", endISO: "2026-08-11T14:00", durationMin: 30,
  }], opts);
  assertEquals(it.endISO, undefined);
  assertEquals(it.durationMin, 30);
});

Deno.test("normalizeCaptureItems drops an absurdly distant end", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Meeting", spaceName: "Personal",
    startISO: "2026-08-11T15:00", endISO: "2027-08-11T15:00",
  }], opts);
  assertEquals(it.endISO, undefined);
});

Deno.test("normalizeCaptureItems clamps a duration to one day and rejects nonsense", () => {
  const [a, b, c] = normalizeCaptureItems([
    { kind: "event", title: "A", spaceName: "Personal", startISO: "2026-08-11T09:00", durationMin: 99999 },
    { kind: "event", title: "B", spaceName: "Personal", startISO: "2026-08-11T09:00", durationMin: -5 },
    { kind: "event", title: "C", spaceName: "Personal", startISO: "2026-08-11T09:00", durationMin: "45" },
  ], opts);
  assertEquals(a.durationMin, 1440);
  assertEquals(b.durationMin, undefined);
  assertEquals(c.durationMin, 45);
});

Deno.test("normalizeCaptureItems forces an unknown kind to task", () => {
  const [it] = normalizeCaptureItems([{ kind: "reminder", title: "Wat", spaceName: "Personal" }], opts);
  assertEquals(it.kind, "task");
});

Deno.test("normalizeCaptureItems canonicalizes a space name's spelling", () => {
  const [a, b] = normalizeCaptureItems([
    { kind: "task", title: "A", spaceName: "school" },
    { kind: "task", title: "B", spaceName: "Fitness" },
  ], opts);
  assertEquals(a.spaceName, "School");
  assertEquals(b.spaceName, "Fitness"); // unknown → passed through for the client to resolve
});

Deno.test("normalizeCaptureItems drops items with no title and keeps only known keys", () => {
  const items = normalizeCaptureItems([
    { kind: "task", title: "   ", spaceName: "Personal" },
    { kind: "task", title: "Real", spaceName: "Personal", bogus: "x", confidence: 0.9 },
    null as unknown as Record<string, unknown>,
  ], opts);
  assertEquals(items.length, 1);
  assertEquals(Object.keys(items[0]).sort(), ["kind", "spaceName", "title"]);
});

Deno.test("normalizeCaptureItems mirrors a lone start onto a task's due date", () => {
  const [it] = normalizeCaptureItems([{
    kind: "task", title: "Essay", spaceName: "School", startISO: "2026-08-13T17:00",
  }], opts);
  assertEquals(it.dueISO, "2026-08-14T00:00:00.000Z");
  assertEquals(it.startISO, "2026-08-14T00:00:00.000Z");
});

Deno.test("normalizeCaptureItems mirrors a lone due onto an event's start", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Recital", spaceName: "Personal", dueISO: "2026-08-13T19:00",
  }], opts);
  assertEquals(it.startISO, "2026-08-14T02:00:00.000Z");
});

Deno.test("normalizeCaptureItems keeps project + notes and trims them", () => {
  const [it] = normalizeCaptureItems([{
    kind: "task", title: "  Read ch 4  ", spaceName: "School",
    projectName: " CS101 ", notes: " bring laptop ",
  }], opts);
  assertEquals(it.title, "Read ch 4");
  assertEquals(it.projectName, "CS101");
  assertEquals(it.notes, "bring laptop");
});

Deno.test("normalizeCaptureItems tolerates a model that emitted UTC anyway", () => {
  const [it] = normalizeCaptureItems([{
    kind: "event", title: "Legacy", spaceName: "Personal",
    startISO: "2026-08-12T00:30:00Z",
  }], opts);
  assertEquals(it.startISO, "2026-08-12T00:30:00.000Z");
  assertEquals(it.isAllDay, undefined);
});
