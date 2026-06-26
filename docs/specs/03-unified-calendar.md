# 03 — Unified Calendar

The home screen. Aggregates everything into one native calendar.

## Sources merged

- **Apple Calendar** — via EventKit (read + write), on-device.
- **Google Calendar** — via backend OAuth + sync.
- **Canvas** — class meetings + assignment due dates (see [05](./05-canvas.md)).
- **Atlas-created** — events and scheduled tasks.

## Main calendar choice

- User picks which calendar is their **"main"** (Apple *or* Google).
- New Atlas-created events default to the main calendar and **two-way sync** to it, so they also appear in the user's native Apple/Google app.
- All sources are visible in Atlas regardless of which is "main."

## Views

- **Day / Week / Month** views.
- **Filter by Space** — show only School, only Personal, etc., or all at once (color-coded by space).
- Each event/task is color-coded by its space.

## Drag-and-drop scheduling

- A **sidebar/tray of unscheduled tasks** (to-dos with no time yet).
- Drag a task onto a time slot → it gets a `scheduled_at`, becomes a calendar block, and (optionally) syncs to the main calendar.
- Dragging an existing block reschedules it; resizing changes duration.

## Two-way sync rules

- Edit in Atlas → push to the source calendar (if it lives there).
- Edit in Apple/Google → pull into Atlas on next sync.
- Conflicts: last-write-wins to start (revisit later).

## Relation to the AI Brain

The Brain ([04](./04-ai-brain.md)) reads the unified calendar to know your free/busy time when auto-scheduling tasks and suggesting goal sessions.

## Open questions

- How aggressively to write Atlas tasks back to the native calendar vs. keep them Atlas-only until confirmed.
- Recurring event handling across sources.
