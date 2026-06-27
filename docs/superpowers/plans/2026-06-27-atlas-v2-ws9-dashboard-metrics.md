# WS-9 — Dashboard + Metrics (plan)

**Date:** 2026-06-27 · Branch `feat/daily-driver-v1`

Spec ref: `docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md` §4 WS-9.

## Goals
1. Move the all-tasks list out of the 320px right rail into a full-width section
   **below** "Today's schedule," grouped by due-date buckets with an optional
   space filter.
2. Remove the Metrics sidebar nav row; surface Metrics via the existing
   `presentMetrics` popup (⌘K quick-action already exists + add a small entry
   near profile/settings). Keep `MetricsView` reachable via the popup's
   "View full metrics page".
3. Replace linear metric bars with Swift Charts donut/ring visualizations across
   MetricsView, MetricsCard, MetricsPopupView. Keep underlying metrics data.

## Tasks

### 1. TaskGrouping (pure, TDD)
- New `Atlas/Data/TaskGrouping.swift`:
  `enum TaskGrouping { static func byDueBucket(tasks:now:calendar:) -> [(title: String, tasks: [TaskItem])] }`
- Buckets in fixed order, only non-empty included:
  **Overdue / Today / This week / Later / No date**.
  - No date: `dueDate == nil`.
  - Compare `dueDate` day vs `now` day: earlier → Overdue, same → Today.
  - Future: within current `weekOfYear` interval → This week, else → Later.
- Within a bucket: sort by `dueDate` ascending (nil last), then title.
- Unit test `AtlasTests/TaskGroupingTests.swift` with injected `now` + fixed
  UTC Monday-first calendar (mirror MetricsTests harness). Assert titles, order,
  membership, empty-bucket omission, all-undated case.

### 2. Dashboard restructure
- `DashboardView`: keep header + HStack(ScheduleCard | rail). Remove `TasksCard`
  from rail (and delete the now-dead `TasksCard` struct). Add a new full-width
  `DashboardTasksSection` below the HStack.
- `DashboardTasksSection`: header ("Tasks" + count + space-filter Menu), an
  "Add a task" affordance (opens `presentCapture`), then grouped rows via
  `TaskGrouping.byDueBucket`. Space filter is `@State String?` (nil = all).

### 3. Sidebar / routing
- Remove `navRow(... route: .metrics ...)`.
- Add a small "Metrics" button in the bottom profile/settings area →
  `state.presentMetrics = true`.
- Keep `Route.metrics` + RootView `.metrics` case (popup "View full metrics page"
  still routes there). ⌘K already has an "Open Metrics" quick action.

### 4. Donut charts (Swift Charts)
- `import Charts` (macOS 14 ok; SectorMark available).
- New shared views in MetricsView.swift:
  - `MetricsCompletionDonut(rate:label:size:)` — ring with center % text.
  - `MetricsSpaceDonut(loads:size:)` — per-space sectors sized by `totalCount`,
    colored by space color, with a custom legend (open/total).
- Replace every `MetricsCompletionBar` with `MetricsCompletionDonut` and every
  `MetricsSpaceLoadBars` with `MetricsSpaceDonut` in MetricsView, MetricsCard,
  MetricsPopupView. Delete the old linear structs (no other refs).

## Verify
- `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
- New TaskGroupingTests pass; existing suites stay green; build (UI wiring) succeeds.
</content>
