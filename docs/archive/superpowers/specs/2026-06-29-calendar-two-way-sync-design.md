# Calendar ⇄ Google: Two-Way Sync, Work-Blocks & Deadlines — Design

_Status: design, **reviewed** (data-loss blockers closed below), awaiting user sign-off. Date: 2026-06-29._

## Goal

Make the Atlas calendar a **true two-way calendar client** with Google: create / edit /
delete on either side and it reflects on the other, promptly, without leaving and
re-entering the tab. Layer in **work-blocks** (dragging a task onto the grid creates a
time block that also lives on Google) and **deadlines** (a task's due date shown as a
distinct marker, with an overdue state) — while keeping Atlas's own store as the brain.

This builds on the existing one-way write-back (Atlas → Google), which already works.

## Decisions (locked with the user)

1. **Per-origin source of truth, Atlas store is the brain.** Every event/block records
   where it was born (`source`). Atlas's store (Supabase) stays the source of truth for
   Atlas-origin items and for everything non-event (tasks, projects, notes). Google is a
   **two-way synced mirror**, not a replacement store. Rationale: Google Calendar only
   holds *events*; tasks/projects/notes have no home there, and the planned AI brain + iOS
   app need a unified local store to query without hammering Google's API.
2. **Editable both ways.** Google-origin events become editable inside Atlas; edits PATCH
   back to Google. (Recurring editing is Phase 3 — see Phasing.)
3. **Conflict = newest edit wins**, by Google's `updated` timestamp (consistent with the
   notes-sync decision).
4. **Multiple work-blocks per task.** A task can be time-blocked in several places
   (e.g. "Study midterm" Mon 3pm *and* Wed 7pm). Requires a new `WorkBlock` model.
5. **Work-blocks sync to Google; deadlines stay Atlas-native for now.** Google has no
   "deadline" concept — it would render as a plain event there, defeating the distinct
   look. An optional "mirror due dates to Google as all-day flags" toggle is deferred.
6. **Drag is never blocked by a deadline.** You can drag a work-block past a task's
   deadline; it simply goes **overdue** (red) rather than being prevented.
7. **Missed work-block → back to the tray, flagged overdue.** When a block's window
   elapses with the task undone, the block leaves the grid and the task returns to the
   unscheduled tray **shown red / "overdue"** (not silently, as it does today).
8. **The "New events go to" picker becomes a single "Sync calendar with Google" toggle.**
   On = full two-way sync to the **primary** calendar. Off = Atlas-only.
9. **Stop swallowing sync errors.** Track and surface a last-sync status so silent
   failures (the earlier "writes vanished" confusion) can't recur.

## Non-goals / deferred

- Apple Calendar write-back (EventKit write).
- Non-primary / multiple Google calendars.
- Push notifications via `events.watch` webhooks and `syncToken` incremental sync
  (performance optimizations; full-window re-list is fine at this scale).
- Mirroring deadlines to Google.
- Gmail / Drive integration (tracked separately in `docs/archive/google-integration-v2.md`).

## The three calendar item types (visual language — approved via mockup)

One rule: **things with duration are rectangles; deadlines are moments (flags / hairlines).**

| Type | Looks like | Source data | Editable | Syncs to Google |
|------|-----------|-------------|----------|-----------------|
| **Event** | Solid block, colored by space/source | `CalendarEvent` (`.atlas` or `.google`) | Yes (both origins) | Yes |
| **Work-block** | Translucent + hatched + checkbox | `WorkBlock` (belongs to a `TaskItem`) | Yes (drag/resize) | Yes (as an event) |
| **Deadline** | Flag-pill (due-that-day) or dashed hairline (due-at-time) | `TaskItem.dueDate` | Via editing the task only; not draggable | No (for now) |

**Overdue** (red): a deadline whose `dueDate` has passed with the task undone; an
overdue task's deadline marker and its tray row both go red. A missed work-block returns
to the tray flagged overdue (decision 7).
**Done**: a checked-off task's deadline clears; completed work-blocks fade.

## Data model changes

### New: `WorkBlock`
```
struct WorkBlock: Identifiable {
    var id: UUID
    var taskID: UUID            // owning task — title & space borrowed from it for Google
    var start: Date
    var durationMin: Int        // default 60, resizable
    var googleEventId: String?  // set after mirroring to Google (as an event)
    var googleUpdated: Date?    // newest-wins fields, same as CalendarEvent
    var localUpdatedAt: Date?
    var source: EventSource     // .atlas (born here) — origin tracking
}
```
- Replaces the single `TaskItem.scheduledAt` / `durationMin` with a one-to-many. A task
  is "scheduled" if it has ≥1 future work-block; "unscheduled" (tray) if it has none.
- Rendered on the grid as work-blocks; mirrored to Google as events using `googleEventId`
  as the join key, exactly like Atlas events. A `WorkBlock` has no title/all-day of its own
  — an adapter borrows the owning task's title/space when building the Google event body.
- **The reaper must namespace gids by type** (a vanished gid that belongs to a `WorkBlock`
  → delete the *block* and resurface the task per decision 7; one that belongs to a
  `CalendarEvent` → delete the *event*). Both tables share one gid namespace, so the
  reconciler looks the id up in both.

### `TaskItem`
- `dueDate: Date?` already exists → drives the **deadline** marker. No new field needed.
- `done`, `status` already exist → drive done/overdue derivation.
- Deprecate `scheduledAt` / `durationMin` in favor of `WorkBlock`. **This is a refactor, not
  a field swap:** `isEffectivelyUnscheduled(now:)` is a method *on* `TaskItem` reading these
  fields and must move to operate over the task's block collection. Every reader re-plumbs:
  `AppState.unscheduledTasks`, `schedule(taskId:at:)`, `AppState+Calendar.busyIntervals` /
  `suggestSlot`, `CalendarView.scheduledTaskEvents` + drop handlers, the **pure unit-tested**
  `AgendaBuilder.build`, and `Metrics`. Migration reality: only `scheduled_at` is persisted
  today (`TaskRow` has **no** `duration_min` column — `durationMin` is in-memory and lost on
  reload), so the backfill maps each persisted `scheduled_at` → one block; durations reset to
  the 60-min default. (Phase 2 work — listed here so the scope is honest.)

### `CalendarEvent`
- Add **two** timestamps, because newest-wins needs both (review B4): `googleUpdated: Date?`
  (Google's `updated`, last seen) and `localUpdatedAt: Date?` (stamped on every local edit).
  Without a local timestamp the reconciler can only detect "Google changed," not *which side
  is newer*, so a local edit could be clobbered by an older Google state. (`Note` already
  carries `updatedAt`/`docSyncedAt` for exactly this — mirror the pattern.)
- Add `isRecurring: Bool`, decoded from Google's `recurringEventId`/`recurrence`. The
  `GEvent` decoder currently decodes only id/summary/description/start/end — it must also
  decode `updated` and the recurrence marker.
- `googleEventId`, `source`, `isReadOnly` already exist; Google-origin **non-recurring**
  events flip `isReadOnly = false` (editable, syncs back) keeping `source = .google`.
  Recurring instances stay `isReadOnly = true` until Phase 3 (review S4).
- Stale-comment cleanup (review N1): `CalendarEvent.googleEventId`'s doc-comment still says
  it's memory-only/not persisted — migration `0003` + `EventRow.googleEventId` now persist
  it; correct the comment so future readers don't reason from the wrong premise.

### Migrations (`supabase/migrations/`)
- `work_blocks` table: `id, task_id (fk), start, duration_min, google_event_id`.
- `events`: add `google_updated timestamptz` (and reserve `etag text` for later).
- `0003_events_google_event_id.sql` (already applied) stays.

## Sync engine

A dedicated `CalendarSyncService` owns reconciliation; `GoogleCalendarService` stays the
thin HTTP layer. `AppState` calls into the sync service rather than holding sync logic.

- **Join key:** `googleEventId`. **Origin:** `source` (`.atlas` we own & push; `.google`
  Google owns, we may edit & push back).
- **Push (Atlas → Google):** on create/update/delete of an Atlas-origin event or
  work-block, mirror to Google (events already done; add work-blocks). Store returned id.
- **Pull (Google → Atlas):** list the visible window `[timeMin, timeMax)` and reconcile,
  **matching on `googleEventId` and updating the existing row in place** — never insert the
  hashed-UUID read copy beside the Atlas-origin row (that yields two DB rows per event;
  review B3). The current view-level gid dedupe in `CalendarView` is **removed** — the
  reconciler becomes the single owner of identity.
  - Google id we don't have → insert (`source = .google`, editable unless recurring).
  - Google id we have, with `updated` newer than stored `googleUpdated` **and** no newer
    local edit (`localUpdatedAt`) → update local. If both changed, **newest `updated` wins**.
  - **Deletion detection — scoped, or it destroys data (review B1/B2).** Treat an event as
    "deleted on Google" only when **all** hold: (a) its `start` is inside the fetched
    `[timeMin, timeMax)` window — events outside the window are absent from the listing and
    must **not** be reaped; (b) it has a non-nil `googleEventId`; (c) that id was stored
    *before* this pull's fetch began — an id that landed mid-pull (pending push / backfill)
    is **not** reaped. Only then delete locally. Deleting an Atlas-origin mirror deletes the
    Atlas event too — **this reverses `calendar-writeback-plan.md` decision 2 ("the Atlas
    copy never disappears")** (review S1); intended, but flagged explicitly.
- **Editing Google-origin events:** drop `isReadOnly`; edits PATCH back via `updateEvent`.
- **Auto-refresh cadence:** pull on calendar appear, on app/window focus, and every ~60s
  while the calendar is visible. No webhooks (deferred). Full-window re-list each pull
  (simplest correct deletion detection without `syncToken`). An existing 60s clock
  (`AppState.startClock`) only bumps `now` today — decide whether to piggyback the pull on
  it or run a separate timer (review N4).
- **Backfill:** when the toggle is switched on, push every Atlas-origin event and
  work-block lacking a `googleEventId`. Backfilled ids are subject to the same
  pending-push reap guard above so an in-flight pull can't wipe them.
- **Observability:** a published `lastSync: (Date, ok | error(message))` on the new
  `CalendarSyncService` (review N3 — it has no home today), surfaced as a small indicator
  in Settings / the calendar header; errors retried next cycle. No silent `try?` swallow
  on the sync path.

## Settings change

Replace the `calendar.main` picker (Atlas only / Atlas + Google) with one toggle:
**"Sync calendar with Google"** (requires Google connected). On = two-way sync to primary.
**Two flags exist today and the toggle must subsume both (review S6):** writes are gated by
`calendar.main == "Google"` (`AppState.shouldWriteBack`) and reads by `calendar.google.enabled`.
Update `shouldWriteBack`, the picker block, and the read gate together so the write and read
paths can't drift. Migrate the old `calendar.main == "Google"` value to the toggle's on-state.

## Phasing (implementation order)

**Phase 1 — Core two-way event sync.** Pull Google changes incl. deletes; Google-origin
events editable; newest-wins conflict; auto-refresh; backfill; the single toggle; surfaced
sync errors. Recurring events are shown **read-only** in this phase. _Delivers the
"edit/delete anywhere, shows up fast" feel._ **Acceptance gate — the four reconciler-safety
items are blockers, not niceties:** window-scoped deletion (B1), pending-push reap guard
(B2), in-place gid match + dedupe relocation (B3), local-edit timestamp for newest-wins
(B4). Phase 1 is *only* a `CalendarEvent` change (`googleUpdated` + `localUpdatedAt` +
`isRecurring` + decoder) — it does **not** depend on the `WorkBlock` model, so it ships and
is tested on its own.

**Phase 2 — Work-blocks + deadlines + overdue.** `WorkBlock` model (multiple per task);
drag-task-to-grid creates a block that syncs to Google; deadline markers (pill / hairline)
from `dueDate`; overdue + missed-block-to-tray behavior; resizable blocks.

**Phase 3 — Recurring two-way editing.** "This event" vs "whole series" edit/delete of
recurring Google events, RRULE handling, syncing each back. Isolated last because it is
the highest-risk surface.

**Decomposition (review).** This umbrella doc holds the full vision and the corrected model;
each phase is built and tested before the next, and gets its **own implementation plan**
(via writing-plans) rather than one giant change. We write and execute the **Phase 1 plan
first** — it is self-contained (no `WorkBlock`), and its four safety items above are its
acceptance criteria. Phase 2/3 plans are written when we reach them.

## Error handling

- Local edits always succeed first (write-through), then sync — a sync failure never
  blocks the user.
- Sync errors are recorded in `lastSync` and shown; retried on the next cycle.
- Deletions on Google for items already gone are treated as success (no stuck retries —
  existing `deleteEvent` already does this).

## Testing

**Unit:** reconciliation (insert / update / delete detection from a Google listing),
newest-wins conflict, backfill selection, work-block ↔ Google event mapping, overdue and
missed-block derivation, settings migration.

**Manual (UI/behavior — not provable by a green build, per the working agreement):**
edit on Google → appears in Atlas without switching tabs; delete on Google → disappears
here; edit a Google-origin event in Atlas → reflects on Google; drag a task → a block
appears on Google; let a block lapse → it returns to the tray in red; deadline pill /
hairline render and clear on check-off.
