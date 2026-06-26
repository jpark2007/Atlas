# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume work.** Snapshot of where we are, the agreed plan, and exactly what's next.

_Last updated: 2026-06-26_

---

## TL;DR for a new session

> We're building **Atlas**, a native SwiftUI (iOS + macOS) smart life manager. The **macOS app is scaffolded and builds clean** on a mock data store. Design is locked (dark, orange accent) and realized for 3 screens. Next: fix the dashboard, build 4 more screens via parallel agents, then wire **Supabase** (auth + data) and the **OpenRouter** AI brain. Full vision in `docs/atlas-vision.md` + `docs/specs/`. Manual setup steps in `docs/SETUP.md`.

To continue: open this repo, run `xcodegen generate && open Atlas.xcodeproj`, and tell the new chat *"continue Atlas from docs/HANDOFF.md."*

---

## Current state (what exists)

- **Builds:** `BUILD SUCCEEDED` (macOS). Run with:
  ```bash
  xcodegen generate
  xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
  # or: open Atlas.xcodeproj  → ▶ Run
  ```
- **Stack:** Swift/SwiftUI, XcodeGen (`project.yml`), macOS 14+. Mock data store (`AppState` + `MockData`) — designed to be swapped for Supabase with no UI changes.
- **Built screens:** Sidebar (Spaces, nav), **Dashboard** (schedule/tasks/focus/goals), **Class detail** (notes, linked-references/backlinks, Canvas badge, pinned URLs). Calendar + Focus are placeholders.
- **Design system:** `Atlas/DesignSystem/Theme.swift` — exact palette from the approved prototype (accent `#ff8c42`, warm near-black bg, SF Pro).
- **Carryover code** to integrate: `docs/carryover/` (global pill hotkey + focus timer from the old prototype — macOS-only, needs restyle).

### File map
```
project.yml                       XcodeGen config (the .xcodeproj is git-ignored, generated)
Atlas/
  App/        AtlasApp, RootView (NavigationSplitView + Route enum)
  DesignSystem/ Theme.swift (AtlasTheme + AtlasCard)
  Models/     Models.swift (Space, Project, ScheduleEntry, TaskItem, Goal, NoteRef, PinnedResource, Backlink)
  Data/       AppState (ObservableObject store), MockData (sample data)
  Views/      Sidebar/, Dashboard/, Project/
docs/         atlas-vision, specs/, carryover/, SETUP, HANDOFF (this file)
```

---

## Known issues to fix FIRST (next session)

1. **Dashboard schedule rows are far too tall.** Cause: the accent bar uses `.frame(maxHeight: .infinity)` and the right column forces the card to stretch. Fix: give schedule rows a fixed height (~60pt) and the accent bar a fixed height; top-align. See `Atlas/Views/Dashboard/DashboardView.swift` → `ScheduleCard.scheduleRow`.
2. **Empty title-bar strip** at the top with a lone sidebar toggle — clean up the window chrome (hidden titlebar / toolbar treatment) in `AtlasApp.swift`.

---

## The plan (agreed)

**Scope chosen: EVERYTHING including AI.** Sequenced so nothing blocks:

### Stage 0 — Foundation (solo, do before agents)
Fix the two known issues AND expand the shared base so parallel agents can't collide:
- Add `CalendarEvent` (real `Date` start/end, `timeLabel`/`durationLabel`) and `Note` models.
- Add to `AppState`: `events`, `notes`, `presentCapture: Bool`, `addTask(title:)`, `events(on:)`, `unscheduledTasks`, and a `Route.focus` case (placeholder-routed at first).
- Make the Dashboard derive its schedule from `events` (single source of truth shared with Calendar).
- Verify `BUILD SUCCEEDED`, commit.

> _A WIP version of this was started then reverted to keep the baseline building — redo it cleanly as Stage 0._

### Stage 1 — Parallel agents (each in its own git worktree)
**Conflict rule: agents ONLY add new files and extend `AppState` via `extension AppState { }` in their own file. They must NOT edit RootView/AppState/Models/Theme.** Each agent runs `xcodebuild` in its worktree to prove it compiles, and returns its files + a short report.

- **Agent A — Calendar** (the hero): day + week time-grid reading `state.events`, color-coded by space, with the drag-to-schedule tray (`state.unscheduledTasks`). New file `Views/Calendar/CalendarView.swift`.
- **Agent B — Quick-capture pill**: a ⌘-triggered floating NL input that calls `state.addTask`; reference `docs/carryover/global-pill-hotkey/` for the macOS hotkey + NSPanel pattern (restyle to liquid-glass). New files under `Views/Capture/`.
- **Agent C — Focus mode**: Pomodoro pill timer — port + restyle `docs/carryover/focus-pill-timer/` (its own `FocusViewModel`). New files under `Views/Focus/`.
- **Agent D — Search + Notes**: ⌘K command palette/search over spaces/projects/tasks/notes + a note editor matching `screenshots/note-edit.png`. New files under `Views/Search/` + `Views/Notes/`.

### Stage 2 — Integrate & review (solo)
Merge worktrees, wire the ~4 one-line route/presentation hooks in `RootView`/`AtlasApp`, regenerate, full build, launch, **screenshot, compare to mockups, iterate until proper.**

### Stage 3 — Backend (Supabase) + AI (OpenRouter)
- Replace `MockData`/`AppState` internals with Supabase (auth + Postgres + realtime) per `docs/specs/01-architecture.md` and the schema sketch in `docs/specs/02-data-model.md`. UI surface stays identical.
- Add a Supabase **Edge Function** that proxies OpenRouter (GPT-4o-mini) for NL capture/bucketing per `docs/specs/04-ai-brain.md`. The OpenRouter key is a server-side secret, never in the app.

### Later — Mobile (iOS)
A **simplified "quick access" version** sharing the same models/state: Today view + quick capture + focus. Not a full port.

---

## What YOU (human) need to do — see `docs/SETUP.md`

In priority order:
1. **Supabase** — create the project, paste me the **Project URL + anon key**. (Backend blocker.)
2. **OpenRouter key** — ✅ you have it. **Where it goes:** NOT in the app or git. It becomes a **Supabase Edge Function secret** (`OPENROUTER_API_KEY`) once the Supabase project exists. For now, keep it in your password manager; paste it when we wire Stage 3. (If you want to test AI *before* Supabase, we can temporarily use a git-ignored `Atlas/Config/Secrets.xcconfig`, but server-side is the real home.)
3. Later: Google Cloud OAuth (Calendar/Drive/Gmail), Canvas token, Apple signing.

---

## Architecture recap (so the new chat has context)

- Native SwiftUI, one codebase iOS + macOS, Apple-only for now.
- All UI talks to `AppState` → swap its guts for Supabase later without touching screens.
- AI = OpenRouter/GPT-4o-mini, always behind a Supabase Edge Function (key hidden).
- `.gitignore` blocks committing secrets and the generated `.xcodeproj`. Commit `project.yml` + Swift source; run `xcodegen generate` after pulling.
