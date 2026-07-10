# Mobile Batch 3 (Drew TestFlight pass #3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three items from Drew's 2026-07-09 late TestFlight pass: overscroll past the day grid's end, "No upcoming deadlines" empty copy in the Tasks DUE view, and drag-to-move for scheduled blocks on the day grid ("edit mode").

**Architecture:** iOS-only (`AtlasMobile/`). Drag-to-move reuses the existing placement-drag machinery/patterns in DayGridView and MUST respect source writability (CLAUDE.md rule 5: an event's source and read-only status must reflect where it actually came from — read-only blocks are never draggable).

**Tech Stack:** SwiftUI (iOS 17), XcodeGen `Atlas.xcodeproj`.

## Global Constraints

- iOS build gate (every task): `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. SourceKit single-file diagnostics are noise.
- No AtlasCore behavior changes that alter Mac paths (adding a method is fine; changing existing behavior is not). No backend/migration changes.
- Match `MobileTheme` tokens/idioms (spring animation vocabulary, ink outlines, accent = live/NOW only).
- UI is not provable by a green build — final verification is Drew's TestFlight pass.
- Surgical diffs; commit per task; end commits with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Concurrent agents may commit on unrelated files: explicit-path staging only; index.lock → wait 2s, retry ≤5; never `git add -A`.

---

### Task F: Polish pair — grid overscroll + DUE empty copy

**Files:**
- Modify: `AtlasMobile/Views/Schedule/DayGridView.swift` (one value), `AtlasMobile/Views/Schedule/ScheduleView.swift` (one value)
- Modify: `AtlasMobile/Views/Tasks/TasksView.swift` (empty-state copy)

**Interfaces:** none new.

- [ ] **Step 1: Grid overscroll** — `DayGridView.swift:90` `.contentMargins(.bottom, 96, for: .scrollContent)` → `300` so the user can scroll past the last hour "into nothingness" and 10-11 PM content sits comfortably mid-screen. List mode: `ScheduleView.swift` list `.contentMargins(.bottom, 72, ...)` → `160` for the same breathing room. (Values are a first pass — Drew tunes by feel on device.)
- [ ] **Step 2: DUE empty copy** — in `TasksView.swift`, the DUE (deadline) grouping's empty state currently shows the "ALL CLEAR" treatment; change the DUE-mode string to `No upcoming deadlines` (same caps-label styling as the current empty state — copy change only, keep the visual treatment). SPACE mode and any other all-clear fallbacks unchanged.
- [ ] **Step 3: iOS build gate; commit** (one commit is fine):
`feat(mobile): grid overscroll past day end + "No upcoming deadlines" DUE empty copy`

---

### Task H: Drag-to-move scheduled blocks on the day grid (RUNS AFTER Task F lands — same file)

**Files:**
- Modify: `AtlasMobile/Views/Schedule/DayGridView.swift` (primary), possibly `AtlasMobile/Data/MobileStore.swift` (write-through call), possibly the block view struct if separate
- Read first: the research report handed to you at dispatch (writability gating + existing write paths)

**Interfaces:**
- Consumes: existing placement-drag pattern (`placementDrag`, snap math, confirm/cancel circles), existing block rendering, existing store write-through methods for events/tasks (per research report), existing source/writability flags on models (per research report).
- Produces: long-press-lift drag-to-move on WRITABLE blocks only.

**Requirement (Drew, verbatim intent):** "an edit mode… where it just makes all events or scheduled tasks draggable to easily move things around." Chosen shape (smallest thing that delivers it): **per-block lift-and-drag** — no global mode toggle:

- [ ] **Step 1: Long-press a WRITABLE block → it lifts** (slight scale/shadow, `MobileTheme.spring`, haptic tap) and becomes vertically draggable. The old empty-slot long-press is gone, so long-press on blocks is free. Read-only blocks (per the research report's actual gating — e.g. Canvas/Google/external read-only sources) do NOT lift; unchanged tap behavior.
- [ ] **Step 2: Drag** moves the block vertically with the same minute-snapping the placement chip uses (reuse/extract that math — do not duplicate it); duration stays fixed; a faint target-time label or the block's own position shows where it will land (match the placement chip's affordance).
- [ ] **Step 3: Release → confirm/cancel** using the SAME bottom-trailing confirm/cancel circle pattern placement uses (reuse the controls; FAB already auto-hides on `placing != nil` — wire the same hide for an active block-move, minimal state addition). Confirm writes the new time through the existing store write path (events: start/end shifted, duration preserved; scheduled tasks: `scheduled_at`); cancel restores the original position. No new persistence code — use whatever `ItemDetailSheet`/store already calls to reschedule (per research report).
- [ ] **Step 4: Scroll coexistence** — the lift gesture must NOT recreate the scroll-killer we just removed: attach the long-press to BLOCKS only (not the canvas), and verify a plain vertical pan on empty grid and ON a block (without completing the 0.4s hold) still scrolls. Describe in your report how the gesture is structured to guarantee this.
- [ ] **Step 5: iOS build gate; commit:**
`feat(mobile): long-press drag-to-move for writable blocks on the day grid`

---

### Task I: Verification (CONTROLLER + DREW)

- [ ] Reviews clean per task; final whole-branch review; push.
- [ ] Drew archives → TestFlight: overscroll feel; DUE copy; long-press-drag a task block and an Atlas event (moves + persists), verify a read-only block does NOT lift, verify grid still scrolls freely everywhere.
