# Handoff — gap fixes, Jonah's batch, model test (2026-09-02)

**iOS 1.1 is APPROVED and RELEASED (Drew released it 09-02).** Mac is 0.11.0 on the DMG channel.
Everything below is UNCOMMITTED on local `main` unless marked deployed. Local main is 4 commits
behind `origin/main` (Jonah's PRs #5 and #6). Do not merge until Jonah says he is done (§3).

## 1. Where the tree stands

Two batches sit uncommitted on top of `370af01`:

**Batch A — 09-01 school-pipeline work** (see `docs/handoff-2026-09-01-*.md` and memory): all-day
dates, syllabus/schedule scan rewrite, dedupe, section auto-match, rescan Keep/Replace, scan
provenance, TermTimeline, class-info redesign, window chrome, due-tonight pills, etc.

**Batch B — 09-02 gap fixes** (this session, all gates green: 424 AtlasCore tests, Mac + iOS build):

| Fix | Where |
|---|---|
| Date-only syllabus TASKS now commit `allDay = true` at the UTC-midnight anchor (events already did; tasks never did) | `SyllabusDraft.taskDue(for:)`, `AppState.addTask(allDay:)`, both `SyllabusScanSheet.commit()` |
| `AtlasBandProbe` debug scaffolding removed; `reassert(delays:)` chrome fix kept | `Atlas/App/WindowConfigurator.swift` |
| Rescan flags are a full re-decision (was a one-way ratchet → retargeting a scan group to a class with no saved pattern silently dropped the meeting pattern). Meetings card gained a toggle | `SyllabusRescan.keepingExisting`, both `SyllabusScanSheet` (~L345 Mac / ~L361 iOS) |
| `recordScan` DB insert is AWAITED before item writes (was an unawaited `Task{}`; FK 23503 could swallow the item) | `AppState+School.swift`, `MobileStore+School.swift`, both `commit()` now `async` |
| `ClassInfoFormat` (weight parsing / TOTAL-row exclusion / `weightTotal`) moved to AtlasCore — ONE copy, both view-local copies deleted; server `isGradeWeightSummaryRow` confirmed equivalent (comment-only change) | `AtlasCore/.../ClassInfoFormat.swift` + tests |
| "Canvas feed stopped syncing" sidebar prompt (Mac): `revoked`/`error` → broken; `active` with no sync in 24h → stale; opens Settings → Calendars | `AtlasCore/.../CanvasFeedHealth.swift` + tests, `SchoolSidebarSection.swift` |
| Due-date-moved chip: server stamps `tasks.due_moved_from` when a Canvas due date changes on a non-done task; amber chip in Mac task detail + tray row marker + iOS detail sheet; dismiss clears it | migration 0047, feeds-sync + canvas-sync, `TaskItem.dueMovedFrom`, `TaskDetailView`, `UnscheduledTray`, `ItemDetailSheet` |

`AtlasCore/Package.resolved` was reverted — running `swift test` standalone drops the Sparkle pin
(Jonah's gotcha). Check `git status` for it before every commit.

## 2. Deployed to prod this session

| What | State |
|---|---|
| Migration 0045 task all_day, 0046 syllabus_scans | applied 09-01 |
| Migration **0047** `tasks.due_moved_from` | applied 09-02 |
| Migration **0048** event recurrence (Jonah's, renumbered from his 0046) | applied 09-02 |
| `feeds-sync` **v5** — `archived_at is null` filter on project routing + due-moved stamping. **This is the function the cron runs** (0040 cut over from canvas-sync) | live |
| `canvas-sync` **v11** — same changes, kept identical (compat endpoint) | live |
| `syllabus-scan` v9 | live since 09-01 evening (no change today) |
| `capture` **v22 — NOT deployed on purpose.** Jonah's new prompt returns one item with `recurrence`; the released iOS 1.1 / Mac 0.11.0 builds predate his code and would create one event instead of a series. Deploy ONLY after builds containing his code ship. | blocked |

## 3. Jonah's batch on origin/main (PR #5 + #6)

Repeating events (materialized rows sharing `series_id`) + six cross-device sync fixes, ~1,670
lines, 26 files. His handoff: `docs/handoff-2026-09-02-recurrence-and-sync.md` (on origin). He
pasted a "PENDING DEPLOY" block into CLAUDE.md that must be deleted once capture is deployed.

**Jonah said more is not done and he is finishing it tonight (09-02). Wait for him.**

Dry-run merge (`git merge-tree`) of our uncommitted tree vs origin/main: **only 3 conflicts, all
trivial adjacent-field additions** — keep both sides:
- `AtlasCore/Sources/AtlasCore/Models.swift` — our `CalendarEvent.scanID` vs his `seriesID`/`recurrenceRule`
- `AtlasCore/Sources/AtlasCore/AtlasDB.swift` — `EventRow.scanId` vs `seriesId`/`recurrenceRule` (4 hunks: field, CodingKey, init, toDomain)
- `Atlas/Views/Calendar/EventEditorSheet.swift` — `event.scanID = seed.scanID` vs the series fields

At merge: DELETE his `supabase/migrations/0046_event_recurrence.sql` (ours is 0046; his content is
already applied as `0048_event_recurrence.sql` in our tree). Tell Jonah 0046–0048 are taken.

Merge plan Drew agreed to in principle: commit + push our batch first so Jonah rebases onto it
tonight; then merge his finished work; gates; ship Mac + iOS builds; THEN deploy capture.
**Drew has not yet said "commit" — nothing is committed.**

His audit's "known open" list overlaps ours: **`TaskItem.projectName` has no DB column — task↔class
link never persists.** Same bug as our "syllabus tasks lack projectID so rescan can't dedupe vs a
prior scan." One owner, not two. Also: Mac writes are fire-and-forget `try?` with no retry queue.

## 4. Model test (syllabus-scan prompt, 3 real PDFs, 3 models via OpenRouter, n=1)

| | Gemini 2.5 Flash (prod) | Claude Haiku 4.5 | Claude Sonnet 5 |
|---|---|---|---|
| Calc I recitations on the right day (all Tuesday) | 0/3 (all Thu, 2 wrong times) | 1/3 | **3/3** |
| PSY101 dated items invented (doc has none) | 0 | 19 | 1 |
| Calc I items (16 is correct) | 43 (lecture topics as tasks) | 16 | 16 |
| Psych schedule doc | identical | identical | identical |
| Cost / 15-page scan | $0.004 | $0.034 | $0.084 |

**Decision: syllabus scan → Sonnet 5. Capture stays Gemini Flash Lite. Jonah agreed** and will share
his Anthropic credits (~$500 ≈ 6,000 Sonnet scans). Open: whose account holds the key (personal
vs org) and when the credits expire. Test artifacts and the borrowed key were deleted.

**Implementation when ready (~half a day, Opus agent):** direct Anthropic Messages API adapter in
`supabase/functions/syllabus-scan/index.ts` behind a provider switch (keep the OpenRouter path so
falling back is config, not code); images as base64 image blocks; JSON via structured outputs;
`max_tokens` stays large, stream or raise the function timeout; `ANTHROPIC_API_KEY` as a Supabase
secret; re-tune the prompt for Sonnet (it ran the Gemini-tuned prompt untuned and still won);
re-run the same 3 PDFs before deploy. Model ID `claude-sonnet-5`. Do NOT deploy while Drew is
mid-testing on a build that expects the old response shape (response shape should not change —
the adapter must return the identical JSON contract).

## 5. Still open (ranked)

0. **"Undo this scan" — Drew's live problem right now.** He uploaded an OLD Psych syllabus by
   mistake; its tasks/events are now mixed into the class alongside the live Canvas items. Rescan
   Keep/Replace only governs `class_info` / `meeting_pattern`; imported ITEMS just accumulate, and
   nothing removes them. Migration 0046 already stamps `tasks.scan_id` / `events.scan_id` and keeps
   a `syllabus_scans` row per commit — the data side of undo exists, the UI does not (there is no
   `deleteScan` in AtlasDB and no scan list on the class page).
   **NOT designed yet — open questions to talk through with Drew before anyone builds:**
   - Is this "undo" (right after a scan) or "remove a syllabus" (weeks later, after the student has
     edited, completed, or rescheduled some of its items)? They're different features. Undo is a
     one-click revert; remove-later needs rules for what the student has touched since.
   - When the student has already edited or completed some of that scan's items, what happens to
     those? Options: remove everything anyway / keep touched ones / show the list and let them tick.
     Which does a student expect in September vs November?
   - Should `class_info` and `meeting_pattern` come back too? We don't snapshot the previous values
     at commit, so today "undo" can only clear them, not restore. Worth a migration (next free is
     0049) or is "clear + rescan the right file" good enough?
   - Where does it live? A scan history list on the class page, a "Remove syllabus items" action in
     the class menu, or both? Does iOS get it or is it Mac-only like Canvas management?
   - Rescan already dedupes new items against existing ones. Is a correct rescan on top of a bad
     scan actually the common path, with "remove" only for the mistaken-upload case?
   - What's the mental model we tell the student: "each scan is a batch you can pull back out" or
     "the syllabus is a thing you can replace"? The second is simpler but implies one syllabus per
     class, and schedule docs already break that.
   - Canvas items are safe either way (they carry `canvas_uid`, never `scan_id`) — confirm that
     holds for items the dedupe step un-checked and the student then re-checked.
   **Immediate cleanup for Drew's Psych class if he can't wait:** the bad items were committed after
   0046 was applied (09-01), so they should carry a `scan_id`. Find the scan row for that project
   in `syllabus_scans`, then delete `tasks`/`events` with that `scan_id` via PostgREST (recipe in
   memory `atlas-live-db-access`). Snapshot first. If they have no `scan_id` (committed before the
   client stamped it), fall back to: project = Psych, `canvas_uid is null`, `created_at` within the
   scan's minute. Then rescan the correct syllabus with Sonnet once §4 lands, or with Gemini now
   and fix the meeting pattern by hand.

1. **Drew's visual pass on Batch A + B** — never done in full; his earlier pass notes were lost with
   that session. UI to check: due-moved chip (Mac detail, tray marker, iOS detail), Canvas-feed
   prompt, Meetings card toggle, white title-bar band, class-info sheets, rescan Keep/Replace,
   density variants, plus Jonah's repeat picker / scope dialogs / series badge / series undo.
2. **Task↔class link never persists** (§3) — decide owner with Jonah.
3. Campus time zone for MEETS blocks (`SchoolCalendar.time` uses device zone at render) — deferred.
4. `ScanRecord.Kind.schedule` never produced; "schedule docs can't write class_info" is not enforced
   server-side — deferred.
5. Rescan dedupe is title-only; a user-renamed task gets duplicated on rescan — deferred.
6. Event `location` field (rooms smuggled into subtitle/notes) — deliberately last.
7. Dec Synthesis date discrepancy + duplicate Final Exam — never root-caused.
8. "1 new course found" banner from a Canvas feed with no matching class — untriaged.
9. Prod Calc I `meeting_pattern` is still the scan-clobbered Mon/Wed version — needs a rescan with
   Sonnet (which gets it right) or a manual PATCH.
10. Pre-0046 scan-created events at "12 AM · 1h" are not backfilled (no canvas_uid, no scan_id).

## 6. Working notes

- Drew wants Sonnet agents for research/orchestration, Opus only when code-heavy; Fable never
  writes implementation code.
- Decisions that need Drew → HTML options page, not a terminal question. Chat with Jonah → short.
- AI cost is not a concern at current volume; the argument for Sonnet is accuracy, not price.
- `supabase migration list --linked` before choosing any migration number.
