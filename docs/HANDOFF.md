# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume.** Current state, how the calendar model
works, the planned work (broken into subagent-able bites), and the honest caveats.

_Last updated: 2026-06-28 — v2 + follow-ups are live on `main`. **Google
Calendar READ sync is working live** (the app mirrors the user's primary Google
calendar). A round of UI fixes is in flight: the **traffic-lights** (bite I) and
**drag-to-schedule** (bite A) fixes are now **applied (build-green) and awaiting the
user's live verification**. Live-testing is happening interactively._

---

## ✅ What works right now (confirmed live by the user)

- **Google Calendar read sync** — connect in Settings → Calendars → Connect; the
  grid shows the user's real Google events. OAuth consent works (user + partner are
  Test Users on the Google Cloud project).
- **Global ⌘⇧K capture** — fires from anywhere while Atlas runs (no longer crashes,
  no longer shadowed by the menu-bar item).
- **⌘K command palette** — opens (the focus/hidden-button issue is resolved).
- **Real logo**, relationship **graph view**, **dashboard** (live date, tasks now
  stacked under the schedule, top-corner stats removed), **app icon** (figure sized
  to fill the tile, not cropped).

## 🔧 In flight (uncommitted working-tree changes, build-verified)

- ✅ Confirmed good live: app icon enlarged (fills tile, not cropped); dashboard
  restacked (tasks under schedule, top stats removed); Metrics popup widened (640);
  Settings widened (560).

### Fix applied — awaiting live verification (build-green, NOT yet user-confirmed)

- **Traffic-lights (bite I).** Root cause was found: `.toolbar(.hidden, for:
  .windowToolbar)` in `Atlas/App/RootView.swift` was stripping the entire window
  toolbar — including the red/yellow/green controls. Fix: **removed** that line from
  `RootView.swift` and **restored** `.windowStyle(.hiddenTitleBar)` in
  `Atlas/App/AtlasApp.swift`. `WindowConfigurator` is kept (it nils the toolbar for
  the gray-strip suppression, which is button-safe). Needs the user to confirm the
  buttons are back on a real run.
- **Drag-to-schedule (bite A).** Two fixes in `Atlas/Views/Calendar/UnscheduledTray.swift`:
  (1) replaced the chip's `.onTapGesture` with `.simultaneousGesture(TapGesture())`
  — a plain tap was swallowing the drag's mouse-down on macOS; (2) switched the drag
  payload from a Codable `DraggableTaskID(.json)` Transferable to a plain `String`
  (`task.id.uuidString`), because a `.json` Transferable does not round-trip on the
  macOS drag pasteboard. `Atlas/Views/Calendar/TimeGridView.swift` `dropDestination`
  now takes `String.self`. Needs the user to confirm a chip actually drops onto the
  grid and schedules.

## 🆕 New findings & requirements (2026-06-28 evening — from live testing)

- **Checkboxes must be SQUARES, standardized everywhere.** Today they're a mix of
  circles (dashboard, calendar tray, project starter tasks). Make all task
  checkboxes square + consistent.
- **Calendar tray checkbox is still open (bite H).** Clicking the check circle in the
  Unscheduled tray completes the task instead of just toggling done — the tap fell
  through to the chip's gesture. Note: the chip's tap gesture was just reworked for
  bite A (the chip now uses `.simultaneousGesture(TapGesture())`, which opens the
  due-date editor — not scheduling). Re-verify the checkbox behavior on top of that
  change, then fix the gesture priority so the checkbox only completes the task.
- **Project-detail "starter tasks" aren't checkable.** Those dashed circles are
  editable *placeholders* (never persisted), so clicking does nothing — but they
  look like checkboxes. Either make project tasks real + checkable, or visually
  distinguish placeholders from real checkboxes. User expects to check them off.
- **Only the Dashboard task checkboxes actually work today.**
- **Settings should be an actual full PAGE** (like Dashboard/Calendar/Focus), opened
  from the sidebar near the user's name — NOT a popup sheet. **Metrics becomes a
  sub-section inside that Settings page** (not a separate sidebar item / not a popup).
  This supersedes the old "merge popups" framing of bite F.

## Git / push state

- `origin/main` = `f913478` (pushed). Local `main` = `9c6926e` (UI fixes commit) is
  **1 ahead, unpushed** — GitHub was returning HTTP 408 on uploads (network, not code).
  The latest in-flight UI batch is **uncommitted** in the working tree — it now
  includes the **traffic-lights (bite I)** and **drag-to-schedule (bite A)** fixes
  above, held until the user confirms them on a real run. Retry `git push origin main`
  when the network settles; the `9c6926e` commit is safe locally.

---

## How the calendar model works (the user asked — explain in-app too, later)

The Calendars settings pane: **"Aggregate read-only. Pick one source to write new events."**

- **Read = everything, together.** Atlas pulls events from every connected source
  (Apple, Google, Canvas, Atlas-native) and shows them on one grid, read-only. It is
  NOT "Google OR Apple" — you see all of them at once.
- **Write = one destination ("Main calendar").** New events you create in Atlas need
  one home. That picker chooses it. Today it defaults to `Atlas` (native) and the UI
  label still says "write-back to Apple/Google deferred (v2)" — **that label is now
  stale**: Google write-back IS coded (`GoogleCalendarService` create/update/delete,
  wired in `AppState`, commit `3abccc4`). It just needs the picker set to `Google` to
  actually fire, plus the label updated. **This is the user's "I want write-back too"
  request — see planned bite #3.**
- **"Default space for Apple events"** — imported external events don't belong to an
  Atlas Space, so Atlas files/colors them under this default bucket (e.g. School).
  Same idea applies to Google imports. Purely categorization/coloring.
- **Canvas LMS** — the school's learning system (assignments/due dates). "deferred
  (v2)": not built. Access depends on the school enabling Canvas API; some restrict it.

---

## Planned work — bite-sized, parallelizable with subagents

Partitioned so agents don't edit the same files. **Parallel-safe** units touch
disjoint areas; **sequential** units share a file.

| Bite | What | Files (rough) | Parallel group |
|---|---|---|---|
| **A. Drag-drop fix** | **FIX APPLIED — awaiting live verification.** Tap was swallowing the drag's mouse-down (`.onTapGesture` → `.simultaneousGesture(TapGesture())`) and the `.json` Transferable didn't round-trip → drag payload is now a plain `String` (uuidString); drop target takes `String.self`. | `UnscheduledTray`, `TimeGridView` | — |
| **C. Week-view overhaul** | Empty gap up top, events cram into one column. | `TimeGridView`, `CalendarView` | Calendar (C, coordinate w/ H-tray) |
| **B. Floating capture panel** | ⌘⇧K should pop a Spotlight-style non-activating panel OVER other apps — not yank you into Atlas. New `NSPanel`. | `CaptureOverlay`, `HotkeyService`, `AtlasApp`, new panel file | Independent |
| **D. ⌘K search → events** | Search covers tasks+notes only; add calendar events incl. external/Google ones. | `CommandPalette` / search model | Independent |
| **E. Google write-back enable** | Wire "Main calendar = Google" to fire the existing write-back; refresh the stale labels. | `SettingsView`, `AppState` | Settings (E→F) |
| **F. Settings as a PAGE + Metrics inside it** | Make Settings a full route/page (like Dashboard/Calendar), opened from the sidebar near the user's name. Move Metrics in as a sub-section of that page. Remove the Metrics sidebar item + the Settings/Metrics popups. | `SettingsView`, `MetricsView`, `RootView`, `SidebarView`, `AppState`(Route) | Settings (E→F) |
| **H. Square + working checkboxes** | Standardize ALL task checkboxes to squares; fix the tray checkbox (it auto-schedules instead of completing — gesture priority); make project tasks real + checkable (or distinguish placeholders). | `UnscheduledTray`, `DashboardView`, `ProjectDetailView` | Mostly independent (touches calendar tray — coordinate with A/C) |
| **I. Traffic-lights** | **FIX APPLIED — awaiting live verification.** Root cause: `.toolbar(.hidden, for: .windowToolbar)` in `RootView` stripped the whole toolbar incl. the close/min/zoom controls. Removed that line; restored `.windowStyle(.hiddenTitleBar)`; kept `WindowConfigurator` for gray-strip suppression. | `RootView`, `AtlasApp` | — |
| **G. Settings width** | DONE (560). | `SettingsView` | — |

**Orchestration:** A and I are **fix-applied, awaiting the user's live verification** —
not part of the parallel agent plan anymore (just confirm them on a real run). Of the
open bites: C + the H-tray checkbox as one **calendar agent** (shared `TimeGridView`/
`CalendarView`/`UnscheduledTray`); B and D as independent agents (parallel, isolated
worktrees); E then F (shared `SettingsView`) run after, sequentially; H's
dashboard/project checkbox + square standardization folds into the relevant agents.
Build + 220 tests after each merge; the user live-tests UI behaviors (none are
provable without their eyes).

---

## Mobile companion (planned — spec'd, not built)

Preliminary **iOS companion** design is drafted in [`specs/11-mobile-companion.md`](specs/11-mobile-companion.md): a minimal **capture + glance** app (NOT a port). 3 tabs (Schedule/Capture/Tasks) + gear, opens to Schedule; reuses the same Supabase backend via a shared Swift package (`Models`/`AtlasDB`/`AtlasAI`); local notifications in v1 (APNs silent-push fast-follow); a lean widget kit (home 4×2/4×4, lock-screen rect+circular, Control Center/Action-Button capture). Capture-screen mockups approved as direction; design tokens + regeneration prompts saved in the spec's Appendix A. **Build after the macOS daily-driver; run brainstorming → writing-plans when ready.**

---

## Honest caveats

- **Write-back to Google is unproven live** (coded, not yet exercised end-to-end).
- **Drag-drop, floating panel, week view, search** = build-verifiable only; need live
  testing on the user's machine.
- Stale `build/` DerivedData has bitten us (entitlements-modified errors) — build to an
  explicit `-derivedDataPath build`, and `rm -rf build` if that error appears.
- SourceKit "Cannot find AppState/AtlasTheme/XCTest" warnings are cross-file isolation
  noise — the real `xcodebuild` is green (220 tests).
