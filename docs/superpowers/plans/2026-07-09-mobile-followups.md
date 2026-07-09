# Mobile Follow-ups (Drew device pass #2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four iOS fixes from Drew's 2026-07-09 device test: scrollable day grid (kill the slot long-press), floating + on the schedule surface, always-visible Spaces→Projects cascade in the Tasks tab, and a basic Sign in / Create account split.

**Architecture:** All iOS-only view/behavior changes in `AtlasMobile/` (Task D may add one small auth method to shared `AtlasCore` if signup is missing). No backend/migration work. Approved by Drew in conversation 2026-07-09 (no separate spec doc — requirements are captured verbatim per task below).

**Tech Stack:** SwiftUI (iOS 17), XcodeGen project `Atlas.xcodeproj`, Supabase GoTrue auth.

## Global Constraints

- iOS build gate (every task): `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- Mac build gate (ONLY if `AtlasCore/` is touched — Task A guard-case and Task D): `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`.
- SourceKit single-file "Cannot find …" diagnostics are noise; xcodebuild is the source of truth.
- **Mac behavior must not change.** `AgendaBuilder` and other AtlasCore code is shared — Tasks must not alter shared logic paths the Mac consumes (adding a new method is fine; changing existing behavior is not).
- Match `MobileTheme` tokens and existing AtlasMobile style for anything visual (ink outlines, no filled accent buttons — accent is graphics-only).
- UI is NOT provable by a green build — final verification is Drew's TestFlight pass; every task reports "applied, builds, needs device check."
- Surgical diffs; commit per task; end every commit message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Concurrent agents commit to this repo on unrelated files: stage ONLY your task's files by explicit path; on git index.lock errors wait 2s and retry (max 5); never `git add -A`/`commit -a`.

---

### Task A: Always-visible Spaces→Projects cascade in the Tasks tab

**Files:**
- Modify: `AtlasMobile/Views/Tasks/TasksView.swift` (grouping/render logic — read it first)
- Possibly read (do NOT behavior-change): `AtlasCore/Sources/AtlasCore/AgendaBuilder.swift`, `AtlasCore/Sources/AtlasCore/Models.swift`

**Interfaces:**
- Consumes: the loaded snapshot's `spaces` + `projects` (all of a user's spaces/projects — server now seeds School+Personal with one starter project each for fresh accounts).
- Produces: no new API; view-local change.

**Requirement (Drew, verbatim intent):** In the Tasks tab's SPACE grouping mode, the Spaces → Projects drill-down cascade must render EVEN WHEN there are no tasks. Today an empty account shows only "ALL CLEAR"; instead it must list every space, with its projects nested under it (e.g. School → My First Class, Personal → Getting Started), so a fresh account sees its structure. Concretely:

- [ ] **Step 1: Read `TasksView.swift`** and determine how SPACE mode builds its groups (does it derive groups from tasks, or from spaces?). Report in your notes which it is.
- [ ] **Step 2: Implement** — SPACE mode iterates ALL spaces from the snapshot (in their `sort` order), rendering each space header with its projects nested beneath, then that project's tasks (if any). A project with zero tasks still renders as a row, with a muted `No tasks yet` hint line in `MobileTheme.faint` (small, unobtrusive, matches existing row typography). A space with zero projects still renders its header. Keep the existing "ALL CLEAR" treatment ONLY for the DUE grouping mode (which is date-driven); SPACE mode never shows it.
- [ ] **Step 3: Keep done-task behavior exactly as-is** — do not touch `AgendaBuilder` or shared filtering (known Drew-decision pending on done-rows; out of scope). If the grouping currently lives in shared code, do the always-visible union view-locally in `TasksView` (spaces/projects joined against the task groups), leaving shared code untouched.
- [ ] **Step 4: Build gate(s), commit** — iOS gate; plus Mac gate only if any AtlasCore file changed (it should not).
Commit: `feat(mobile): Tasks SPACE view always shows spaces→projects cascade, even empty`

---

### Task B: Scrollable day grid — delete the slot long-press

**Files:**
- Modify: `AtlasMobile/Views/Schedule/DayGridView.swift`

**Interfaces:**
- Consumes: nothing new. Produces: the grid canvas with NO slot-press gesture; placement-chip drag (`placementDrag`, `:267`) and all placement UI stay.

**Requirement (Drew):** the long day grid must scroll natively; the press-and-hold empty-slot add is REMOVED entirely (the + button flow covers adding).

- [ ] **Step 1: Delete the slot long-press** — remove `.gesture(slotPress)` at `DayGridView.swift:106`, the `slotPress` gesture definition (`:114-124`, incl. its design comment `:109-113`), and any state/vars/handlers that exist ONLY for it (whatever a grep shows is now orphaned — e.g. slot-hold state, haptics calls, the slot-press-created-event path). Do NOT touch `placementDrag` (`:267,271-285`) or the placement confirm/cancel controls (`:287-303`) — chip placement via the sheet stays fully functional.
- [ ] **Step 2: Verify no orphans** — grep the file (and `AtlasMobile/`) for identifiers you removed; delete only what YOUR removal orphaned; report anything ambiguous instead of deleting it.
- [ ] **Step 3: iOS build gate, commit**
Commit: `feat(mobile): day grid scrolls natively — remove slot long-press (add via + instead)`

---

### Task C: Floating + button on the schedule surface (RUNS AFTER Task B lands — same file region)

**Files:**
- Modify: `AtlasMobile/Views/Schedule/ScheduleView.swift`

**Interfaces:**
- Consumes: existing `showPlace` sheet state (`ScheduleView.swift:117-121` button → `.sheet` at `:62-68`), existing `placing` chip-placement state (find its owner — `beginPlacing` is `ScheduleView.swift:344-350`), existing bottom furniture: Today pill overlay (`:35-55`, bottom-center, `.padding(.bottom, 14)`) and grid placement controls (`DayGridView.swift:45-47, 287-293`, bottom-trailing `.padding(.trailing, 24).padding(.bottom, 96)`).
- Produces: a floating + button; the header place button removed.

**Requirement (Drew):** floating circular + at the bottom-right of the schedule surface itself (BOTH grid and list modes), replacing the header `calendar.badge.plus`.

- [ ] **Step 1: Add the FAB** — 44pt circle, bottom-trailing overlay on the schedule content (`.padding(.trailing, 24)`, bottom padding clearing the tab bar consistent with existing insets ~`.padding(.bottom, 96)`), containing a plus glyph. Style per AtlasMobile language: paper `MobileTheme.bg` fill with 1.5pt `MobileTheme.ink` stroke + ink plus (mirror the existing placement `placeCircle` look, `DayGridView.swift:299`, for visual consistency) — NOT an accent-filled button. Tapping sets `showPlace = true` (same sheet as today).
- [ ] **Step 2: Auto-hide while placing** — the FAB is hidden whenever chip placement is active (`placing != nil` state), because placement confirm/cancel circles occupy the same corner. Animate with the standard `MobileTheme.spring`.
- [ ] **Step 3: Remove the header button** — delete the `calendar.badge.plus` button (`ScheduleView.swift:117-121`); row 2 drops to 4 controls. Remove anything that removal orphans; keep `showPlace` (the FAB uses it).
- [ ] **Step 4: iOS build gate, commit**
Commit: `feat(mobile): floating + on schedule (grid+list), header place button removed`

---

### Task D: Basic Sign in / Create account split

**Files:**
- Modify: `AtlasMobile/Views/SignInView.swift` (or wherever the iOS auth screen lives — locate it)
- Possibly modify: `AtlasMobile/Data/MobileStore.swift`, `AtlasCore/Sources/AtlasCore/SupabaseAuth.swift` (ONLY if a signup call is missing)

**Interfaces:**
- Consumes: existing email+password sign-in (`MobileStore.signIn`-style) and `signInWithApple` (`MobileStore.swift:76-84`). GoTrue: password grant = sign-in; `POST /auth/v1/signup` = account creation.
- Produces: a two-mode auth screen. Apple button identical in both modes (OAuth auto-creates; do not fork its behavior or copy).

**Requirement (Drew):** "basic page difference for sign in v sign up since we have email and pass but nothing major since most ppl will rely on apple sign in anyway."

- [ ] **Step 1: Locate the iOS auth screen** and the email/password submit path; check whether `SupabaseAuth` already exposes a signup (the Mac may already create accounts — search for `signup`/`signUp` before writing one).
- [ ] **Step 2: Add a mode toggle** — a small "Sign in / Create account" switcher (text-button toggle beneath the form, editorial style — no segmented control chrome). Mode changes: the submit button label (`Sign in` ↔ `Create account`), and in create mode the submit calls the signup path instead of the password grant. Same email+password fields (no confirm-password field — keep it basic per Drew). Apple button and any error-banner plumbing untouched.
- [ ] **Step 3: If signup is missing from AtlasCore**, add ONE minimal method to `SupabaseAuth` mirroring the existing sign-in method's style (`POST {url}/auth/v1/signup`, same session decode/persist path). Handle the "email confirmation required" project setting gracefully: if signup returns no session, surface the existing-style notice text telling the user to check email — do not build new UI machinery.
- [ ] **Step 4: Build gates, commit** — iOS gate always; Mac gate too if AtlasCore changed.
Commit: `feat(mobile): sign-in / create-account modes on the auth screen`

---

### Task E: Verification (CONTROLLER + DREW)

- [ ] All tasks reviewed clean; final whole-branch review.
- [ ] Push to origin. Drew re-archives + TestFlight: grid scrolls freely; + floats bottom-right on both modes and hides during placement; fresh/empty account shows School→My First Class / Personal→Getting Started cascade in Tasks SPACE view; auth screen toggles Sign in / Create account; (carry-over) new paper palette + delete-account red legibility.
