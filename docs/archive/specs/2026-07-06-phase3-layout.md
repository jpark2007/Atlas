# Phase 3 — Layout refinement

**Date:** 2026-07-06 · **Status:** DRAFT — runs LAST, after Phase 1 (reskin) and Phase 2 (features).
Reference: the locked mockup (artifact `e29aefff…`, version `paper-minimal-v4-12h`) and master plan
`2026-07-06-dashboard-focus-perf-plan.md` §1. Mac only.

Phase 3 is structural: it moves/replaces dashboard sections and adds the date-navigator behavior.
No new visual language here — Phase 1 tokens/components are assumed done. No new features — anything
functional belongs to Phase 2.

---

## 3.1 Dashboard restructure (the big one)

Target layout (from the locked mockup):

- **Title bar:** greeting demoted to tiny mono uppercase, left ("GOOD AFTERNOON"); date right
  ("MON — JUL 6, 2026"). The big serif "Good morning, Jordan" header goes away.
- **Main column:**
  1. **Clock block** — live 12-hour clock, huge mono ink digits, clay colons, muted seconds, small
     AM/PM; mono dateline under it ("MONDAY —— JUL 6 / 2026"); hairline below.
  2. **Focus list** — "TODAY'S FOCUS" (or "FOCUS — THU, JUL 9" when navigated): task rows with
     square checkboxes, space wash-tags; subtle "+ Add a task" text affordance (opens quick capture).
  3. **Recent Notes** — plain rows: serif title · GOOGLE DOC marker when linked · mono "date · space".
     Row click opens the note (corner-card editor, per Phase 2.1 rule).
- **Right rail (~348pt):**
  1. **Mini month calendar in the outlined instrument container** — the date navigator.
  2. **Agenda** — "TODAY" (or the navigated day): time · space-colored dot · title · duration;
     the current event row highlighted ("now", clay wash); "FULL VIEW ›" routes to `.calendar`.

**Date-navigator behavior (core interaction):** selecting a day updates Focus list + agenda +
labels; today keeps the solid clay square; selected ≠ today gets the outline treatment and a
"← TODAY" link appears; nav chevrons page months. Reuse `MonthGrid`/`MonthGridView` geometry,
`events(on:)` (`AppState.swift:448-452`), `scheduledWorkBlocks(on:)` (`:476-497`), and
`CalendarView.deadlineEvents(on:)` logic for dots.

**Data semantics (DECIDED, Drew 2026-07-06):**
- **Focus list = the next ~8–10 upcoming open tasks ordered by deadline** (`dueDate`, then
  `scheduledAt` as tiebreaker; undated tasks after dated ones). NOT scoped to the selected calendar
  day. The count (8 vs 10) can become a Settings knob later — hardcode a sensible one at build time.
- **Agenda (under the calendar) = the selected day's events + scheduled work blocks**
  (`events(on:)` + `scheduledWorkBlocks(on:)`). The calendar's date-navigation drives the AGENDA
  (and its label), not the Focus list. "← TODAY" resets the agenda day.
- Notes section: recent notes, as mocked.

**Removed from the dashboard (DECIDED):** `ScheduleCard` (replaced by the agenda rail), `FocusCard`
(Focus reachable via sidebar + Phase-2 menu-bar timer), **`GoalsCard` and `MetricsCard` — dropped;
they live in Settings→Metrics.**

## 3.2 Secondary screens alignment (light pass, after 3.1)

- **Calendar screen:** month grid = same instrument container language; day/week headers mono.
- **Project detail:** section headers to the shared mono+hairline style; notes/references as plain
  rows (no cards) except pickers.
- **Focus screen:** timer ring becomes an "instrument" (outlined) consistent with the calendar.
- **Command palette / capture:** verify they read correctly on the new tokens (they're overlays —
  the one place a filled surface is still allowed).

## 3.3 Verification

Every step: build green + Drew's visual pass (layout is exactly the class of change a green build
cannot prove). E2E: date-navigator click-through once implemented.
