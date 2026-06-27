# Task 0 Report — Foundation

## Status
DONE

## Build + Test Summary
- `xcodegen generate` — SUCCESS
- `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED
- `xcodebuild ... test CODE_SIGNING_ALLOWED=NO` — Test Suite `SmokeTests` PASSED (1 test, 0.002s)

## Files Changed

### Modified
| File | Change |
|------|--------|
| `Atlas/App/RootView.swift` | Added `case metrics` to `Route` enum; added `case .metrics: MetricsView()` to detail switch; added `.sheet(isPresented: $state.presentMetrics) { MetricsPopupView() }`; added `// TODO Task 9` comment for CalendarSyncSheet |
| `Atlas/Data/AppState.swift` | Added `@Published var presentMetrics = false` and `@Published var presentCalendarSync = false`; added `addEvent(_:)`, `updateEvent(_:)`, `deleteEvent(id:)`, `addGoal(_:)`, `updateGoal(_:)` in-memory CRUD methods |
| `Atlas/Config/SupabaseConfig.swift` | Added `static var functionsBase` and `static var restBase` computed URLs |
| `Atlas/Views/Sidebar/SidebarView.swift` | Added `navRow(title: "Metrics", icon: "chart.bar.fill", route: .metrics, trailing: nil)` after Focus row |
| `Atlas/Views/Dashboard/DashboardView.swift` | Added `MetricsCard()` to right-column VStack |
| `Atlas/Views/Search/CommandPalette.swift` | Added `PaletteAction` struct; added `.action(PaletteAction)` case to `CommandResult`; added `quickActions` (Open Metrics); replaced empty-query hint with "Quick actions" group; updated `flat`, `activate()`, `icon()`, `primary()`, `secondary()` to handle `.action` |
| `project.yml` | Added `AtlasTests` unit-test target and `schemes:` section wiring Atlas + AtlasTests |

### Created
| File | Description |
|------|-------------|
| `Atlas/Views/Metrics/MetricsView.swift` | Placeholder full-page view (AtlasCard stub) |
| `Atlas/Views/Metrics/MetricsPopupView.swift` | Placeholder popup sheet (AtlasCard stub) |
| `Atlas/Views/Metrics/MetricsCard.swift` | Placeholder dashboard card (AtlasCard stub) |
| `AtlasTests/AtlasTests.swift` | `SmokeTests.testItRuns()` — `XCTAssertTrue(true)` |

## Self-Review

### Issues Encountered
1. **Unicode curly quotes in CommandPalette.swift**: The original file had smart/curly double-quote characters (`"` U+201C / `"` U+201D) used as display characters inside the `hint("No matches for "\(query)".")` string, and also as string _delimiters_ in the `group(...)` calls (a pre-existing encoding artifact). After my Edit-tool insertions added more curly-quote delimiters, the build failed with "unicode curly quote found" errors. Fixed via Python script to replace all U+201C/U+201D with ASCII `"`, then restored the display-quote intent on the hint line by using Swift escaped quotes `\"`.

### Correctness
- All 5 CRUD methods are pure in-memory array mutations as required (no DB code).
- `PaletteAction.run` is a closure that fires on `.action` selection in `activate()` then calls `dismiss()`.
- `quickActions` is a computed property (not `let`) so it captures `state` lazily — safe since `CommandPaletteOverlay` has `@EnvironmentObject private var state`.
- `// TODO Task 9` comment for CalendarSyncSheet preserves the build-green requirement.
- All Theme tokens used verbatim; no hardcoded colors in new files.

### Concerns
- None. Build and smoke test both clean.
