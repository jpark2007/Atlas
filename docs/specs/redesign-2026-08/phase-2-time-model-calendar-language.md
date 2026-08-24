# Phase 2 — Time Model & Calendar Language (agreed 2026-08-24)

Part of the 2026-08 redesign. Status: **discussion converged; not yet planned/implemented.**
**Mac-first.** iOS gets its own interpretation of the same model later.

## The five things on the calendar

| Concept | What it is | Rendering |
|---|---|---|
| Class meeting | Recurring lecture/lab from the Class's meeting pattern | Solid block, class color |
| Event | Something happening at a time (any source) | Solid block, calendar/class color |
| Work session | Planned time for a task ("the plan, not the commitment") | Dashed/faded block, movable, linked to its task |
| Deadline | Due date/time — a boundary, not an occupancy | Hairline marker + caps/chips (below). Never a block |
| Task (unscheduled) | To-do, date optional | Side rail only — never on the grid |

**Channel rules:** color = class/calendar, never type. Fill/outline = type (solid vs dashed vs marker). State overlay = amber/red (below).

## Side rail

Unscheduled tasks live in a side rail next to the calendar. **Drag from rail onto grid = creates a work session** for that task. (Mechanism already exists as task `scheduled_at` work-blocks; rail is the canonical surface.)

## Deadlines

- **Day view:** thin full-width hairline marker at the actual due time, class color, small flag cap + title. Untimed dues = marker at end-of-day with a "no time" glyph. If due markers are below the viewport (11:59 PM), a **sticky bottom edge-chip** appears: "2 due later tonight ↓".
- **Week view:** same markers, plus a **per-day count cap** at the top of each column ("3 due", class-colored, click to expand). Cap = count + jump target; markers = source of truth. Never "+2 more" collapse.
- **Deadline ↔ work link (differentiator — nobody ships this):** click/hover a due marker → its work sessions glow, rest dims; marker carries a small planned-hours fill ("2.5 of 4h planned"). Requires task time-estimates to be optional-but-supported. (No auto-slot "Schedule time" action — cut; sessions are planned by dragging from the rail.)

## Completion mechanics — task is the truth

- The task checkbox is the **only** checkbox. Check it anywhere (rail, class page, clicking its work session) → done; future work sessions for it fade/clear.
- A past work session completes nothing; it becomes faded **history** (proof you worked). If its task is still open, the past session shows a quiet **"+ more time"** affordance → one click schedules the next session.
- Didn't actually work? Delete/drag the session like any calendar block. No session-level "done?" prompts, ever.

## Mockup-review addenda (agreed 2026-08-24, after visual preview)

- **Dashboard keeps the mini month calendar.** Late bar + Due-today rail + Tonight's-work join it; only the recent-notes widget gives up its slot. Dashboard layout otherwise unchanged.
- **Calendar gains a List toggle:** Day · Week · Month · **List** — agenda grouped Late / Due today / Tomorrow / This week (mirrors the iOS Schedule list).
- **No auto-slot scheduling (cut by Drew 2026-08-24):** there is no "Schedule time drops a session in a free gap" action. Planning a session is always manual — drag the task from the rail onto the grid. The deadline marker keeps the hover-glow link and planned-hours fill only.
- **Time estimates are an optional task field** (set via chip popover or task detail). With no estimate the due marker shows "N sessions planned" instead of the hours fill.
- **Token collision to resolve at implementation:** theme `warning` and the yellow space color are both `#febc2e`, so a Late bar can read as a HIST-colored item. Pick a distinct warning amber if it reads ambiguously in the real app.

## Overdue — pin, don't roll

- Overdue items collect in a **Late bar** pinned above today (calendar page + side rail), showing original due date + days late.
- **Dismiss collapses the bar only, never the items.** Reappears next day; repeat daily until checked off. Nothing silently vanishes; the original date keeps a faded marker in the past.
- **No auto-roll.** Bar offers explicit one-click triage: "Reschedule N late items." Original due date survives and stays visible after any reschedule.
- **Color semantics (research-backed):** amber = late. **Red is reserved for "due today and no work time planned"** — that's where pressure helps; red overdue graveyards cause avoidance (ADHD/student findings).

## Research notes (for the implementer)

- Sunsama's own roadmap: task-vs-event distinction "too subtle" — hence dashed+faded, not tint-only.
- Morgen is the closest prior art (due marker + separate planned blocks, multiple sessions per deadline); Shovel's per-day due cap; Google/Apple strip conventions. Motion's silent auto-reschedule is its most-cited trust failure — never auto-move.
- Full reports live in the session research; key sources: Morgen guides, Shovel, Todoist/TickTick/Akiflow overdue patterns.
