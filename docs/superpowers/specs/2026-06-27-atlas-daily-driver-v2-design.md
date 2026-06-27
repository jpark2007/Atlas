# Atlas Daily-Driver v2 — Design & Agentic Execution Plan

**Date:** 2026-06-27
**Branch base:** `feat/daily-driver-v1` (18 commits ahead of `main`, not yet pushed)
**Status:** Design approved at a high level by user ("go after it all"). This doc is the record + the subagent execution plan. No code written yet.

---

## 0. One-paragraph summary

v1 shipped the shell: spaces, calendar (day/week), unscheduled tray, capture overlay, metrics, EventKit read-only. But the AI brain never actually runs (its backend was never deployed, and failures are swallowed), tasks have no real due dates, scheduling is fully manual, there's no global capture / voice, no Google sync, no way to add a project, and the dashboard/metrics need restructuring. v2 makes Atlas an actual daily driver: a working AI capture pipeline, structured task dates with auto-scheduling, global + voice capture, Google Calendar two-way sync, month/list calendar views, project management, and a reworked dashboard + donut metrics.

---

## 1. Root-cause findings (grounded in the code, not assumptions)

A three-agent read-only scout produced these facts. They reframe several of the user's complaints.

| Complaint | Reality found in code | Root cause |
|---|---|---|
| "OpenRouter hasn't been called" | `AtlasAI.parse()` → Supabase Edge Function `capture` → OpenRouter (GPT-4o-mini). One call site: `CaptureOverlay.swift:219`. | The `capture` function was **never deployed** (per HANDOFF). Every parse 404s. |
| "Everything in Unscheduled is raw text (`math exam on friday`)" | On ANY error, `CaptureOverlay.swift:239` silently `state.addTask(title: rawText)`. | Same — AI down → silent fallback to plain task, failure hidden. |
| "Doesn't parse 8pm / due friday" | `TaskItem` has **no `dueDate`** — only free-text `dueLabel`. Even when AI returns `dueISO`, tasks discard it (`CaptureOverlay.swift:232`). | Data-model gap + silent fallback. |
| "Weekly view needs work" | Code shows a **fully built** 7-day grid (`TimeGridView.swift:250`). | Not a stub — likely visual/polish. Needs run-the-app diagnosis. |
| "Braindump/speak from global command" | `⌘⇧K` capture overlay IS the braindump and DOES call AI — but only when app is focused. No voice anywhere. | True global hotkey explicitly deferred (`ShortcutStore.swift:6`). Carryover Carbon hotkey exists, unwired: `docs/carryover/global-pill-hotkey/HotkeyService.swift`. Zero Speech-framework code. |
| "⌘K vs ⌘⇧K confusing" | `⌘K` = search/command palette; `⌘⇧K` = capture. | Two separate entry points; palette can't create-on-the-fly. |
| "Metrics shouldn't be in sidebar; use donuts" | Metrics is sidebar item (`SidebarView.swift:19`). Charts are linear/horizontal bars only — **no Swift Charts, no donuts**. `presentMetrics` popup hook already exists in AppState. | Easy to relocate; donuts need Swift Charts. |
| "Global search should search tasks + create on the fly" | `⌘K` already searches projects/tasks/notes by substring; on no match shows "No matches." | Create-on-the-fly missing. |
| "Unscheduled returns after the slot passes" | `unscheduledTasks = tasks.filter { scheduledAt == nil && !done }`. No time-based re-evaluation anywhere. | Behavior doesn't exist yet. |
| "Filter by space but calendar stays global" | Calendar grid has All/per-space filter; **Unscheduled tray ignores it** (always all spaces). | Tray needs to respect the filter. |
| "Tasks should flow below the schedule, grouped" | Dashboard tasks live in a 320px right rail as a flat list. No grouping, no filter. | Restructure `DashboardView`. |
| "Sync to a real calendar" | EventKit (Apple) = read-only, working. Google = deferred stub, no OAuth. | User chose **Google first**. |
| "Expand and close at the top" (Image #4) | Native macOS traffic-light window controls. | Ensure standard window chrome shows. |
| Reference calendar (Image #1) | Has Month/Week/Day/List + in-calendar search + Colors/Tags/Categories. Atlas has only Day/Week + space filter. | Add Month + List + search + tags. |

**Highest-leverage insight:** deploying `capture` + un-hiding failures + giving `TaskItem` a real `dueDate` fixes ~4 complaints at once and unblocks everything time-related. It is the foundation.

---

## 2. Scope (full — everything discussed, decomposed into workstreams)

User confirmed: **do all of it.** Decomposed so parallel agents don't collide on shared files.

- **WS-0 Diagnose** — confirm AI deploy state + reproduce silent fallback; visual diagnosis of week view & window chrome. (read-only / run app)
- **WS-1 Foundation** — `TaskItem` structured dates + capture pipeline live + failures surfaced. **Must land before all of WS-2..WS-9 (Phase 2).**
- **WS-2 AI brain upgrade** — multi-item paragraph parsing, project/space context injection, deploy `capture`.
- **WS-3 Scheduling** — auto-find-a-slot suggestion, drag-to-suggested, revert-after-slot-passes, manual due-date picker, space-filter the tray.
- **WS-4 Calendar views** — week-view polish, **Month view**, **List view**, in-calendar search, tags/categories/color filters, native window controls.
- **WS-5 Google Calendar sync** — OAuth (PKCE), read + write-back.
- **WS-6 Global hotkey + Voice** — *(its own subagent group)* system-wide hotkey via carryover `HotkeyService`; click-to-talk mic button in the corner of the capture overlay (NOT listening on open); on-device `SFSpeechRecognizer`.
- **WS-7 Command palette unify** — `⌘K` searches tasks + "Create '<query>'" on the fly.
- **WS-8 Spaces/Projects** — add-project UI + edit description/detail.
- **WS-9 Dashboard + Metrics** — tasks-below-schedule grouped by headings (+ space filter); pull Metrics off sidebar into popup; donut/ring charts.

---

## 3. Foundation (WS-1) — must land first

**Problem:** `TaskItem` has no structured date; capture hides AI failures.

**Changes:**
1. `Models.swift` `TaskItem`: add `dueDate: Date?`, `startAt: Date?` (already has `scheduledAt`), `durationMin: Int?`. Keep `dueLabel` as a *derived* display string (computed from `dueDate`), migrate existing string data best-effort.
2. `AtlasDB`: persist the new fields; lightweight migration.
3. `CaptureOverlay.swift`: for `kind == "task"`, parse `dueISO` → `dueDate` (stop discarding it). For events keep current `startISO` handling.
4. **Surface failures:** replace the silent `catch → addTask(rawText)` with a visible state — e.g. "Saved as plain task — AI offline" badge / retry — so a down backend is never invisible again. Keep the never-lose-data fallback, just make it honest.
5. Deploy the `capture` edge function (or document exact deploy command for the user if Supabase CLI auth is required).

**Why first:** WS-3 (scheduling), WS-2 (AI), WS-9 (dashboard grouping by due date) all depend on a real `dueDate`.

---

## 4. Workstream designs

### WS-2 — AI brain upgrade
- **Multi-item paragraph:** `capture` returns an **array** of `CaptureResult`, not one. Client loops and creates each. (Paste "essay due thu, gym 3x, dinner sunday" → 3 items.)
- **Context injection:** client sends the user's spaces + project names/codes to the function so the model routes each item to the right Space/Project. Edge function prompt updated accordingly.
- **Deploy + secret:** OpenRouter key as Supabase function secret; verify end-to-end.

### WS-3 — Scheduling
- **Auto-find-a-slot:** given a task with `durationMin` (default 60), scan the day's free gaps and propose a slot; user accepts or drags elsewhere. Surfaced as a "Suggest a time" affordance + a ghost block on the grid.
- **Drag-to-suggested:** keep manual drag (already works); the suggestion is draggable too.
- **Revert-after-slot:** a task scheduled 2–3pm that isn't `done` by 3pm returns to Unscheduled. Implemented as a derived computation (a scheduled-but-past-and-unchecked task is treated as unscheduled) + a timer-driven refresh, not destructive data edits — so nothing is lost, it just resurfaces.
- **Manual due-date picker:** clicking a task opens an editor with a date/time picker (sets `dueDate`) and optional duration.
- **Space-filter the tray:** `UnscheduledTray` respects the calendar's space filter; calendar grid stays global-capable.

### WS-4 — Calendar views
- **Week polish:** act on WS-0 visual findings.
- **Month view:** new `MonthGridView` — 6-week grid, event chips per day (model on Image #1), click a day → day view.
- **List view:** agenda-style chronological list of upcoming events/tasks.
- **In-calendar search:** search events/tasks by title within the calendar.
- **Tags/categories/colors:** lightweight category/tag filter row (Image #1's Colors/Tags/Categories). Reuse space colors initially; tags are additive.
- **Native window controls:** ensure `.titlebar`/window style shows the standard traffic lights (close/minimize/zoom); fix whatever custom chrome is hiding them.

### WS-5 — Google Calendar sync
- **OAuth:** `ASWebAuthenticationSession` + **PKCE** (no client secret to protect). Tokens in Keychain; refresh handling.
- **Read:** fetch Google events, merge into the calendar like EventKit does (tagged read-only or editable per scope).
- **Write-back:** create/update Atlas events in Google.
- **Settings:** wire the existing "Connect Google" stub (`SettingsView.swift:171`) to the real flow.
- **Prereq:** user-provided Client ID (see §6).

### WS-6 — Global hotkey + Voice *(dedicated subagent group)*
- **Global hotkey:** integrate carryover `HotkeyService.swift` (Carbon) so capture works system-wide, app unfocused.
- **Voice:** on-device `SFSpeechRecognizer` + `AVAudioEngine`. **Click-to-talk only** — a **mic button in the corner of the capture overlay**; tapping starts listening, NOT on open. Transcript flows into the same capture text field → same AI pipeline. Handle mic + speech permissions.
- Why its own group: permissions, entitlements, and Carbon/AVFoundation are a distinct risk surface; isolating it keeps the other workstreams clean.

### WS-7 — Command palette unify
- `⌘K` keeps searching projects/tasks/notes; add a persistent top row **"Create '<query>'"** that, on no/any match, creates a task (routes through AI when possible) — "make it on the spot."
- Clarify ⌘K (find/create) vs ⌘⇧K (braindump) in UI copy.

### WS-8 — Spaces / Projects
- **Add project:** "+" affordance on each Space (and/or context menu) → sheet to create a project/class (name, code, isClass, description).
- **Edit:** edit `overview`/description and metadata from `ProjectDetailView`.
- Persist via `AtlasDB` `ProjectRow`.

### WS-9 — Dashboard + Metrics
- **Tasks below schedule:** move the all-tasks list out of the 320px rail into a **full-width section under "Today's schedule,"** grouped by headings (due date / space / topic), with an optional space filter.
- **Metrics off sidebar:** remove `SidebarView.swift:19`; surface Metrics via the existing `presentMetrics` popup (from ⌘K quick-actions and/or a top-right/profile entry).
- **Donut charts:** add **Swift Charts**; replace linear completion/space bars with donut/ring visualizations (completion ring, per-space donut).

---

## 5. Agentic execution plan

**Coordination constraint:** WS-1/2/3/9 all touch `Models.swift`, `AppState.swift`, `CaptureOverlay`, `CalendarView`. Parallel worktrees would conflict. Hence **phased**, with the foundation serialized first.

### Phase 0 — Diagnose (2 agents, parallel, read-only / run app, no edits)
- **Diag-A (AI pipeline):** confirm `capture` deploy state; reproduce silent fallback live (type "essay due friday 8pm" → observe it become a plain task); confirm ⌘K works on the real binary; list exact deploy steps.
- **Diag-B (visual):** run the app; screenshot week view + window chrome; pinpoint what "week view needs work" and the missing traffic lights actually are.
- *Also:* offer to delete the 6 stale DerivedData builds so wrong-binary mixups can't recur.

### Phase 1 — Foundation (1 agent, solo) — **everyone waits**
- WS-1 in full. Merge to branch. This is the spine.

### Phase 2 — Parallel workstreams (each in its own git worktree, rebased on Phase-1)
- **Agent-AI:** WS-2
- **Agent-Sched:** WS-3
- **Agent-Cal:** WS-4
- **Agent-Google:** WS-5 (starts once user provides Client ID; code can scaffold before)
- **Voice group (2–3 agents):** WS-6 — one for global hotkey integration, one for Speech/mic UI, one to review entitlements/permissions
- **Agent-Palette:** WS-7
- **Agent-Proj:** WS-8
- **Agent-Dash:** WS-9

Worktrees prevent file collisions; each rebases on the merged foundation. Shared-file edits (Models/AppState) are mostly done in Phase 1 to minimize later conflicts.

### Phase 3 — Review & verify
- A `code-review` agent per workstream diff.
- One **integration-review** agent for cross-cutting conflicts after merges.
- A manual **run-the-app verification** pass (build to explicit `-derivedDataPath`, launch that binary — per the stale-build lesson) before anything is pushed. **User pushes when ready.**

---

## 6. Manual prerequisites (what only the user can do)

**Google Cloud (one-time, ~10 min):**
1. console.cloud.google.com → new project `Atlas`.
2. APIs & Services → Library → **Google Calendar API** → Enable.
3. OAuth consent screen → External → app `Atlas` → add **lets.flowstate@gmail.com** as Test user → scope `.../auth/calendar.events` → status **Testing**.
4. Credentials → Create → OAuth client ID → **Desktop app** → copy **Client ID** → paste to Claude.

**At runtime (only the user):** the "Sign in → Allow" consent click in the Google window (can't be done headlessly by an agent).

**Supabase (maybe):** if `capture` deploy needs interactive `supabase login`, user runs the provided deploy command via `!` in-session.

---

## 7. Open decisions / risks

- **Tags vs spaces:** start by reusing space colors as the category filter; full tag system is additive (don't over-build in v2).
- **Revert-after-slot UX:** derived/non-destructive (resurface, don't delete the schedule) so an accidental pass-the-slot never loses the intended time.
- **Voice model:** on-device `SFSpeechRecognizer` (free, private) over cloud Whisper for v2.
- **Google write-back scope:** `calendar.events` (read+write) chosen so two-way works; if user prefers read-only first, narrow to `calendar.readonly`.
- **Branch:** continue on `feat/daily-driver-v1` or cut `feat/daily-driver-v2`? (Recommend a fresh `feat/daily-driver-v2` so v1 stays a clean reviewable unit.)

---

## 8. Terminal state

After user reviews/approves this spec → invoke **writing-plans** to produce the detailed per-task implementation plan, then execute Phase 0 → 3. User controls the push.
