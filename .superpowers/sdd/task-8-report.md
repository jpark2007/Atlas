# Task 8 — iOS 2-step calendar-views spotlight — Report

**Status:** COMPLETE. Both builds green. Committed (code files only).

## What was built
A skippable dim+cutout spotlight shown once ever on the first Schedule visit:
- Step 0: cutout over the list/grid `viewToggle`; advances when the user really taps it (`viewMode` changes).
- Step 1: cutout over the calendar glyph; finishes when month opens (`showMonth` becomes true).
- Prominent "Skip" button ends immediately. `@AppStorage("spotlight.calendarViews.done")` set on every exit path so it never re-triggers.

## Files
- `AtlasMobile/Views/Schedule/CalendarSpotlight.swift` (new) — `SpotlightAnchorKey` PreferenceKey, `spotlightAnchor(_:)` View extension, `CalendarSpotlightOverlay`.
- `AtlasMobile/Views/Schedule/ScheduleView.swift` (modified) — anchors on `viewToggle`/calendar Button; spotlight state; overlay hosting; step advance/finish wiring.

## Adjustments from brief (all sanctioned or forced by drift)
1. **Line numbers drifted** (Tasks 6+7 touched the file). Anchored on structure: `.spotlightAnchor("toggle")` on `viewToggle`, `.spotlightAnchor("calendar")` on the calendar-glyph Button. The glyph's existing action (`checklist.month` flag + `peekedMonth` donate) was left untouched — step 2 finish is driven by `.onChange(of: showMonth)`, not by editing the button.
2. **Skip button uses GeometryReader proxy** (`geo.size.width/2`, `geo.size.height - 80`) instead of the brief's deprecated `UIScreen.main.bounds`. Sanctioned in the task.
3. **`.zero` anchor guard** — overlay renders the cutout only when `anchors[holeID]` exists and is non-zero, preventing a flash of a hole at the origin before the preference is delivered.
4. **Merged into existing handlers** rather than adding duplicates: first-visit gating folded into the existing `.onAppear`; step-0→1 advance folded into the existing `.onChange(of: viewMode)`. Only `.onChange(of: showMonth)`, `.onPreferenceChange`, and the spotlight `.overlay` were added as new modifiers.

## Builds
- iOS: `-scheme AtlasMobile -destination generic/platform=iOS Simulator` → **BUILD SUCCEEDED**
- Mac: `-scheme Atlas -destination platform=macOS` → **BUILD SUCCEEDED**
- `xcodegen generate` run before building (new file under AtlasMobile/).

## Manual QA for Drew (device)
1. Fresh install → first Schedule tab visit: screen dims with a rounded cutout over the list/grid toggle + caption "Switch between list and grid".
2. Tapping the toggle *through the hole* actually changes the view AND advances to the calendar glyph ("Tap to jump to any day in month view").
3. Tapping the calendar glyph opens month view AND ends the spotlight.
4. "Skip" (bottom center) ends it immediately at either step.
5. Leave and return to Schedule tab in the same session → not re-shown.
6. Relaunch app → never shown again.
7. Reset: delete app or clear `spotlight.calendarViews.done` in UserDefaults.
- Dim + cutout positioning is visual and NOT proven by the green build — Drew must confirm the hole lands on the right controls and taps pass through.

## Concerns
- None functional. The dim has `.allowsHitTesting(false)` so header controls remain tappable through it — confirmed by design, needs Drew's visual pass.
