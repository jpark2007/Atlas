# WS-3 — Scheduling (Atlas v2)

**Date:** 2026-06-27
**Branch:** `feat/daily-driver-v1`
**Builds on:** Foundation (WS-1) — `TaskItem.dueDate/durationMin`, `TaskItem.dueLabel(for:now:)`, `AppState.addTask(title:dueDate:durationMin:)`.

## Goal
Make scheduling smart and non-destructive: auto-find-a-slot, resurface-after-slot,
manual due-date editing, and a space-filtered unscheduled tray.

## Tasks

### 1. Auto-find-a-slot (testable pure logic)
- New `Atlas/Services/SlotFinder.swift` — `SlotFinder.firstFreeSlot(durationMin:on:busy:now:startHour:endHour:snapMinutes:)`.
  Scans `busy: [DateInterval]` for the first free gap >= duration, within
  visible hours, snapped up to 15 min, never before `now`. Pure → unit-tested
  with synthetic intervals.
- `AppState.busyIntervals(on:excludingTask:)` gathers busy time from
  `events(on:)` (timed only) + scheduled tasks (`scheduledAt` + `durationMin`,
  default 60) on that day.
- `AppState.suggestSlot(for:on:now:) -> Date?` = `firstFreeSlot` over `busyIntervals`.

### 2. UI — "Suggest time" per task
- `UnscheduledTray` gains `onSuggest: (UUID) -> Void`; context menu + a button.
- `CalendarView` wires it: `suggestSlot(for:on:now:)` → `state.schedule(taskId:at:)`.
- Manual drag unchanged.

### 3. Revert-after-slot (non-destructive)
- `TaskItem.isEffectivelyUnscheduled(now:)` — true when `scheduledAt == nil`,
  OR (`scheduledAt + durationMin*60 < now` AND `!done`).
- `AppState.unscheduledTasks` uses it (`&& !done` keeps done tasks out of the tray).
- `AppState.now` published, refreshed by a 60 s `Timer` (`startClock()`).
- `CalendarView.scheduledTaskEvents` excludes effectively-unscheduled tasks → they
  leave the grid and return to the tray as their slot passes.
- Unit-test `isEffectivelyUnscheduled` with injected now (past-unchecked => true;
  future => false; past-but-done => false).

### 4. Space-filter the tray
- `UnscheduledTray` takes `spaceFilter: String` ("All" or space name) and narrows
  its tasks internally; `CalendarView` passes its existing `spaceFilter`. Grid stays global.

### 5. Manual due-date picker
- `AppState.setDueDate(taskId:date:)` updates `dueDate` + `dueLabel` via
  `TaskItem.dueLabel(for:)`. Unit-tested.
- Tapping a tray chip opens a popover with a `DatePicker` bound to the due date
  (+ Clear). Manual drag still works.

## Verification
`xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
New test classes: `SlotFinderTests`, `TaskItemUnscheduledTests`, `AppStateScheduleTests`.
Commit per feature. Leave the tree green.
