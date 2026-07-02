# Server-Side Canvas ICS Sync — Design

**Date:** 2026-07-02 · **Status:** approved to build AFTER Google sync ships (same rails)
**Ground truth:** `.superpowers/sdd/sync-architecture-brief.md` §6 + `docs/superpowers/specs/2026-07-01-canvas-ics-sync-design.md` (the client-side v1 this supersedes).

## Goal

Canvas assignments/events flow into Atlas on a server schedule from the user's Canvas **ICS feed URL** — no OAuth, no Mac open, no Canvas-admin cooperation. Rides the exact cron/edge rails Google sync builds.

## Deltas from the client-side Canvas design

The 2026-07-01 design deliberately kept Canvas v1 client-side and **ephemeral** (parse → display, don't persist). Server-side reverses that: Canvas items must be **persisted, keyed by ICS `UID`** — that's the whole point (phone + widgets see them with nothing open).

## Architecture

1. **Connect:** user pastes their Canvas calendar feed URL (Canvas → Calendar → Calendar Feed) into Mac Settings (phone later). Stored in `canvas_connections`: `user_id PK`, `feed_url` (treat as a secret — it's a capability URL; Vault like the Google token), `space_name` (which Atlas space Canvas items land in, default "School"), `last_synced_at`, `etag/last_modified` (conditional GET cache), `status`, `last_error`. RLS mirrors `google_connections`.
2. **Schema:** `tasks.canvas_uid text` + partial unique index `(user_id, canvas_uid)`; same for `events.canvas_uid` (Canvas feeds carry both assignments → tasks and calendar events → events; the existing client mapper's rules port as-is: VEVENT with due-style semantics → task with dueDate, others → event).
3. **Runner:** `canvas-sync` edge function on the same pg_cron schedule (offset from Google's). Per user: conditional GET the feed (respect etag — Canvas feeds are big and change rarely); parse ICS **in TypeScript** (small purpose-built parser for the VEVENT subset Canvas emits — port the Swift `ICSParser`'s rules; a vendored deno ICS lib is acceptable if it's dependency-light); upsert by `(user_id, canvas_uid)`.
4. **Change semantics (user-data-safe):** new UID → create; changed due date/title → update those fields but NEVER overwrite user-set fields (space, project, notes edits, scheduledAt, done); UID disappears from feed → leave the row alone (Canvas hides past items from feeds routinely — disappearance ≠ deletion). Completed-in-Atlas stays completed even if Canvas re-lists it.
5. **Project routing:** the existing client design's course-code → project matcher ports server-side: match the event's course prefix to the user's project codes (the capture context already models this); unmatched → the connection's `space_name` with no project.
6. **Mac migration:** same single-owner gate pattern as Google — when `canvas_connections.status == 'active'`, the Mac's client-side Canvas ICS polling/ephemeral display turns off; Canvas rows arrive via `loadAll()` like everything else.

## Scale note (from Drew)

Canvas floods tasks. The mobile month dots cap at 3+overflow (done), and this project is the trigger to build the parked mobile items: search, real project grouping, post-commit undo.

## Verification

Seed a real Canvas feed URL (Drew's), deploy, verify: assignments appear as tasks with correct due dates/times (timezone-correct — feeds are UTC/zoned, reuse the tz discipline from capture), completing in Atlas sticks across syncs, feed disappearance deletes nothing, and re-runs are idempotent (unique index).
