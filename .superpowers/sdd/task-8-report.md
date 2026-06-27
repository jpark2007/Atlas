# Task 8 Report — Metrics Module

## Status: COMPLETE

---

## TDD Evidence

### RED (test wrote first, before Metrics.swift)
```
error: cannot find 'AtlasMetrics' in scope   ×9 instances
** TEST FAILED **
```

### GREEN (after Metrics.swift)
```
Test Suite 'MetricsTests' passed at 2026-06-27 07:37:44.657
  testCompletionRate              passed
  testCompletionRate_noTasks      passed
  testEventCounts_todayAndThisWeek passed
  testFullScenario                passed
  testGoalAvgProgress             passed
  testGoalAvgProgress_noGoals     passed
  testNoteCount                   passed
  testPerSpaceLoad                passed
  testTaskCounts_openDoneScheduled passed
Test Suite 'All tests' passed
```

---

## What metrics are computed

| Field | How derived |
|---|---|
| `totalTasks` | `tasks.count` |
| `openTasks` | `tasks.filter { !$0.done }.count` |
| `doneTasks` | `tasks.filter { $0.done }.count` |
| `scheduledTasks` | `tasks.filter { $0.scheduledAt != nil }.count` |
| `eventsToday` | events where `Calendar.isDate(start, inSameDayAs: referenceDate)` |
| `eventsThisWeek` | events where `Calendar.dateInterval(of: .weekOfYear, for:).contains(start)` |
| `perSpace` | grouped by `spaceName`, tracking open/total; color from `spaces` list |
| `goalAvgProgress` | `mean(goals.map(\.progress))`, 0 if empty |
| `noteCount` | `notes.count` |
| `completionRate` | `doneTasks / max(1, totalTasks)` |

### Honestly omitted (with reason)

- **`completedToday` / `completedThisWeek`** — `TaskItem` has no `completedAt` timestamp; `done: Bool` only tells us *if* completed, not *when*. A `// TODO: richer time-bucketed metrics once tasks carry completedAt` comment is in `Metrics.swift`.
- **`focusMinutesToday`** — `FocusViewModel` is in-memory only (`completedWorkIntervals` on a non-persisted ObservableObject, not surfaced via `AppState`). Including a stale `0` would be misleading, so the field was omitted entirely.
- **Streak** — requires per-day completion timestamps; same blocker.

---

## Three Views

### MetricsCard (dashboard, 320 wide)
- "At a glance" header + "Details →" button → `state.presentMetrics = true`
- Stat row: open tasks | events today
- `MetricsCompletionBar` (gradient capsule, labeled %)
- Goal avg % (accent color when ≥ 70 %)
- The `.sheet(isPresented: $state.presentMetrics)` is wired here so the popup appears over the dashboard.

### MetricsPopupView (modal sheet, 440×520)
- Summary AtlasCard: open / done / notes + completion bar
- Calendar AtlasCard: events today + this week
- By Space AtlasCard: `MetricsSpaceLoadBars` — per-space colored capsule bars
- Goals AtlasCard: avg progress + completion bar
- "View full metrics page →" button (`state.route = .metrics`)

### MetricsView (full page, `.metrics` route)
- Page kicker "METRICS"
- At a glance card: 4-column stat grid (open / done / events today / notes) + completion bar
- By Space card: `MetricsSpaceLoadBars` (same shared view)
- Calendar card: events today + this week
- Goals card: avg % stat + goal bar

### Shared subviews (defined in MetricsView.swift, internal visibility)
- `MetricsStatCell` — number + label
- `MetricsCompletionBar` — labeled gradient capsule bar
- `MetricsSpaceLoadBars` — per-space colored bars with open/total label

---

## Palette Quick Actions (CommandPalette.swift)

Appended to `quickActions` after "Open Metrics":

| Action | id | Icon | Behavior |
|---|---|---|---|
| New Task | `new-task` | `plus.circle.fill` | `state.presentCapture = true` |
| New Note | `new-note` | `note.text.badge.plus` | `state.addNote(title:body:spaceName:isExternal:)` (discardable) |
| New Event | `new-event` | `calendar.badge.plus` | computes next round hour → sets `eventEditorSeed` + `state.route = .calendar` + `presentEventEditor = true` |

All 4 actions appear in the "Quick actions" group when query is empty; `activate()` dispatches via the existing `.action(let action) { action.run(); dismiss() }` branch.

---

## Build + Test Output

```
** BUILD SUCCEEDED **
Test Suite 'MetricsTests' passed (9/9 cases, 0 failures)
Test Suite 'All tests' passed
```

---

## Files Changed

| Path | Change |
|---|---|
| `Atlas/Data/Metrics.swift` | CREATED — `SpaceLoad`, `AtlasMetrics`, dual `compute` |
| `AtlasTests/MetricsTests.swift` | CREATED — 9 TDD tests |
| `Atlas/Views/Metrics/MetricsView.swift` | REPLACED — full page + shared subviews |
| `Atlas/Views/Metrics/MetricsCard.swift` | REPLACED — dashboard card |
| `Atlas/Views/Metrics/MetricsPopupView.swift` | REPLACED — popup sheet |
| `Atlas/Views/Search/CommandPalette.swift` | MODIFIED — 3 palette actions added |

---

## Concerns

1. **Sheet ownership**: `MetricsCard` owns `sheet(isPresented: $state.presentMetrics)`. If another view in the tree also installs a sheet on that binding there could be a conflict. Consider moving to `RootView`-level sheet in a future cleanup.
2. **`eventsThisWeek` includes today**: The field counts today's events *plus* other events this week. This is intentional and consistent (today is in this week), but the label should say "this week (incl. today)" if ever surfaced in copy.
3. **Per-space `id: UUID()`** is regenerated on every `compute` call. This is fine for rendering (stable within one SwiftUI pass) but means `perSpace` arrays are not `Equatable`/cacheable by id. Fine for now given compute is cheap.
