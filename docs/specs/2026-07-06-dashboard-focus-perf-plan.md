# Dashboard redesign · Focus build · Perf fixes — working plan (MASTER)

**Date:** 2026-07-06 · **Status:** DIRECTION LOCKED (evening) — skin = paper-minimal mockup
(artifact version `paper-minimal-v4-12h`). Phase docs: `2026-07-06-phase1-reskin.md` ·
`2026-07-06-phase2-features.md` · `2026-07-06-phase3-layout.md`.
**Locked 2026-07-06 pm:** 12-hour clock · Mac-first (mobile parked) · flat paper skin applied
app-wide; outlined "card" containers reserved for instruments (calendar, timers, pickers) only.
**Sources:** Jonah's Figma concept, Drew's edits, retrofuturism refs (Spinlab / Litverse), code recon + perf audit (Opus agents, 2026-07-06)

---

## 1. Dashboard redesign mockup (ACTIVE — design gate)

Standalone HTML artifacts only; no app code until approved.

**Direction:** editorial paper / notebook feel with a light retro-futurist accent — boxy ink-outlined
modules, mono labels, chunky serif display — but restrained ("not too far"). Must stay recognizably
Atlas: real sidebar (Dashboard / Calendar / Focus + Spaces), real space colors (School `#5b9bd5`,
Personal `#5fb98e`, Side Project `#b48ad9`), clay accent `#d97757`, real shortcuts (⌘K / ⌘⇧K).

**Locked decisions (Drew, final round 2026-07-06 pm — target is Jonah's "no black clock" concept +
reMarkable paper feel):**
- Clock: **plain digital numerals directly on paper — no dark panel, no boxes, no flip.**
  Big ink HH:MM, orange colons, seconds lighter/grey, all mono.
- **No dark gradients anywhere.** Flat paper surfaces; separation via hairlines, not cards/shadows.
- **Notes are plain list rows** (serif title · mono date · space tag) — NOT outlined cards.
  "Don't outline everything." The ONE outlined box Drew liked: the **calendar container** — keep it.
- **No section numbering**; sections = mono uppercase label + hairline rule.
- **Right rail:** outlined mini calendar (top) → "TODAY" agenda under it (time · colored dot · title,
  NOW row highlighted, "Full view ›" link). Schedule lives here now, not under the tasks.
- Calendar stays a **date navigator**: click a day → Focus + agenda follow, "← Back to today".
- Greeting demoted to the title bar as tiny mono ("GOOD AFTERNOON" left, date right) — no big serif
  headline on the dashboard.
- Add-task: subtle "+ Add a task" text link (per the reference), not a boxed input.
- Done checkbox = solid orange square; task tags = tiny mono uppercase with soft wash, space colors.

**The real deliverable of the mockup = the repeatable style system, not the layout** (Drew: "we're
mainly looking for real style indicators that are repeatable to make the entire app consistent —
layout after"). The tokens the mockup demonstrates, to become the new `AtlasTheme`:
- Surfaces: paper `#f2efe6` base / `#f7f5ee` raised; NO card fills, NO shadows inside the window.
- Ink: `#211d17` primary · `#6f6a5e` secondary · `#9c968a` muted. Hairline = ink @ ~12%.
- Accent stays clay `#d97757` (deep `#b04f2f`) — used for: live/NOW, today, colons, done-state,
  active ticks. Never button fills.
- Type roles (repeat everywhere): mono = all numbers/dates/times + uppercase section labels
  (wide tracking); serif bold = note/content titles only; rounded sans = body/tasks/nav.
- Controls: square checkboxes; the only outlined container style is reserved for "instruments"
  (calendar, and later: timers, pickers).

**Artifacts:** analog concept → claude.ai/code/artifact/c2411b96-…; current concept (flip v1, being
replaced by boxed v2) → claude.ai/code/artifact/e29aefff-…

**After approval:** translate into SwiftUI on `DashboardView` (clock panel, mini-month navigator,
notes card, section relabels). Separate implementation plan at that point.

---

## 2. Task ↔ Note linking (ON HOLD — small)

**Current state (verified 2026-07-06):** cannot link a pre-existing note from
`TaskDetailView`. Model support already exists and is unused: `TaskItem.noteID`
(`AtlasCore/Sources/AtlasCore/Models.swift:176`) + `AppState.updateTask(...noteID:)`
(`Atlas/Data/AppState.swift:639-645`). Calendar events already ship the exact UI
(`CalendarEventDetailView.linkedNoteSection`, `CalendarEventDetailView.swift:184-217` — a Menu over
all notes + "New note…"). The task References section is NOT a note picker — it only lists
Drive-imported project references (`AttachReferencePicker.swift:95-98`).

**Plan:**
1. Mirror `linkedNoteSection` into `TaskDetailView` (reads/writes `TaskItem.noteID`). No schema change.
2. **Open-in-editor requirement (Drew, 2026-07-06):** clicking a linked note — on the task's linked-note
   row AND on `.docNote` reference rows — opens the **in-app corner-card editor**
   (`NoteCardOverlay`), never just a jump to the external Google Doc. `ReferenceRowView` already has
   "Edit in Atlas" for linked Docs; make the row's primary click do that, with "Open in Google Docs"
   demoted to a secondary action.

**Gotchas from recon:** references are project-scoped while notes are global (pick the event-style
global-notes scope); the `noteID` tag and the `ReferenceAttachment` join are two parallel systems
that don't reflect each other; `[[mentions]]` are display-only, not persisted backlinks.

---

## 3. Perf fixes (ON HOLD — small, high value)

From the 5-point audit (2026-07-06). Items 3–5 of the checklist verified CLEAN (URLSession gzip fine,
optimistic UI everywhere, landing is static on Vercel CDN). Two real problems:

**P1 — launch N+1 + serialized bootstrap (worst):**
- `loadCollabState()` awaits members per project (`Atlas/Data/AppState.swift:305-310`), and each call
  fetches the ENTIRE `project_members` table then filters client-side
  (`AtlasCore/Sources/AtlasCore/AtlasDB.swift:932-935`). P projects = P serial full-table GETs, re-run
  on every realtime change (`AppState.swift:283-291`).
- Bootstrap tail awaits 4 independent calls in series: profile → collab → Google → Canvas
  (`AppState.swift:213-220`).
- **Fix:** one `getAll("project_members")` grouped in memory (RLS already scopes rows); `async let`
  the bootstrap tail. `loadAll()` (`AtlasDB.swift:846-853`) already shows the concurrent pattern.

**P2 — first-run seed writes row-at-a-time:**
- `seedInitial` does one awaited POST per row across 6 loops (`AtlasDB.swift:1002-1009`); dozens of
  serial round-trips on a fresh account.
- **Fix:** PostgREST batch upsert — encode each table as one array body, 6 POSTs total, using the
  existing `upsertQuery`/`upsertHeaders` plumbing.

---

## 4. Focus mode build (ON HOLD — biggest track)

Current Focus = Pomodoro countdown only (`FocusView.swift`, `FocusViewModel.swift`), entered from the
sidebar; the dashboard `FocusCard` is decorative (no action wired — `DashboardView.swift:318-341`).

**Spec draft:**
- **Enter:** sidebar Focus → "Start focus" takes the window into true macOS fullscreen; also wire the
  dashboard FocusCard. Esc / End session exits.
- **Layout:** timer shrinks to a corner; center is the work surface.
- **Notes access:** ⌘K inside Focus opens the existing command palette scoped to notes; picking one
  opens it in the chromeless corner-card editor (`NoteCardOverlay` — exists). Doc-linked notes keep
  two-way write-back for free.
- **Quick sticky note:** `addNote` with no project and no Doc pairing — instant local note. Optional
  later filing: pair to a Doc via the existing `DriveOnePickFlow` ("file it" is a deferred action,
  never a creation blocker).
- **Expanded notes surface:** `NotesListView` (exists, deliberately unwired from nav) becomes the
  full-screen notes page INSIDE Focus only — per Drew, notes do NOT get a sidebar item.
- **Menu-bar timer (Drew, 2026-07-06):** the existing `MenuBarExtra` (`AtlasApp.swift:42-47`) shows
  the live countdown whenever a focus session is running (label swaps to `MM:SS`), and clicking it
  surfaces session controls — visible even when Atlas isn't frontmost.

---

## 5. Ideas backlog (captured 2026-07-06 — organize, not scheduled)

- **Arc-style auto-hide sidebar:** sidebar hidden by default; cursor at the left screen edge slides it
  out as an overlay; it retracts on mouse-leave. Feasible on macOS (track `NSEvent` mouse location /
  hover zone + overlay panel instead of `NavigationSplitView`'s pinned sidebar). Risks: discoverability,
  fighting `NavigationSplitView` — prototype as an overlay first. Drew: "idk if that works" — needs a feel test.
- **Two documents open + editable at once:** NOT possible today — one `@State editingNote` drives a
  single `NoteCardOverlay` (`ProjectDetailView.swift:32,99-100`). Idea: allow a second card (split or
  two floating cards). Needs an answer for save-conflicts on the same note (probably: same note can
  only be open once).
- **Global calendar popup:** a quick calendar overlay summonable from the menu-bar item (or a global
  hotkey, like ⌘⇧K capture already is via `HotkeyService`) that works over ANY app — glance at the
  week without switching to Atlas. Natural home: `MenuBarExtra` with `.window` style popover.
- **"Sync now" button for Doc-notes:** the google-sync cron runs every 5 min
  (`supabase/migrations/0008_google_sync_cron.sql`) and there is NO user-facing manual resync —
  `reloadReferences()` only refreshes the app from our DB, it never triggers a Drive pull. A small
  "Sync now" affordance on doc-note rows would just invoke the google-sync function on demand.
- **Multi-tab Google Docs (verified live 2026-07-06):** PULL is fine — `files.export text/markdown`
  exports ALL tabs, each tab title as an `# H1` heading (confirmed: Tab 2 edit landed in the
  "Fitness App" note body one cron tick after editing). WRITE-BACK is the risk: `drive-writeback`
  replaces the whole Doc via multipart markdown upload, and markdown has no tab concept — so saving
  from Atlas would almost certainly FLATTEN a multi-tab doc into one tab with H1 sections. Untested
  (deliberately — would destroy real tab structure). TODO before enabling write-back on tabbed docs:
  test on a scratch doc; likely fix = detect multiple tabs at import and mark the note read-only-ish
  or scope write-back to the first tab via the Docs API.
- **Mockup taste follow-ups:** espresso vs paper hero (see §1 open questions).

---

## 6. Observed bugs & non-UI gaps (logged 2026-07-06 pm — Drew's live testing; fix in Phase 2)

- **Note editor doesn't self-refresh.** Cron lands Doc changes in the DB every 5 min, but the app
  only re-reads on view load — Drew's Doc edit appeared only after navigating to another project and
  back. Fix ideas: periodic/`onAppear`+timer refresh while a doc-note is open, or a Supabase realtime
  subscription on `notes`; also make "Last synced Xm ago" live-update. (Related: "Sync now" button, §5.)
- **Underline doesn't render in the note editor.** The U toolbar button produces nothing visible.
  Root-cause candidate: Markdown round-trip — Markdown has no native underline, so it's dropped on
  save/render. Decide: support via HTML `<u>` in the round-trip, or remove the U button.
- **"Done" in the note corner-card hid the entire Atlas window** (app still running). Likely the
  overlay/panel dismissal is closing/ordering-out the main window. Reproduce + fix.
- **Seen in screenshot (not yet reported):** References error banner "Drive import didn't finish —
  Google sign-in failed: access_denied" on Calculus II. Investigate token/scope state.
- **Multi-tab Docs PULL confirmed good in-app** (tabs render as `# Tab N` sections — "handled
  perfectly" per Drew). Write-back flattening risk from §5 still stands.

---

## 7. Attack plan (Drew, 2026-07-06 — order locked)

**Now (this hour):** iterate the dashboard mockup until the style system is right. UI talk only;
everything else gets written down here, not built.

**Execution rules (Drew, 2026-07-06 evening):** run FULLY AUTONOMOUSLY once Drew signals go — no
mid-run check-ins or approval gates. Visual verification is Claude's job: build, launch the app,
and screenshot it directly (Drew explicitly authorized this; it supersedes the CLAUDE.md
"user must confirm UI" rule for this effort). Implementation subagents on **Opus**; Claude may
drop individual tasks to **Sonnet 5** where Opus is overkill (Claude's judgment). Phase-2 Wave 4
(gated ideas) stays EXCLUDED unless Drew/Jonah say otherwise. Floating overlays keep their shadows.

**When Drew's usage limits reset:**
1. **Phase 1 — Reskin & styling** → `2026-07-06-phase1-reskin.md`. Apply the locked tokens across
   the ENTIRE Mac app — repeatable style indicators first, consistency over layout. No layout moves.
2. **Phase 2 — Features & fixes** → `2026-07-06-phase2-features.md`. Everything: linking with
   open-in-editor, perf fixes, editor bugs, sync freshness, multi-tab guard, Focus mode, menu-bar
   timer, gated ideas.
3. **Phase 3 — Layout refinement** → `2026-07-06-phase3-layout.md`. Dashboard restructure to the
   locked mockup, then secondary screens.
