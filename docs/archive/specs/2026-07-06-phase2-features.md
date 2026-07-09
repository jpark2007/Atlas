# Phase 2 — Features & fixes ("everything")

**Date:** 2026-07-06 · **Status:** DRAFT — runs after Phase 1 (reskin), see
`2026-07-06-dashboard-focus-perf-plan.md` for the master plan and `2026-07-06-phase1-reskin.md` /
`2026-07-06-phase3-layout.md` for the neighbors. Mac app only (mobile explicitly parked).

Execution model: independent Opus agents on disjoint files, verified by
`xcodebuild … CODE_SIGNING_ALLOWED=NO` + E2E where present; UI behavior additionally needs Drew's
visual pass (build green ≠ UI works).

---

## Wave 1 — small, independent, high value

### 2.1 Task ↔ Note linking (with open-in-editor)
- Mirror `CalendarEventDetailView.linkedNoteSection` (`CalendarEventDetailView.swift:184-217`) into
  `TaskDetailView` as a LINKED NOTE section. Plumbing exists: `TaskItem.noteID` (`Models.swift:176`),
  `AppState.updateTask(...noteID:)` (`AppState.swift:639-645`). Global-notes scope (like events), not
  project-scoped references.
- **Open-in-editor rule (Drew):** clicking a linked note on a task, and clicking `.docNote` reference
  rows, opens the in-app corner-card editor (`NoteCardOverlay`) — "Open in Google Docs" becomes a
  secondary action (`ReferenceRowView` already has "Edit in Atlas"; make it the primary click).
- Verify: link a note from a task, click it, edit in the card, unlink. Build + visual pass.

### 2.2 Perf — launch N+1 + serialized bootstrap
- `loadCollabState()` awaits members per project (`Atlas/Data/AppState.swift:305-310`); each call
  fetches the whole `project_members` table then filters client-side (`AtlasDB.swift:932-935`);
  re-runs on every realtime change (`AppState.swift:283-291`). Fix: ONE `getAll("project_members")`
  grouped in memory (RLS already scopes rows).
- Bootstrap tail serializes 4 independent awaits (`AppState.swift:213-220`): profile → collab →
  Google → Canvas. Fix: `async let` (pattern already used in `loadAll()`, `AtlasDB.swift:846-853`).
- Verify: cold-launch time before/after with several projects; realtime edit doesn't re-fetch P times.

### 2.3 Perf — batch the first-run seed
- `seedInitial` does one awaited POST per row across 6 loops (`AtlasDB.swift:1002-1009`). Fix: one
  array-body POST per table (PostgREST batch upsert) using existing `upsertQuery`/`upsertHeaders`.
- Verify: fresh-account first launch; row counts identical.

### 2.4 Note editor bugs (from Drew's 2026-07-06 testing)
- **Underline lost:** the U toolbar button produces nothing persistent — Markdown round-trip has no
  underline. Decide & implement: support `<u>`/HTML in the round-trip, or drop the U button.
  (Data-correctness bias: never silently eat formatting a user applied.)
- **"Done" hides the app:** dismissing the corner-card editor hid the entire Atlas window (app still
  running). Reproduce; suspect window/panel ordering in the overlay dismissal or
  `CapturePanelController`-style panel misuse. Fix + visual pass.
- **Drive import `access_denied` banner** on Calculus II references — investigate token/scope state
  (Google sign-in failed during import). May be stale-token UX rather than a code bug; decide
  re-auth affordance.

## Wave 2 — sync robustness

### 2.5 Doc-note freshness in the app
- Cron pulls Drive→DB every 5 min, but the app only re-reads on view load (Drew observed a Doc edit
  appear only after navigating away and back).
- Add: (a) refresh while a doc-note is open/visible — timer on `NoteCardOverlay`/project view or a
  Supabase realtime subscription on `notes`; (b) live "Last synced Xm ago" label; (c) a **Sync now**
  button on doc-note rows that invokes the `google-sync` function on demand.

### 2.6 Multi-tab Docs write-back guard
- PULL is fine (verified live: tabs export as `# Tab N` sections). WRITE-BACK would flatten a
  multi-tab Doc into one tab (whole-doc Markdown replace in `drive-writeback/index.ts:204-220`).
- Test on a scratch multi-tab Doc; then either scope write-back to the first tab via the Docs API or
  detect tabs and block write-back with a clear warning. Never silently flatten.

## Wave 3 — Focus mode build

### 2.7 Focus mode (full spec in master plan §4)
- True macOS fullscreen from Focus + wire the dashboard `FocusCard` (currently decorative,
  `DashboardView.swift:318-341`); Esc/End exits.
- Timer shrinks to a corner; ⌘K inside Focus = command palette scoped to notes; picked note opens in
  the corner-card editor; quick sticky note = `addNote` with no project/Doc (file-to-Drive later via
  `DriveOnePickFlow`); `NotesListView` (exists, unwired) becomes the expanded notes surface inside
  Focus only — nothing new in the sidebar.
- **Menu-bar timer:** existing `MenuBarExtra` (`AtlasApp.swift:42-47`) label shows live `MM:SS`
  during a session, with session controls in the menu.

## Wave 4 — gated ideas (need Drew+Jonah approval before build)

- **Arc-style auto-hide sidebar** — hover the left edge to slide the sidebar over content; prototype
  first (fights `NavigationSplitView`; discoverability risk).
- **Two note editors at once** — today a single `editingNote` drives one card
  (`ProjectDetailView.swift:32,99-100`). Needs same-note-conflict answer before build.
- **Global calendar popup** — menu-bar (or global-hotkey) calendar overlay that works over any app;
  natural home: `MenuBarExtra` window style. Pairs with the menu-bar timer work in 2.7.
