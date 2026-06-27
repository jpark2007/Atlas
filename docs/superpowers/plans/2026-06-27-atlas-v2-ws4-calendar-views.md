# WS-4 — Calendar Views (Month / List / Search / Filters / Window controls)

**Date:** 2026-06-27
**Branch:** feat/daily-driver-v1
**Spec:** docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md §4 WS-4

## Goal
Bring the calendar from Day/Week-only to a full Month/Week/Day/List set with in-calendar
search, a color/category filter row, and restored native macOS traffic-light window controls.

## Existing foundation (do NOT redo)
- `CalendarMode` enum (Day/Week) in `CalendarModels.swift`.
- `CalendarView.swift` — header, segmented mode picker, single-space filter menu, grid switch,
  `filteredEvents(on:)`, `scheduledTaskEvents(on:)`, Apple Calendar aggregation.
- `TimeGridView.swift` — `DayCalendarView`, `WeekGridView`, `EventTile`, `HourGutter`.
- `TaskGrouping` / `SlotFinder` — the pattern for pure, injected-`Calendar` testable modules.

## Tasks (commit per feature)

### 1. Month grid date math + MonthGridView
- New pure module `Atlas/Services/MonthGrid.swift`:
  - `cells(for date:, calendar:) -> [Date]` — 42 cells (6×7), first cell aligned to
    `calendar.firstWeekday` on/before the 1st of the visible month.
  - `isInMonth(_:of:calendar:) -> Bool`.
- Test `AtlasTests/MonthGridTests.swift`: 42 cells, first-cell weekday == firstWeekday,
  first cell ≤ 1st of month and within 6 days, all month days present, last cell == first+41.
- New `Atlas/Views/Calendar/MonthGridView.swift`: 6-week grid, up to 3 event chips/day +
  "+k" overflow, today highlight, dimmed out-of-month days; tap a day → Day view for it.

### 2. Agenda ordering + AgendaListView
- New pure module `Atlas/Services/AgendaBuilder.swift`:
  - `AgendaItem` (id, kind event/task, title, date, endDate?, allDay, color, spaceName).
  - `AgendaSection` (day, items).
  - `build(events:tasks:from:now:calendar:) -> [AgendaSection]` — upcoming from `from`'s
    day-start; sections day-ascending; within a day all-day first then time then title;
    excludes done tasks and past events.
- Test `AtlasTests/AgendaBuilderTests.swift`: day order, intra-day order, merge of events+tasks,
  done-task exclusion, past-event exclusion.
- New `Atlas/Views/Calendar/AgendaListView.swift`: grouped chronological list, day headers,
  tap event → openSource, tap task → Day view.

### 3. Wire Month + List into the mode toggle
- Add `.month`, `.list` to `CalendarMode`. Update CalendarView's `grid`, `titleLabel`,
  `shift(by:)`, and `loadAppleEventsIfNeeded()` switches. Widen the segmented picker.

### 4. In-calendar search
- `@State searchText`. A search field in the header. `filteredEvents`/agenda/month respect it.

### 5. Color/category filter row
- `@State hiddenSpaces: Set<String>`. A row of toggleable space-color chips alongside the
  existing single-space menu. Hidden spaces drop from every view.

### 6. Native window controls
- `WindowConfigurator.configure` explicitly un-hides the three standard window buttons
  (close/miniaturize/zoom) so the traffic lights always render, even with the transparent
  full-size-content titlebar + removed toolbar.

## Verification
`xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
Green tree required before hand-off.
