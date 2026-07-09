# Canvas ICS Sync — Design

**Date:** 2026-07-01
**Status:** Design — approved in concept, pending written review
**Supersedes:** the token/OAuth connection approach in [05-canvas.md](./05-canvas.md)

## Problem

Atlas needs to read a student's Canvas assignments + due dates into the unified calendar. The existing integration (`CanvasService` + Jonah's `AppState+Canvas.syncCanvas`, commit `a0e36ac`) uses the **Canvas REST API with a personal access token**. Both target schools — **Rutgers and Princeton — disable student-generated access tokens** at the admin level (confirmed in-app: *"Your Canvas administrators have chosen to limit your ability to generate your own access token"*). So the token path returns zero data for our actual users, and Canvas policy forbids asking other users to paste personal tokens into a multi-user app anyway.

We need a connection method that (a) works on locked-down student accounts with no admin involvement, (b) is read-only, (c) is simple.

## Solution: the Canvas Calendar Feed (ICS)

Every Canvas user has a private per-user **calendar feed URL** (Calendar → "Calendar Feed"), e.g. `https://canvas.rutgers.edu/feeds/calendars/user_<secret>.ics`. The long token in the URL *is* the auth — no login, no access token, and **admins cannot disable it** (core Canvas feature). It returns an iCalendar (ICS) file of the user's assignments and calendar events. Works identically on Drew's Rutgers account and Jonah's Princeton account, today, with zero setup beyond pasting the URL.

### What we get / don't get
- **Get:** assignment **name**, **due date/time**, a **link** back to the Canvas assignment, the owning **course** (from the assignment URL's `/courses/:id/`), and course calendar **events** where present.
- **Don't get:** grades, submission status, to-do items, assignments with **no due date**, the "assigned/posted" date, and reliably the human course **name**. The "new assignment posted" gap is a separate future path (Canvas notification emails via the planned Gmail integration) — out of scope here.

## Product shape (decisions from brainstorm)

Three layers, in priority order:

1. **Floor — show everything (default, zero-config).** Once the feed is connected, *every* assignment appears as a **read-only deadline** in the unified calendar, labeled by course. No project setup required. This is the always-works baseline and mirrors how Atlas already treats Apple/Google as live read-only sources.

2. **Linking — course ↔ project (explicit, auto-suggested — "option 1").** A course can be linked to an existing project. Atlas *suggests* a match (reusing Jonah's normalized course-code / name matcher) and the user **confirms or overrides** via a picker listing the courses found in the feed. Linked assignments additionally surface under the project, where they can be checked off and dragged to schedule work time. The link is an explicit binding stored by **course id** — no fragile re-matching each sync, survives course renames.
   - **Display vs. match:** a project keeps its friendly **display name** ("nickname"). Matching no longer depends on that name — the explicit link is the binding. (This realizes the "real title vs. nickname" idea as a *link* rather than a hidden text field, so you never have to know Canvas's exact official course title.)

3. **Setting — "Canvas assignments to show": All courses (default) / Only linked courses.** The clean switch between the floor (all) and a tighter linked-only view. Default = All, so it works the instant you connect.

## Architecture

Canvas becomes a **third live, read-only calendar source**, alongside Apple (EventKit) and Google — the same pattern already in `CalendarView.loadAppleEventsIfNeeded()`.

### Components
- **`CanvasFeedService`** (repurposes `CanvasService`): given the stored feed URL, fetch the ICS over HTTPS → `[CanvasFeedItem]`. No token, no write-back.
- **`ICSParser`** (new, pure/testable): iCalendar text → `[CanvasFeedItem]`. Handles `VEVENT`, `UID`, `SUMMARY`, `DTSTART` (both `VALUE=DATE` all-day and timed forms), line unfolding, and `URL`/`DESCRIPTION` to extract `/courses/:id/`. No external dependency — a small hand-rolled parser is enough for this well-scoped format.
- **`CanvasFeedItem`** (model): `uid`, `title`, `dueDate: Date?`, `courseId: Int?`, `courseName: String?`, `url`.
- **Reused from Jonah (`a0e36ac`):** the assignment→`TaskItem` mapper and the code/name matcher. The two **Bearer-token REST fetchers are removed** and replaced by feed fetch + `ICSParser`.
- **Source model & representation:** add a `source` field to `TaskItem` and add `EventSource.canvas`. Then, unambiguously:
  - A Canvas **assignment** → a read-only `TaskItem` (`source = .canvas`, `dueDate` set), keyed by `uid`. The calendar already renders any task-with-`dueDate` as a deadline pill, so **one deadline per `uid`**. Unlinked assignments simply have no project; linking sets the project association. Reuses Jonah's assignment→`TaskItem` mapper directly.
  - A Canvas **calendar event** (class meeting, if present) → a read-only `CalendarEvent` (`source = .canvas`).
  - Everything Canvas is `isReadOnly = true`.

### Data flow
1. On launch / focus / 30s refresh / manual "Sync now" (same triggers as Apple + Google), `CanvasFeedService` fetches the feed URL.
2. `ICSParser` → `[CanvasFeedItem]`, keyed by stable `uid`.
3. Each item → a read-only **deadline** in the merged calendar, `source = .canvas`, labeled by course. **Upsert by `uid`** so re-syncs never duplicate (directly avoids the relaunch-dupe bug class already seen with work-blocks).
4. If the item's course is **linked** to a project, it also surfaces under that project.
5. Scheduling a Canvas deadline (drag to a slot) spawns a normal **Atlas-native work-block** linked by `uid` — the Canvas item itself stays read-only; we never write to Canvas.

### Persistence
- **Feed content is derived, not persisted** — re-fetched each session like Apple/Google events. Simplest, and honors read-only.
- **Atlas-added overlay persists**, keyed by `uid`: course→project links, and (for scheduled items) the work-block. Needed only once linking/scheduling land — deferred to Phase 2.

### Refresh & connection
- **Client-side**, consistent with existing calendar fetches. No scheduled Supabase Edge Function for v1 — the point of ICS is that there is no server-side secret to hold. (The feed URL is a read-secret, stored locally like the current Canvas host; a future server-side move is possible but not required.)
- **Settings UI:** replace the token/host fields with a single **"Canvas Calendar Feed URL"** paste field + "Sync now", plus the show-all / only-linked toggle.

## Error handling
- Bad/expired feed URL or network failure → surface via existing `lastCanvasSyncError`; **keep last-good items on screen** (don't blank the calendar on a transient failure), mirroring the Google fetch's "skip reaping on error" safety.
- Malformed `VEVENT` → skip that item, keep the rest; never discard the whole feed for one bad line.
- Empty feed (e.g. no classes posted yet — Drew's current state) → valid, shows nothing, no error.

## Testing
- **`ICSParser` unit tests** against a checked-in fixture `.ics` (all-day due date, timed due date, event with course URL, folded lines, malformed `VEVENT`). Highest-value, fully deterministic.
- **Matching/auto-suggest tests** for the course→project suggester (`CS201`==`CS 201`, name match, no-match), following the `CalendarSyncReapTests` pattern.
- **Dedup test:** same feed parsed twice → no duplicates (upsert by `uid`).
- UI/behavior (picker, calendar rendering) verified manually per project rule.

## Non-goals (v1)
Grades, submission status, to-do items, write-back to Canvas, robust class-meeting recurring events (only if cleanly present in the feed), server-side feed storage, and the "new assignment posted" email path.

## Open dependency (confirm before/at build)
The exact ICS **course-name** representation. Course *id* is reliably in the assignment URL; the human-readable course name and `SUMMARY` format vary by Canvas config and need eyeballing against a **real feed**. Drew's feed is currently empty (fall classes not yet posted) — confirm when classes drop or against a sample. Parser degrades gracefully (fall back to `Course <id>` when no name is present).

## Reuse & migration summary
- **Keep:** `syncCanvas` orchestration shape, course→project matcher, assignment→`TaskItem` mapper, `lastCanvasSyncError`, launch/connect trigger wiring (`a0e36ac`).
- **Remove/replace:** `CanvasService.fetchCourses` / `fetchAssignments` (Bearer-token REST) → feed fetch + `ICSParser`; token/host Settings fields → feed-URL field.
- **Add:** `EventSource.canvas`, `TaskItem.source`, `ICSParser`, `CanvasFeedItem`, course-link storage, show-all / only-linked setting.

## Implementation phasing (for the writing-plans step)
- **Phase 1 — Floor:** feed-URL field + `ICSParser` + `CanvasFeedService` + render all assignments as read-only Canvas-sourced deadlines (ephemeral, upsert by `uid`). Ships the core value to both users.
- **Phase 2 — Linking + setting:** auto-suggested course picker, project-link storage, all / only-linked toggle, overlay persistence for scheduling/done.
