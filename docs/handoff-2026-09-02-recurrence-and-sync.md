# Handoff — repeating events + six sync fixes (2026-09-02)

**Merged to `main` in [PR #5](https://github.com/jpark2007/Atlas/pull/5) (`f371b84`). Two deploy steps are still outstanding, and their ORDER matters — see §1 first.**

Two independent pieces of work landed together: general-purpose repeating events (capture → real dated sessions), and six cross-device sync defects found by an audit of the iOS/Mac refresh paths. 280 Mac tests + 341 AtlasCore tests pass; both targets build.

---

## 1. STOP — deploy ordering (read before testing capture)

### 1a. The `capture` edge function is NOT deployed
The prompt changes are on `main` but the **live function is still serving the old prompt**. Merging does nothing to a Supabase edge function; it goes live only via:

```
supabase functions deploy capture
```

**Consequence for anyone testing right now:** type a repeating capture ("yoga every Tuesday until Dec 12") against the live backend and you get the OLD behavior. The code you are reading is not what answered the request. This is the single most likely thing to waste a reviewer's afternoon.

**Why it wasn't deployed with the merge:** once the new prompt is live, a repeating capture returns ONE item carrying `recurrence` instead of enumerated sessions. Installed builds decode that field as nil (it's optional — nothing crashes), but they would create a *single* event where they previously created several. So the intended order is:

1. Ship a Mac/iOS build containing this code, then
2. `supabase functions deploy capture`.

**If you need to test end-to-end BEFORE shipping,** that tradeoff flips: deploy the function, but everyone testing must be on a build from `main` at or after `f371b84`. Don't deploy while people are on older installed builds.

### 1b. Migration `0046` is not applied
`supabase/migrations/0046_event_recurrence.sql` adds `events.series_id` + `events.recurrence_rule` and a partial index. Additive, nullable, no backfill — existing rows are one-offs and correctly keep a null `series_id`, and clients that don't know the columns ignore them.

Safe to apply at any time, independent of 1a:
```
supabase db push
```
Until it is applied, a repeating capture will create the events in memory but the `series_id`/`recurrence_rule` columns won't persist, so scope editing breaks after a reload.

> Note for whoever runs these: as of 2026-09-01 the remote had migrations `0041`–`0045` applied whose files were not all in the repo. `0046` was chosen to clear that range. Run `supabase migration list` before assuming a version is free.

---

## 2. What repeating events actually do

**Scope: the GENERAL case only** — a standing meeting, a weekly shift, "gym every Tuesday". A class's schedule is deliberately NOT this. Classes stay with the School framework, where `SchoolCalendar.meetings(on:classes:term:)` derives meetings from `Project.meetingPattern`, term-bounded and break-aware. That is the better model for a class and it already existed; this does not replace or duplicate it.

Where both could draw the same block, `CalendarSync.collapsingDuplicates` collapses them at display time (same title, same instant), so the grid shows one block. **This is the seam most likely to produce a surprising bug** — if a repeated capture and a class meeting ever render twice, look there first.

### Design: materialized, not re-derived
A rule is expanded ONCE, at capture/save time, into real `events` rows sharing a `series_id`. There is no live RRULE the grid re-expands per render.

- **Why:** nothing downstream had to learn about recurrence — grids, agenda, search, availability publishing, and the Google/Apple mirrors all keep operating on plain dated rows. Cancelling one occurrence is just deleting a row, so per-occurrence exceptions are free and no later pass can resurrect them.
- **Cost:** a series must be bounded (`until`, `count`, or a 1-year default horizon capped at 400 occurrences — `RecurrenceRule.defaultHorizonDays` / `.maxOccurrences`), and changing a *pattern* after the fact means rebuilding rows rather than editing a field. The repeat picker is create-only for exactly this reason; an existing series shows its rule read-only.

### Three edge cases, each with a test in `RecurrenceRuleTests.swift`
- **DST** — occurrences re-apply wall-clock time per day rather than adding 7×86400s, so a 10 AM block doesn't slide to 9 AM after the November fallback. `testWallClockTimeSurvivesDSTFallback` asserts the UTC offsets really do differ across the boundary.
- **The phantom first session** — when a weekday set is given, IT governs, not the start date: a range opening on a Tuesday produces no Tuesday occurrence for an MWF pattern. This is a deliberate divergence from RFC 5545, where `DTSTART` is always an occurrence. `testStartDateThatIsNotAListedWeekdayIsNotAnOccurrence`.
- **Garbled model output** — unknown freq, junk weekday codes, negative interval, unparseable bound all normalize or drop in `RecurrenceRule.init?(capture:)`, the single validation seam between the LLM and the store. Anything unusable degrades to the plain one-off event, never a broken series.

### Where it lives
| What | Where |
|---|---|
| Rule, expansion, RRULE text, `SeriesScope` | `AtlasCore/Sources/AtlasCore/RecurrenceRule.swift` |
| Wire type from the model | `AtlasCore/Sources/AtlasCore/AtlasAI.swift` (`CaptureRecurrence`) |
| Prompt: pattern vs. dated-list | `supabase/functions/capture/index.ts` |
| `series_id` / `recurrence_rule` | `AtlasCore/.../AtlasDB.swift` (`EventRow`), migration 0046 |
| Batch upsert, scoped series delete | `AtlasCore/.../AtlasDB.swift` (`upsertEvents`, `deleteEventSeries`) |
| Series CRUD + scope | `Atlas/Data/AppState.swift` (`addEvents`, `updateSeries`, `deleteSeries`) |
| Capture → sessions | `Atlas/Data/AppState+Capture.swift` (`applySeries`) |
| Repeat picker | `Atlas/Views/Calendar/RecurrencePicker.swift` |
| Scope dialogs, series badge | `Atlas/Views/Calendar/CalendarEventDetailView.swift` |
| iOS parity | `AtlasMobile/Views/Capture/CaptureView.swift`, `CaptureItems.swift` |

### Needs a visual pass (a green build does NOT prove these)
Per §4 of the working agreement:
- The **repeat picker** in the New Event sheet — cadence menu, weekday chips, the "Ends" toggle + date, and the live summary line ("Every Mon, Wed & Fri until Dec 12 · 44 events").
- The **scope dialogs** on the event detail page — editing or deleting one session of a series should prompt this / this-and-following / all, and write nothing until a choice is made.
- The **series badge** in the detail header.
- **Undo of a repeating capture** — one correction chip stands for the whole series and should take back every session, not strand 43 of them.

---

## 3. The six sync fixes

All six were live on `main` before this PR; each was confirmed against the actual code, not inferred.

1. **The Mac stopped refreshing for an entire session.** `Atlas/Data/AppState.swift` — `isEditInFlight` reads `calendarDetailItem != nil`, but the sidebar sets `route` directly without clearing it. So opening one event detail and then clicking anything in the sidebar suppressed EVERY background re-pull (the 5-minute timer AND `didBecomeActive`) until relaunch, with nothing on screen indicating it. `route` now has a `didSet` that clears the item, and a tick deferred by an open editor retries in 20s instead of waiting out the full interval.
2. **iOS had no periodic refresh at all** — only a scene transition or a pull-to-refresh. A phone left open on the Schedule tab never saw a Mac edit or anything the Google (5 min) / feed (15 min) crons wrote. Added a 5-minute foreground poll (`MobileStore.startForegroundPolling`), started/stopped from `scenePhase`.
3. **iOS dropped a refresh entirely when a write was in flight**, and never retried. Foreground the app, tap a task done within the first second, and incoming changes were lost for the session. Now recorded as `refreshDeferred` and drained by `persist` when the last mutation settles.
4. **A failed refresh kept the stale snapshot and scheduled nothing** — no spinner, no banner, looks fully loaded. Now retries 3× with backoff.
5. **The Schedule day-grid had no pull-to-refresh** (only the list did), and a long-press to place a task drops you into grid mode permanently — so a user could end up with no way to force a re-pull.
6. **`getAll` was unpaged.** PostgREST clamps every response to `db-max-rows` (1000 on Supabase) and reports it only in a header, so past ~1000 rows data silently stops loading with no error. Now pages over a total `(order, id)` sort. Newly relevant because one repeating capture can add dozens of event rows at once.

Also: iOS wrote `space_name` without `space_id` in four places (`ItemDetailSheet`, `ManualAddSheet`, `CaptureView`). The Mac treats `space_id` as authoritative, so an event added on the phone into a Google-linked space never reached that calendar.

---

## 4. Known-open, deliberately not fixed here

From the same sync audit (18 confirmed causes, 14 refuted by an adversarial verify pass). These are real and unaddressed:

- **`TaskItem.projectName` has no database column.** Assigning a task to a class never syncs and never survives a reload; `TaskRow` decodes `project_id` then throws it away. `tasks.project_id` already exists (0001), so **no migration is needed** — it needs `TaskItem.projectID`, a round-trip in `AtlasDB`, and `projectName` demoted to a derived display value. Touches many call sites, which is why it was left out.
- **Mac writes are fire-and-forget `try?` with no retry queue.** Create something while offline and the next background pull silently deletes it from your own screen. iOS already has the rollback pattern (`MobileStore.persist`) to copy.
- **The pending capture queue dequeues before its write is confirmed** — a failed write loses that capture permanently.
- **Realtime never starts for a newly accepted invite**, and the socket's JWT is captured once and never refreshed, so live collaboration dies after roughly an hour. Note `RealtimeSyncService` only ever covered SHARED projects — it is not a general cross-device channel, and a solo user has no socket on either platform. The 5-minute poll is the real cross-device mechanism.
- **Four verification agents errored out** (API safeguard flags) so those claims are neither confirmed nor refuted: task `project_id` nulling, `Note.docSyncedAt`, clearing nullable fields, and device-local `UserDefaults` keys that never sync.

## 5. Gotcha worth knowing

Running `swift test` inside `AtlasCore/` standalone **rewrites `AtlasCore/Package.resolved` and drops the Sparkle pin** (Sparkle is an app-target dependency the package alone doesn't see). It was reverted before commit here, but it will happen again — check `git status` after running package tests and `git checkout -- AtlasCore/Package.resolved` if it shows up.
