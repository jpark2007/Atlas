# Collaboration — Shared Spaces, Group Projects & Availability

**Date:** 2026-07-05
**Status:** Approved design, pending implementation plan
**Supersedes/extends:** `docs/specs/07-social.md` (vision sketch → concrete design)

## Summary

Atlas users can share a single project or an entire space with other Atlas
users. Members see shared tasks (with assignees), shared events, shared notes,
and each other's availability — free/busy blocks plus fully-detailed
project-specific work blocks, never the contents of private calendars unless a
member opts in. Everything lives in one interface: a **Team view** inside the
shared project/space.

Decisions made during brainstorming:

- **Scope:** full architecture designed now, implemented in 4 phases.
- **Availability:** anonymized free/busy published from each device; each
  member chooses detail level per membership (`busy_only` default, `details`
  opt-in).
- **Invites:** email invite + in-app accept/decline. No separate friends
  system in v1 — membership is the relationship.
- **Roles:** owner + member. Owner manages membership and deletes the
  container; members create/edit shared content.
- **Tasks:** shared tasks are assignable; unassigned tasks are claimable.
- **Sync:** Supabase Realtime push on shared tables.
- **Architecture:** extend existing tables with membership junctions
  (approach A) — no parallel "shared" tables, no CRDTs.
- **UI:** minimalist, clean, vintage/editorial — aligned with
  `docs/archive/specs/2026-07-03-mac-editorial-light-design.md`.

## 1. Data model & permissions

### Foundation migration (prerequisite)

`projects`, `tasks`, `events`, `notes` currently reference spaces by
denormalized `space_name` text. Names collide across users, so sharing
requires real keys:

- Add `space_id uuid references spaces(id)` to all four tables.
- Backfill: map each row's `space_name` to its owner's space of that name.
- Keep `space_name` temporarily for backward compat; drop in a later
  migration once clients are updated.
- Client models switch from `spaceName` strings to IDs, resolving names at
  load.

### New tables

| Table | Shape | Purpose |
|---|---|---|
| `profiles` | `user_id`, `display_name`, `email`, `avatar_color` | Public identity so members can see who someone is. |
| `space_members` | `space_id`, `user_id`, `role: owner\|member` | Whole-space sharing; sharing a space shares everything in it. |
| `project_members` | `project_id`, `user_id`, `role: owner\|member` | Single-project sharing without sharing its space. Appears for invitees under a system "Shared with me" space. |
| `invites` | `id`, `kind: space\|project`, `target_id`, `inviter_id`, `invitee_email`, `status: pending\|accepted\|declined`, `created_at` | Email invite flow. Accepting writes the membership row. Invites to unregistered emails resolve on signup. Single-use, expire after 14 days. |
| `availability_blocks` | `user_id`, `start_at`, `end_at`, `source: apple\|google\|atlas`, `updated_at` | Anonymized busy intervals — never titles. |
| `sharing_prefs` | `user_id`, `kind: space\|project`, `target_id`, `detail_level: busy_only\|details` | Member-chosen availability granularity per membership. Default `busy_only`. |

### Attribution columns

- Shared `tasks` gain `assignee_id` and `created_by`.
- Shared `events` gain `created_by`.
- `user_id` remains the row owner (creator) — consistent with the existing
  ingest-time attribution rule (CLAUDE.md §5: never mislabel a source).

### RLS

- Content tables widen from owner-only to: *owner, or member of the row's
  space, or member of the row's project*.
- Implemented via `security definer` helper functions
  (`is_space_member(space_id)`, `is_project_member(project_id)`) to avoid
  recursive policy lookups (standard Supabase pattern).
- Writes: members can insert/update content inside shared containers; only
  owners delete the container or manage membership.
- `availability_blocks`: readable only by users sharing ≥1 space/project with
  the row's owner.

## 2. Availability system

### Publishing (client → server)

- New `AvailabilityPublisher` service in the Mac app derives anonymized busy
  intervals from the locally-merged calendar set (Atlas events, Google
  events, EventKit/Apple events, scheduled work blocks).
- Window: rolling **next 14 days**.
- Triggers: app launch, any local calendar change (debounced), periodic
  refresh.
- Write strategy: delete-then-insert per window — simple, self-healing, no
  per-event diffing.
- Excluded from busy: all-day events, deadline markers.
- Payload: start, end, source. **Never titles.**

### Project-specific blocks

Work blocks scheduled against a shared project's tasks are real rows in the
shared `events`/`tasks` tables, so teammates see them with full detail (task
title, assignee). Availability blocks cover everything else as anonymous
"busy."

### Reading (server → client)

For a shared container, the client fetches members' `availability_blocks`
for the visible range plus shared project events. If a member's
`sharing_prefs` is `details`, their Atlas-event titles are additionally
visible (second query permitted by RLS).

### Display merging rule

Per teammate column: shared project blocks (detailed, colored) > busy blocks
(neutral, anonymous) > free (empty). Overlaps collapse; anonymous blocks are
visually quiet.

### Non-choices

Google's free/busy API is deliberately **not** used — client-side publishing
gives one code path covering Apple + Google + Atlas uniformly and works for
members without Google connected.

### Staleness

Each member's published window carries `updated_at`; if >48h stale, their
column shows a subtle "as of Tuesday" annotation instead of pretending to be
current.

## 3. Shared interface (UX)

Design language: minimalist, clean, vintage — per the editorial light design
spec (paper background, serif/small-caps headers, hairline rules).

### Sidebar

- Shared spaces/projects: existing rows plus a small overlapping-initials
  cluster (tiny serif-initial circles, ink-on-paper tone). No "SHARED"
  badges.
- Projects shared with you: a "Shared with me" section.
- Pending invites: one understated row at the sidebar bottom
  ("1 invitation") opening an accept/decline sheet.

### Team view

A new tab inside a shared project/space (alongside Overview/Tasks/Notes):

- **"The Week" (top band):** horizontal availability grid. One row per
  member — small-caps name in the left margin like a ledger column, days
  across. Anonymous busy = quiet hatched/tinted rectangles (pencil-shading
  feel); shared project blocks = solid ink-toned blocks with task titles;
  free = bare paper. Hairline rule under the band. Click-drag across a
  shared free gap proposes a meeting event pre-filled with those attendees.
- **"The Ledger" (below):** shared task list typeset like a classic index —
  rule-separated rows, checkbox, title, assignee initials at the right
  margin, due date in the numeric style. Unassigned tasks show a hollow
  circle; click to claim. Grouped Open / Claimed / Done.

### Attribution elsewhere

Teammate-created events/notes show tiny initials in their detail view only.
Realtime changes appear without animation fanfare.

## 4. Phasing

Each phase independently shippable:

1. **Foundations** — `space_id` migration + backfill, `profiles`, client
   model switch to IDs. Zero visible change.
2. **Shared projects** — invites, `project_members`, RLS widening,
   assignee/claiming, "Shared with me," realtime subscriptions.
3. **Availability + Team view** — `AvailabilityPublisher`,
   `availability_blocks`, Week band + Ledger, meeting proposal from a gap.
4. **Shared spaces + preferences** — `space_members`, `sharing_prefs` detail
   levels, staleness annotations, polish.

## 5. Error handling

- **Membership revoked mid-session:** realtime delivers the removal; client
  drops the shared container from state gracefully.
- **Invite edges:** re-inviting an existing member no-ops; invites single-use,
  expire after 14 days; declining leaves no trace for the invitee.
- **Publisher failures:** fire-and-forget with silent retry; never blocks or
  alerts. Staleness annotation is the honest fallback.
- **Offline writes to shared content:** existing local-first pattern;
  last-write-wins on sync (acceptable for row-shaped task/event data).

## 6. Testing

- **RLS (the security boundary):** SQL test script with two seeded users
  asserting member-can-read, non-member-cannot, member-cannot-delete-
  container, availability visible only with shared membership.
- **AtlasCore unit tests:** busy-interval derivation/merging/windowing;
  invite state machine.
- **UI:** green build, then user visual confirmation (house rule — Team view
  especially).
