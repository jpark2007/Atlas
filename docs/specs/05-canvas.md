# 05 — Canvas Integration

Canvas (the LMS) feeds the **School** space.

## What syncs

- **Classes → Projects.** Each Canvas course becomes a **Class** project in the School space.
- **Assignments → Tasks.** Each assignment becomes a task **auto-populated with its due date and description/notes**, linked to its class project.
- Scope is intentionally focused: **classes + assignments**. Not the whole Canvas surface (grades, discussions, etc.) — at least to start.

## Behavior

- A class project owns its recurring **meeting event** on the calendar (if class times are available).
- Assignment tasks appear in the unified calendar by due date and can be dragged to schedule work time.
- Re-sync periodically (scheduled Edge Function) to pick up new/changed assignments.

## How it connects

- Canvas API access via the backend (token/OAuth held server-side, per [01](./01-architecture.md)).
- A **scheduled Supabase function** pulls updates; changes flow into the user's School space.

## Auth approach (to decide)

- Canvas API token vs. OAuth flow — pick during the Canvas phase. Token is simpler to start; OAuth is cleaner for other users later.

## Open questions

- Mapping Canvas course meeting times to recurring events (not all schools expose these cleanly).
- De-duping if a user also has Canvas events in their Google/Apple calendar.
