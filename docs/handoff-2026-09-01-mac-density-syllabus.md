# Handoff — Mac density, event location, syllabus scan quality (2026-09-01)

Drew reviewed the Mac app on the real `drewkhalil` account (4 classes; "Calc I Life&Soc Sci" went 22 → 49 tasks after scanning the real Rutgers Math 135 syllabus). Three problem areas came out of it: (A) task lists show everything forever and overwhelm, (B) calendar events never show a room even though class MEETS rows do, (C) the syllabus scan produced wrong meeting times, a hallucinated office-hours string, a hard-to-read review sheet, and ~20 duplicate tasks because **there is no dedupe of any kind on accept**.

This is a problems list with root causes and file:line evidence — not a spec. A future session can pick any item up cold.

Evidence for C is from the live prod DB (read-only PostgREST, service key) plus the source PDF at `~/Downloads/Calc I Syllabus Fall 2026.pdf`.

---

## A. Task-list density

### A1. The calendar right rail is unscrollable and unbounded
- `Atlas/Views/Calendar/UnscheduledTray.swift:14` — root is `AtlasCard { VStack }` at `:63`. **No `ScrollView` anywhere in the file**, and `AtlasCard` (`AtlasCore/Sources/AtlasCore/Theme.swift:125`) doesn't scroll either. Anything past the window height is clipped.
- Per-task `ForEach` at `:127`, inside a `DisclosureGroup` (`:125`) that force-expands every space on appear (`:114`).
- Source: `Atlas/Views/Calendar/CalendarView.swift:80` → `AppState.unscheduledTasks` (`Atlas/Data/AppState.swift:1176`):
  ```swift
  tasks.filter { !$0.done && ($0.scheduledAt == nil || $0.needsReplan(now: now)) }
  ```
  **Root cause: there is no date window at all.** A task due in November renders today. The only other filters are hidden-space chips (`:54`) and grouping/sort by space (`:58`, `AtlasCore/.../TaskGrouping.swift:58`).

### A2. The class page task list is flat and unbounded
- `Atlas/Views/Project/ProjectDetailView.swift:791` — a single flat `ForEach` over `liveTasks` (`:62`), no grouping, no limit. `SpaceDetailView.swift:179` has the identical pattern.
- Root cause: same as A1 — no horizon concept in the filter.

### A3. Week-scoping logic already exists but is unused on Mac
- `AtlasCore/Sources/AtlasCore/TaskGrouping.swift:28` `bucket(for:now:calendar:)` already computes Overdue / Today / This week / Later / No date (it is `internal`, not `public`). `byDueBucket` (`:94`) is public and is used **only** by iOS (`AtlasMobile/Views/Tasks/TasksView.swift:344`).
- `AtlasCore/.../AgendaBuilder.swift:129` has Late / Due today / Tomorrow / This week buckets.
- There is **no** shared `weekStart`/`weekInterval` helper — `dateInterval(of: .weekOfYear,…)` is duplicated in ~5 places. That's the natural place to add one (`TimeModel.swift`).
- Existing "show N then + more" precedents to copy: `LateBar.swift:33-45`, `MiniMonthAgenda.swift:226-240`, `Atlas/Views/Components/RevealRow.swift:7`.

### A4. Fix sketch (one line each)
Add a public horizon filter to `TaskGrouping`/`TimeModel`, default both surfaces to the current week, and add a shared footer control next to `RevealRow.swift` for "show next week / see all N". Separately, wrap the tray group list in a `ScrollView`.

**Watch out:** the tray's drag-to-schedule uses a custom `DragGesture(minimumDistance: 6, coordinateSpace: .global)` at `UnscheduledTray.swift:243` with global-coordinate drop math in `CalendarView.performTaskDrop`. Adding a `ScrollView` will fight that gesture — needs Drew's visual pass, not just a green build.

### A5. Open product decisions
- Does the rail's collapsed badge count (`CalendarView.swift:74`) stay the **total** or the **in-week** count?
- Overdue tasks from previous weeks: always shown above the week window, or hidden behind "see all"?
- Does the class page get week-scoping too, or due-bucket grouping (Overdue/This week/Later), which may fit a course better?

---

## B. Event location — dropped at every layer

**Bottom line: `location` does not exist on the calendar event model, in the DB, or in any renderer.** The rooms Drew sees on the class page are `MeetingBlock.location` (`AtlasCore/.../Models.swift:166`) — a different object entirely, never a calendar event field.

### B1. Model + persistence
- `AtlasCore/Sources/AtlasCore/Models.swift:326` — `CalendarEvent` has 22 fields; **none is location**.
- `supabase/migrations/0001_init.sql:70` — `events` DDL has no `location` column. A grep of all migrations for `location` returns exactly one hit, and it's a comment about meeting patterns (`0042_school_terms.sql:85`).
- `AtlasCore/.../AtlasDB.swift:595` `EventRow` + `CodingKeys` at `:634` — 19 keys, no location.

### B2. Per-source ingest gaps

| Source | Upstream has it | Captured | Persisted | Mac detail | iOS detail |
|---|---|---|---|---|---|
| Apple EventKit (Mac) | yes (`EKEvent.location`) | **no** — `Atlas/Services/EventKitService.swift:147` maps title/subtitle/notes/isAllDay only | no | no | no |
| Apple EventKit (iOS) | yes | **no** — `AtlasMobile/Services/MobileEventKitService.swift:74` | no | no | no |
| Google Calendar | yes; no `fields` mask is set (`google-sync/index.ts:296`) so the API **is** returning it | **no** — `GEvent` interface at `supabase/functions/google-sync/index.ts:167` omits it; mapping at `:682` discards it | no | no | no |
| ICS feeds | yes | **parsed then thrown away** — `supabase/functions/_shared/ics.ts:304` parses `LOCATION`; `feeds-sync/index.ts:213` `EventPayload` has no field for it | no | no | no |
| Canvas | same parser | **no** — `canvas-sync/index.ts:191` | no | no | no |
| Class MEETS → events | yes | **smuggled into `subtitle`** — `AtlasCore/.../SchoolCalendar.swift:126`: `subtitle: meeting.location ?? meeting.code ?? "Class"` | yes (as subtitle) | no (subtitle is never rendered) | no |
| Semester-wizard ICS import | yes | **smuggled into `notes`** — `Atlas/Data/AppState+School.swift:114` | yes | yes, mislabeled "DESCRIPTION" | yes, as Notes |

### B3. Render gaps
- Mac event detail: `Atlas/Views/Calendar/CalendarEventDetailView.swift:200` shows STARTS / ENDS / SPACE / DESCRIPTION only.
- Mac grid chip: `Atlas/Views/Calendar/TimeGridView.swift:280` `EventTile` renders title + time only and **never reads `subtitle`** — so the MEETS room at `SchoolCalendar.swift:126` is written but is dead for display everywhere.
- iOS event detail: `AtlasMobile/Views/Components/ItemDetailSheet.swift:363` (read-only) and `:148` (editable) — Title / Space / When / Duration / Notes.
- The widget already needs location and works around its absence with a title+start-time side lookup into class meetings (`AtlasMobile/Data/WidgetSnapshotWriter.swift:27-51`, with a comment saying `AgendaItem` "carries neither location nor the event's own id").

### B4. Fix sketch
One new column (`events.location text`), one field on `CalendarEvent`, four codec touchpoints in `AtlasDB.swift` (`:595/:634/:657/:683`), one-line additions at each of the six ingest sites above, and a "Where" row in the two detail sheets. Wide but shallow. Stop smuggling into `subtitle`/`notes` at `SchoolCalendar.swift:126` and `AppState+School.swift:114`; `AgendaBuilder.AgendaItem` needs a passthrough so the widget hack can go.

### B5. Open product decisions
- **Write-back:** if Atlas reads Apple/Google location but doesn't write it, an in-Atlas edit will blank the upstream value (same trap `EventKitService.swift:155` already warns about for notes). Read-only field, or full round-trip?
- Migrate existing smuggled `subtitle`/`notes` room strings into the new column, or leave them?
- Show location on the calendar tile, or detail-only?

---

## C. Syllabus scan — quality, review sheet, dedupe

### C1. The 4 "MW" meeting rows are a parse error, not real sections

The PDF's Meetings table reads:

```
Sec. 37–39   Lecture      MW4   2:00–3:20 pm   PH-115
Section 37   Recitation   T4    2:00–3:20 pm   SEC-217
Section 38   Recitation   T5    3:50–5:10 pm   SEC-217
Section 39   Recitation   T6    5:40–7:00 pm   SEC-217
```

What's in prod (`projects.meeting_pattern`, class `bea49332-f6ff-4427-82db-c67888be7b33`) — `weekdays` uses Foundation numbering, `[2,4]` = Mon+Wed:

| Stored | PDF truth | Verdict |
|---|---|---|
| `[2,4]` 10:00–10:55 "Hill Center 434" | not a meeting at all — that's the instructor's **office** | **Hallucinated**. Both the days and the times are invented. |
| `[2,4]` 14:00–15:20 "PH-115" | MW 2:00–3:20 PH-115 | **Correct** — the only right row. |
| `[2,4]` 15:50–17:10 "SEC-217" | **Tu** 3:50–5:10, Section 38 (not Drew's) | Time right, **day wrong** (T→MW), and it's another section. |
| `[2,4]` 17:30–19:00 "SEC-217" | **Tu** 5:40–7:00, Section 39 (not Drew's) | Day wrong **and** start time wrong (17:40 → 17:30). |

Missing entirely: Drew's own Section 37 recitation (Tu 2:00–3:20 SEC-217). Also, unlike his other three classes, these blocks have **no `firstDate`/`lastDate`**, so they have no term bounds.

**Root causes:**
1. **Prompt.** The entire meetings instruction is the schema block at `supabase/functions/syllabus-scan/index.ts:117-123` plus one rule at `:158-159` — *"'meetingPattern' is the RECURRING weekly pattern only. A one-off exam date is an item, not a meeting block. Merge days sharing a time into one block's 'weekdays'."* That merge instruction actively encourages flattening rows that differ. Nothing tells the model a syllabus can list **multiple sections of which the student attends one**, nothing distinguishes lecture from recitation, and nothing says an "Office:" line is not a meeting. (Rule `:151` "NEVER invent a date" covers dates but not times, so a fabricated 10:00–10:55 block passed unchallenged.)
2. **Silent weekday clamping.** `supabase/functions/_shared/syllabus_scan.ts:73-74` does `filter(d => typeof d === "number" && d >= 1 && d <= 7)` — nothing more. If the model answers in **ISO numbering (Mon=1…Sun=7)** instead of the Foundation numbering the prompt asks for, **Tuesday (ISO 2) silently becomes Monday (Foundation 2)** and Sunday (0) is dropped, with no error and no signal. `_shared/syllabus_scan_test.ts:58,65` confirms out-of-range days are silently discarded. This is the most likely mechanism for "Tuesday recitations became M/W" and is provably reproducible from a test fixture.
3. **No block hygiene.** `normalizeClasses` maps blocks 1:1 (`_shared/syllabus_scan.ts:66-81`); `applyCaps` (`:130`) caps classes (20) and items (200) but never blocks, and never collapses identical ones.
4. **No section-picking step** exists anywhere: the model can't know which recitation Drew is in, and the review sheet never asks — its `meetingPattern` display at `SyllabusScanSheet.swift:209` is **read-only**, so he couldn't fix the rows before committing either.
5. **A re-scan overwrites wholesale.** `AppState+School.swift:206` `setMeetingPattern` and `:225` `setClassInfo` replace the project's arrays outright — which is how the previously correct Tu/MW pattern was destroyed.

### C2. `class_info` — grading right, office hours hallucinated
- Grade weights: **correct**, all six lines match the PDF table (HW 4 / wrappers 4 / quizzes 20 / midterms 36 / final 36 / total 100).
- Policies: **correct**, six accurate condensations of the Absences & Makeups, ODS, and Academic Integrity sections.
- `office_hours: "Tue 2–4pm, Rm 312"` — **pure hallucination**. The PDF says *"See Canvas for the most up to date office hours"* in both instructor blocks. Root cause: this exact string is the prompt's own example at `index.ts:127` (`// e.g. "Tue 2–4pm, Rm 312"`) and the model copied the example verbatim. Any placeholder example in that schema is a hallucination risk.

### C3. Items — right shape, wrong December dates, and the exams landed as events
Prod holds **49 tasks** (22 with `canvas_uid` set, 27 syllabus-derived) plus **17 events** (13 quizzes, 2 midterms, 2 "final exam" rows). So the ~43 accepted items did land; task/event routing worked as designed (`index.ts:146-147`).
- Dates: syllabus tasks store `HH:59` local end-of-day and match the PDF **except the three December Synthesis items**, which are wrong: S1 Dec 2 → stored Dec 7; S2 Dec 7 → Dec 8; S3 Dec 9 → Dec 14.
- Two competing finals exist: `Calc I Life&Soc Sci Final Exam` (00:00) and `Final Exam` (12:00) both on Dec 15 — one from the school/term calendar, one from the scan. A duplicate.

### C4. DEDUPE — the answer is **none. Zero. At any layer.**

`Atlas/Views/School/SyllabusScanSheet.swift:482` `commit()` loops `group.includedItems` and calls `state.addEvent(...)` / `state.addTask(...)` unconditionally. There is no lookup of existing tasks, no title normalization, no date comparison, no `canvas_uid` check. Grepping `dedup|duplicate|existing|canvasUID|normaliz` across `SyllabusScanSheet.swift` and `AtlasCore/.../SyllabusDraft.swift` returns **nothing**.

The result is visible in prod — roughly **20 near-duplicate pairs** on this one class, e.g.:

| Canvas task | Syllabus task | Same work? |
|---|---|---|
| Lecture 1 Definition of the Derivative | Rates of change, definition of the derivative | yes |
| Lecture 2 Limits of Indeterminate Form | Limits of indeterminate form (0/0 only) | yes |
| Lecture 4 The Chain Rule | The chain rule | yes |
| Lecture 6 Continuity | Continuity | yes |
| Lecture 13 Related Rates | Related rates | yes |
| Lecture 19 Fundamental Theorem of Calculus | Fundamental theorem of calculus | yes |

…and so on for lectures 0, 3, 5, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18. Titles differ in wording so exact-string matching would catch none of them; the reliable signal is **same class + same/adjacent date**, since the Canvas lecture and the syllabus topic land on the same or next calendar day.

**What dedupe does exist, and why none of it helps here:**
- `docs/specs/redesign-2026-08/phase-3-sync-rules-dedup.md:20-31` specifies `collapsingDuplicates(...)`, and it **is now implemented** — `AtlasCore/.../CalendarSync.swift:113`, with `titlesMatch` `:156`, `timesMatch` `:164`, `priority` `:184`, `normalizeTitle` `:196`; thresholds `minPrefixMatchLength = 8`, `sameStartTolerance = 60s`, `overlapThreshold = 0.5`. Called from `AppState+Calendar.swift:120`, `CalendarView.swift:500`, `MobileStore+Calendar.swift:85`. **The spec's own status line at `:3` ("not yet implemented") is stale — update it.**
- But it is **display-time, events-only**. A syllabus exam within 60s of a Canvas copy gets visually collapsed; the duplicate row still exists in the DB, and syllabus events commit at the stated hour with a 60-minute default (`SyllabusDraft.swift:100`) so any drift past 60s shows both. **There is no task equivalent anywhere, at any layer.**
- Canvas ingest dedupes server-side on `onConflict: "user_id,canvas_uid"` (`canvas-sync/index.ts:263,313`), but syllabus-created tasks leave `canvas_uid`, `canvas_course`, `feed_id`, `feed_type` all `nil` — so the two rows are permanently unrelated. Confirmed in prod: 22 rows with `canvas_uid`, 27 with none.
- **The spec never covered task-level or syllabus-accept dedupe at all.** That's a gap in the spec, not just the code.

**Drew's requirement:** accepting a scan must never duplicate an existing Canvas task or calendar event.

### C5. Review sheet is a wall of small text
`Atlas/Views/School/SyllabusScanSheet.swift:200` `groupSection`. Everything renders at 12pt with no hierarchy and no collapse:
- Meeting times `:209` — 12pt secondary.
- Class info `:222` — every grade weight and every policy line flattened into one undifferentiated `ForEach` of 12pt secondary text (`infoLines(info)`).
- Work items `:279` `itemRow` — 13pt title, a 10pt mono kind pill, one row per item; 43 of these stack with no grouping by month or type.

The sheet is also a **fixed 560×560 window** (`:50`), so all of it scrolls inside a small box. `infoLines(_:)` at `:379` is the specific culprit for the class-info wall: it flattens `gradeWeights + policies + officeHours` into one undifferentiated bullet stream with no group headings and no line limit. iOS mirrors this at `AtlasMobile/Views/School/SyllabusScanSheet.swift:200-236`.

Root cause: no sectioning, no size contrast, no per-group collapse, and no notion of "this one is suspicious / this one is a duplicate." Also note the meeting-pattern rows are display-only — there is no way to correct a bad block before committing.

### C6. The class-page Policies dump
`Atlas/Views/School/ClassHubSection.swift:149` `classInfoCard` → `infoGroup` at `:198`. Every grade weight and **every policy** renders unconditionally at 13pt with `lineLimit(2)` each (`:207-211`) — for this syllabus that's 6 weight lines + up to 12 lines of policy text in one grey block. Root cause: no cap, no expand/collapse, no per-item chip treatment. There's already a detail sheet behind it (`ClassInfoSheet.swift:90-123`, deliberately unlimited — "the whole point of this screen is the full wording"), so the card doesn't need to carry the full text. `ClassInfoCard` is **structured** (`Models.swift:204`: three string arrays in `projects.class_info` jsonb), so a card/chip redesign is purely presentational — no model, no migration, no server. Touches four view files: `ClassHubSection.swift:149-217`, `ClassInfoSheet.swift:90-123`, and the iOS twins `AtlasMobile/Views/School/ClassHubView.swift:201-215` and `AtlasMobile/Views/School/ClassInfoSheet.swift:88-110`.

### C7. Fix sketches (one line each)
- **Meetings:** rewrite the `meetingPattern` prompt block to forbid merging rows that differ in day, to name office/instructor lines as non-meetings, and to emit a `sectionLabel` + `kind` (lecture/recitation/lab) per block; then let the review sheet ask "which section are you in?" when more than one is returned.
- **Office hours:** delete the `"Tue 2–4pm, Rm 312"` example from `index.ts:127` (or replace it with a non-copyable placeholder).
- **Server guard (cheap, independent of all UI work):** make `_shared/syllabus_scan.ts:73` flag rather than silently clamp implausible weekdays, collapse byte-identical blocks, and cap blocks per class. Reproducible from a test fixture today.
- **Dedupe:** a pure function in AtlasCore matching a draft item against existing tasks/events for the same class, reusing `CalendarSync.normalizeTitle` `:196` / `titlesMatch` `:156`, but keyed on **same due *day*** rather than same instant (Canvas's 11:59pm vs the syllabus's stated hour will never match to the second). Called from `SyllabusScanSheet.swift:482` (and the iOS twin at `AtlasMobile/.../SyllabusScanSheet.swift:506`), defaulting matched items to `include = false` with a visible "already in Canvas" badge — never silently dropping them.
- **Review sheet meeting editing:** make `SyllabusDraftGroup.meetingPattern` editable in the sheet so a bad block can be fixed before commit, not after.
- **Review sheet:** cards per group, larger type, month sectioning of work items, duplicate badges.
- **Class info card:** chips for grade weights, first N policies with an expand, full text in the existing detail sheet.

### C8. Open product decisions
- When the scan returns several sections, does Atlas ask Drew to pick one, import all and let him delete, or import only the lecture?
- On a duplicate: default the syllabus copy to unchecked, or merge its notes/section info into the existing Canvas task?
- Should dedupe also run **after** the fact (a "you have 20 possible duplicates" cleanup on the class page), given his account already has them?
- Should a scan ever be allowed to overwrite an existing `meeting_pattern` outright? It replaced a previously correct Tu/MW pattern here.

---

## TODO — UI ideas page (not yet built)

An interactive variants page was scoped for this batch but **was not built**. It remains a follow-up task:

> Build `docs/specs/redesign-2026-08/ui-density-syllabus-ideas.html` in the style of the earlier `ui-style-directions.html` — a self-contained page showing 2–3 design variants for each of:
> 1. **Week-scoped calendar task rail** — default to the current week, with "show next week" / "see all N tasks" at the bottom, and a decision on where overdue items sit.
> 2. **Class-page task list** — week scoping vs due-bucket grouping (Overdue / This week / Later), with the same show-more affordance.
> 3. **Card-based syllabus review sheet** — replacing today's 12pt wall of text. **Type must be noticeably bigger**, work items grouped (by month or by kind), and each item able to carry a **duplicate badge**.
> 4. **Class-info chips/cards** — replacing the giant Policies dump with grade-weight chips and collapsed/expandable policies.
>
> Non-negotiable to represent in the mockups: **accepting a scan must never duplicate an existing Canvas task or calendar event** — the duplicate state needs a visible design, not just a silent filter.

Drew picks variants on that page before any implementation starts.

---

## Suggested implementation order

1. **C4 dedupe** — the only item actively corrupting real data every time he scans. Blocks nothing else.
2. **C1/C2 prompt + `_shared/syllabus_scan.ts` weekday guard** — cheap, server-only, no client release; stops wrong meeting times and the fake office hours at the source. Also correct the stale status line in `phase-3-sync-rules-dedup.md:3`.
3. **Build the UI ideas page**, get Drew's variant picks.
4. **A** — week scoping (shared AtlasCore logic first, then both surfaces; the tray `ScrollView` needs a visual pass).
5. **C5/C6** — review sheet and class-info card, per the chosen variants.
6. **B** — event location, the widest change and the least urgent; do it as one column + one field + a sweep, not piecemeal per source.
