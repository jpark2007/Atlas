# Atlas — Calendar Handoff (2026-06-29)

State of the calendar work, and the open issues that need a future review/research/fix
pass (by subagents). **No agents have run on these yet — this doc is the brief for that.**

- **Branch:** `feat/calendar-two-way-sync-phase1`, pushed to `origin/main` (latest: `0a34052`).
- **Co-owner:** Jonah (jpark2007) pushes to `main` directly; we merge his commits in.
- **Migrations to run on Supabase (in order):** `0003_events_google_event_id.sql`,
  `0004_detail_page_fields.sql`, `0005_task_work_block_google_event_id.sql`.
  **Several open issues below only resolve once 0004 + 0005 are actually applied.**

---

## What shipped (recent work)

**Phase 1 — two-way Google Calendar sync.** Create/edit/delete on either side reflects on
the other. Delete-on-Google reaping with safety rules (window-scoped + pending-push guard,
unit-tested in `CalendarSyncReapTests`). One-off Google events editable in Atlas; recurring
stay read-only. Auto-refresh (30s + on focus). Single "Sync with Google" toggle. Surfaced
sync errors (`lastCalendarSyncError`).

**Phase 2 — work-blocks + deadlines.** Dragging a task onto the grid creates a *work-block*
(provisional dashed tile + checkbox) that mirrors to Google. Deadlines render from
`TaskItem.dueDate` as flag-pills in a "DUE" strip (day) / all-day row (week), red when
overdue, showing the time when set. Timed deadlines also draw a **red dashed hairline** on
the grid at the due time (`TimeGridView.DayColumnView`).

**Phase 3 — full-page detail.** Clicking a plain event opens `CalendarEventDetailView`
(edit title/time, description, tag-a-note). Clicking a **work-block** opens Jonah's richer
`TaskDetailView` (due/scheduled chips, project picker, notes) — now with an **editable due
date** (date+time sheet → `AppState.setDueDate`), a **space chip**, and "NOTES" renamed to
"DESCRIPTION".

**Merges with Jonah.** Task/space detail pages, tiered sidebar, dashboard task-grouping, AI
capture, ⌘⇧K keyboard fix, grid-drag-to-reschedule (his half + our restored wiring).

**Polish.** Dashboard work-blocks = hollow circles; ⌘K search finds tasks + events and the
sidebar field opens the palette; capture panel shadow/box tightened + brighter buttons;
persist `workBlockGoogleEventId` (migration 0005) to stop relaunch duplicates.

---

## Open issues (need subagent review → research → fix)

### 1. Work-block DUPLICATES still appear  ⚠️ highest priority
**Symptom:** a scheduled task shows on the grid twice — the dotted Atlas work-block AND a
solid blue Google read-back copy (e.g. "wash laundry" ×2). Makes tasks look like events.
**Fix already shipped:** persist `TaskItem.workBlockGoogleEventId` via migration `0005` +
`AtlasDB.TaskRow` mapping, so the block PATCHES its Google event across relaunches and the
read-back de-dupe (`CalendarView.loadAppleEventsIfNeeded`, `ownGoogleIDs` unions the task
gids) can match.
**Still reported duplicating — investigate, in order:**
1. **Is migration `0005` actually applied + app relaunched?** If the `work_block_google_event_id`
   column is missing, `db.upsertTask` likely *fails the whole upsert* (PostgREST rejects the
   unknown column) → the gid never persists → dupes continue. Confirm the column exists and
   that `upsertTask` succeeds (check for swallowed `try?` errors in `AppState`).
2. **Pre-existing Google duplicates** from earlier sessions stay until deleted by hand — the
   fix only prevents *new* ones. Confirm whether the visible dupes are old cruft vs newly
   created this session.
3. **ID match in the de-dupe:** verify the Google `event.id` read back EXACTLY equals the
   stored `workBlockGoogleEventId` (format/casing). If `pushWorkBlockToGoogle` stores a
   different id than `listEvents` returns, the union never filters it.
4. Consider a one-time cleanup routine (scan primary calendar for same-title/same-time
   work-block events and de-dupe) — out of scope until root cause confirmed.
**Files:** `AppState.swift` (pushWorkBlockToGoogle, schedule, upsertTask path),
`AtlasDB.swift` (TaskRow), `CalendarView.swift` (dedup), `GoogleCalendarService.swift`.

### 2. Overdue / done semantics are wrong
**Rule the user wants:** a task is **OVERDUE only when its actual `dueDate` passes** — NOT
when its scheduled work-block time passes. A task is **DONE only when checked off**. Passing
the *scheduled* time is neither overdue nor done.
**Current behaviour:** work-block "missed time" is conflated with resurfacing (see #3); the
deadline pill/line already key off `dueDate` (correct). Audit everywhere that infers
overdue/done and make sure it keys off `dueDate` for overdue and `done` for completion only.

### 3. A passed work-block should STAY dotted (marked "passed"), not vanish
**Symptom/want:** when a scheduled work-block's time elapses and it isn't done, it should
**stay on the grid as the dotted work-block, just visibly "passed"** (dimmed / struck) — not
disappear or bounce back to the tray.
**Current behaviour:** `TaskItem.isEffectivelyUnscheduled` (Models.swift) returns true once
the slot elapses unmet, so the block drops off the grid and resurfaces in the Unscheduled
tray. This directly conflicts with the desired "stays dotted, marked passed."
**Decision needed:** separate three states cleanly — *scheduled-time passed* (visual: dim
the dotted block, keep it on the grid), *overdue* (dueDate passed → red, see #2), *done*
(checked). Then implement the "passed" visual + stop the resurface-on-elapse for work-blocks.

### 4. Crowding when multiple deadlines/blocks are close together
**Symptom:** several deadline hairlines + "Due · title" labels stack on top of each other
near the same time (e.g. a 5 PM cluster), and the DUE strip pills can crowd horizontally.
**Want:** a layout strategy for density — e.g. offset/stack overlapping labels, collapse a
cluster to a count ("3 due"), or a combined marker; and wrap/scroll the strip pills.
**Files:** `TimeGridView.swift` (deadline line ForEach + `DeadlineStrip`), `AllDayRowView.swift`.

---

## Smaller follow-ups
- Deadline color: the **line** is always red (stands out); **strip pills** stay overdue-aware
  (accent upcoming / red overdue). Confirm that split is the intended final design.
- `TimeGridView` `body` triggers a SourceKit "type-check too complex" warning in isolation —
  builds fine via xcodebuild, but worth breaking up if it ever fails a real build.
- 226→227 unit tests green; all the above are UI/behaviour, not unit-covered — they need
  visual confirmation per the working agreement.
