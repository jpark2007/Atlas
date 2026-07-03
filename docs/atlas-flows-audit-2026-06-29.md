# Atlas — App Flows & State Audit (2026-06-29)

A map of how Atlas works **today**. The app holds one in-memory source of truth (`AppState`) feeding a single routing enum (`Route`), with tasks as the durable unit of work and "work-blocks" as transient views of scheduled tasks. This documents current behavior and its conflicts — it is not a redesign and proposes no code.

## Conflicts / bugs to fix

1. **Elapsed work-blocks resurface (core defect).** `TaskItem.isEffectivelyUnscheduled` (`Models.swift:156-161`) returns `true` once a scheduled, not-done slot's end passes. Driven by the 60 s `now` clock, a deliberately-placed block **silently vanishes from the grid and reappears in the Unscheduled tray** at slot end. "Elapsed/passed/missed" has no state of its own — it is laundered through the "unscheduled" predicate.
2. **Two incompatible "overdue" keys.** Deadline pills/lines key off **`dueDate`** (correct per data-correctness rule); work-block disappearance keys off **`scheduledAt`**. A task due next week with a work-block this morning leaves the grid this afternoon — the strip says "not overdue" while the grid acts as if it were missed.
3. **Drop code fights its own predicate.** `schedule`/reschedule (`CalendarView.swift:555-565, 605-614`) bump any past-`now` drop forward to the next 15-min boundary so it won't instantly resurface — a deliberate past-time placement cannot stick.
4. **`.overdue` bucket is dead.** `TaskGrouping.byDueBucket` defines/tests an Overdue group but **no view consumes it** (only tests). Dashboard + tray use `bySpace`; the only on-screen overdue signal is the red deadline-pill color.
5. **Inconsistent `done` filtering.** `unscheduledTasks`, `scheduledWorkBlocks`, `deadlineEvents` exclude `done`; `TaskGrouping.bySpace` (Dashboard list, `UnscheduledTray.displayedTasks`) does **not** — done tasks linger (strikethrough) until fade-delete.
6. **Deadlines have no detail destination.** No pill/line/strip is tappable and `openSource` guards `!event.isDeadline` — non-interactive everywhere.
7. **Dead work-block edit path.** `CalendarEventDetailView` has a full work-block edit/Unschedule branch (Save → `updateScheduledTask`), but the grid routes work-blocks to `TaskDetailView` instead, so the branch is never reached live.
8. **Stale persistence comments (no functional bug).** `Models.swift:126-129` and `AppState.swift:504-507` claim Google ids are in-memory-only and re-create on relaunch. **False** — migrations 0003/0005 + `EventRow`/`TaskRow` persist and round-trip them.

## Navigation trails

Routing core: `Route` enum in `RootView.swift` (`.dashboard/.calendar/.focus/.project/.calendarDetail/.space/.task/.settings`); `RootView` is a `NavigationSplitView` switching on `state.route`. `calendarDetailItem` holds a **snapshot** of the clicked tile for `.calendarDetail`. Modals are separate booleans, not routes: `presentEventEditor`(+`eventEditorSeed`)`/presentSearch/presentCapture/presentGraph`.

**Trails from a TASK**

| Entry | Destination |
|---|---|
| Dashboard / Project / Space task row, ⌘K task result | **TaskDetailView** |
| **Work-block tile on grid** (`openSource`: `isWorkBlock` → `.task(id)`, id == task id) | **TaskDetailView** (not the event detail) |
| Unscheduled tray chip | **No nav** — click = toggle done; drag ≥6pt = schedule; context-menu = suggest/set due/schedule-to-hour |
| Agenda (List mode) task row | Jumps to **Day grid** for that day (no detail) |

`TaskDetailView` edits: toggle **done**, **due date** (+time, clearable), **project** (limited to space's projects via `setTaskProject`), **notes** (`updateTaskNotes`). Displays space + "Scheduled" chip but offers **no scheduled-time edit and no delete**.

**Trails from a CALENDAR item**

| Entry | Destination |
|---|---|
| Plain Atlas tile (left-click) | **CalendarEventDetailView** (editable: title/start/end/desc, link note, Save, Delete) |
| Read-only Apple/Google tile | **CalendarEventDetailView** (read-only: lock banner, fields disabled; Open Project/Note only) |
| Work-block tile | **TaskDetailView** |
| Deadline marker (pill/all-day/red dashed line) | **Nothing — non-interactive** |
| Event tile right-click | Inline `EventContextMenuModifier` (Edit→`EventEditorSheet`, Change Duration, Move, Delete; task-tile: Unschedule/Mark Done; read-only: disabled label) |
| Agenda event row, ⌘K event result | **CalendarEventDetailView** |
| "+ Add event" / tap empty grid / ⌘K New Event | **EventEditorSheet** (modal; Save → `addEvent`/`updateEvent`) |

`CalendarEventDetailView` reads mode from item flags (`isReadOnly`, `isWorkBlock`/`source`). Back → `.calendar`; Open Project → `.project`; Open Note → `NoteEditorView` sheet.

**Relations:** `SidebarView` rows set nav routes (space→`.space`, project→`.project`, profile→`.settings`, search→`presentSearch`). Dashboard `ScheduleCard` shows `todaysEvents` (events **+** work-blocks); Tasks section groups by space → TaskDetailView. Calendar grid composes `events(on:)` + `scheduledWorkBlocks` + `deadlineEvents` (Atlas-only) + read-only `externalEvents`; tray = `unscheduledTasks`, drop → `schedule(taskId:at:)`.

## Task & work-block lifecycle

**Core types (`Models.swift`)**
- `Space` → `[Project]`. Project's nested `assignments/notes/pinned/backlinks` are **display-only, NOT persisted** (`ProjectRow.toDomain()` returns them empty).
- `TaskItem` — the durable unit. `dueDate` (deadline), `scheduledAt` (nil = no work-block), `durationMin` (default 60), `done`, `status` (defined but **unused** for done logic), `workBlockGoogleEventId`.
- `CalendarEvent` — `source`(`.atlas/.apple/.google`) + `isReadOnly` stamped **once at ingest**, never inferred. A **work-block is NOT a stored event** — it's a synthesized view of a scheduled task.

**Lifecycle flow**

```
capture/addTask → TaskItem(scheduledAt=nil) → Unscheduled tray
   drag onto grid → schedule(): scheduledAt set, upsertTask, pushWorkBlockToGoogle
      → scheduledWorkBlocks(on:) synthesizes transient CalendarEvent(isWorkBlock) tile
   toggleTask(done) → drops from grid & tray; deleteTask removes after grace period
```

- **Create:** `applyCapture` routes by kind (task/event/note). `addTask` resolves `spaceColor`, appends, `upsertTask`.
- **Schedule:** custom `DragGesture` (native `.draggable` avoided), 15-min snap, past-drop bumped forward. `schedule()` sets `scheduledAt` + pushes Google.
- **Work-block tile:** `scheduledWorkBlocks(on:)` `compactMap`s scheduled/not-elapsed/not-done tasks → `CalendarEvent(id: task.id, isWorkBlock: true, source: .atlas)`, end = `scheduledAt + durationMin`. Feeds grid + `todaysEvents`.
- **Google mirror (`pushWorkBlockToGoogle`):** gated on `calendar.google.enabled` + connected. Updates if `workBlockGoogleEventId` set, else creates and stores id back. Sends only summary/description/start/end. **Deadline (`dueDate`) is never pushed** — deadlines stay Atlas-native.
- **Teardown:** `unschedule` clears only `scheduledAt` (keeps Google id, no delete); `unscheduleTask` does full teardown incl. Google delete. `toggleTask` flips done; `deleteTask` removes after grace.
- **Contrast — real events:** created via `addEvent`, stored as `EventRow`, mirrored via `pushNew/Updated/DeletedEventToGoogle`. Google-origin events live in non-persisted `externalEvents`, edited by patching Google directly, never written to the Atlas table.

## Overdue / done / passed / scheduled (current logic & conflicts)

| State | Defined | Keyed off | Notes |
|---|---|---|---|
| Unscheduled / "elapsed" | `isEffectivelyUnscheduled` `Models.swift:156-161` | `scheduledAt` | **Conflates never-scheduled with slot-passed** (Conflict 1) |
| Done | `TaskItem.done` `Models.swift:120` | — | only completion flag; `status` unused |
| Overdue (bucket) | `TaskGrouping.bucket` `:28-43` | `dueDate` | correct, but **dead in UI** (Conflict 4) |
| Overdue (pill color) | `deadlineEvents(on:)` `CalendarView.swift:364` | `dueDate` | red `danger` vs `accent`; only on-screen overdue signal |
| Scheduled tile | `scheduledWorkBlocks(on:)` `:276-296` | `!isEffectivelyUnscheduled` | drops elapsed blocks |

- **Clock:** `AppState.now` is `@Published`, bumped every 60 s (`startClock()`) — this is what auto-fires elapsed-slot recomputation.
- **Consumers:** work-blocks → grid `EventTile` (hollow circle, dashed border) + Dashboard `ScheduleCard`; `unscheduledTasks` → tray chips + drop guard; `deadlineEvents` → `DeadlineStrip`/`AllDayRowView` pill/red hairline; `done` → checkboxes/strikethrough; `TaskGrouping.bySpace` → Dashboard + tray lists (**does not filter done**).
- See Conflicts/bugs 1-5 above for the contradictions concentrated here (elapsed resurfacing, dual overdue keys, drop hack, dead bucket, inconsistent done filtering).

## Sync & persistence flow

Three stores, one in-memory truth (`AppState`):
- `events/tasks/notes/spaces/goals` — Atlas-owned → Supabase → Google.
- `externalEvents` — read pool (Apple EventKit + Google). **Never persisted, never written to `events`.**
- Supabase (`AtlasDB`) — durable; PostgREST upserts `on_conflict=id`, RLS-scoped to `auth.uid()`.

**Load (DB → AppState):** `bootstrap(db:)` → `loadAll()` fetches six tables in parallel, maps `*Row.toDomain()`. Empty `spaces` → seeds `MockData`. Colors re-derived from `spaceName` post-load (only `spaces.color_token` persists).

**Propagation (AppState → DB → Google):** every mutator = in-memory update → fire-and-forget `Task { try? await db?.upsert/delete }` → optional Google push. Failures swallowed so a local edit never blocks.
- Events: `addEvent/updateEvent/deleteEvent` → `upsertEvent`/`deleteEvent` → `pushNew/Updated/Deleted`.
- Tasks/work-blocks: all mutators `upsertTask`/`deleteTask`; `schedule`/`updateScheduledTask` → `pushWorkBlockToGoogle`; `unscheduleTask` → `deleteGoogleEvent`. Deadlines never pushed.
- **Write-back gate** (`shouldWriteBack`): `isConnected` AND `calendar.google.enabled` AND `!isReadOnly`. `backfillEventsToGoogle` pushes `.atlas && googleEventId==nil` when toggle flips on. Google delete treats 404/410 as success.
- **Editing Google-origin events:** mutate `externalEvents` optimistically, PATCH/DELETE Google, **never** write Atlas DB (would orphan a ghost row).

**Read + reaping (Google → AppState):** `loadAppleEventsIfNeeded()` is the single pull (on appear, date/mode/toggle/connection change, scenePhase, 30 s timer); rebuilds `externalEvents` from EventKit + `listEvents`.
- **De-dupe:** `ownGoogleIDs = events.googleEventId ∪ tasks.workBlockGoogleEventId` filtered out of fetched results.
- **Reaping safety (`CalendarSync.reapableEventIDs`, pure/testable):** only if `wantGoogle && googleFetchOK` (failed fetch ≠ "all deleted"); window-scoped (B1); pending-push guarded via pre-fetch snapshot (B2); only `.atlas` events with a `googleEventId` absent from `presentGoogleIDs`. Reap = `removeEventsLocally` (memory + DB, no echo back to Google).

**Attribution (set once at ingest):** Apple → `isReadOnly: true, .apple`; Google → `.google`, `isReadOnly = isRecurring`; Atlas → `.atlas, isReadOnly: false`. Apple/Google ids hashed to deterministic UUIDs (`stableUUID`, FNV-1a) to avoid re-fetch flicker.

**Migrations:** 0003 `events.google_event_id` · 0004 `events.note_id` + `tasks.notes/note_id/duration_min` · 0005 `tasks.work_block_google_event_id`. (Persistence comments in `Models.swift:126-129` / `AppState.swift:504-507` claiming in-memory-only are stale — see bug 8.)
