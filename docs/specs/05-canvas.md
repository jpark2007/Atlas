# 05 — Canvas Integration

Canvas (the LMS) feeds assignments + due dates into the unified calendar.

> **Connection changed (2026-07-01):** the original plan used a Canvas API access
> token / OAuth held server-side. Both our schools (Rutgers, Princeton) **disable
> student access tokens**, so that path is dead. Canvas now connects via the read-only
> **Calendar Feed (ICS)** URL instead. Full design + rationale:
> [2026-07-01-canvas-ics-sync-design.md](../archive/specs/2026-07-01-canvas-ics-sync-design.md).

## What syncs

- **Assignments → read-only deadlines.** Every assignment in the feed appears in the
  unified calendar by due date, labeled by course. Zero setup — this is the default.
- **Optional: course → project linking.** A course can be explicitly linked to a project
  you've created (Atlas auto-suggests the match, you confirm). Linked assignments also
  surface under that project and can be dragged to schedule work time.
- Scope stays focused: **assignments + due dates**. Not grades, submissions, or to-dos.

## How it connects

- **Read-only Canvas Calendar Feed (ICS).** Per-user feed URL (Calendar → "Calendar Feed"),
  pasted once into Settings. No token, no admin, no login — the URL carries its own secret,
  and admins cannot disable it. Works on locked-down student accounts.
- Fetched **client-side** on the same triggers as Apple/Google calendar (launch / focus /
  refresh / manual). No scheduled Edge Function needed — there is no server-side secret.
- Canvas is a third live read-only calendar **source** (`EventSource.canvas`), alongside
  Apple (EventKit) and Google.

## Setting

- **Canvas assignments to show:** *All courses* (default) / *Only linked courses*.

## Resolved from the old open questions

- **Class meeting times:** surfaced only if cleanly present in the feed (not all schools
  expose them) — best-effort, not required.
- **De-duping vs. Google/Apple:** Atlas ingests the feed itself and tags items
  `source = .canvas`; users should **not** also subscribe the same feed into Google/Apple,
  which would double-show and mislabel it.
