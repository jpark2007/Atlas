-- ============================================================
-- Collaboration Phase 3: availability publishing
-- 1) availability_blocks: anonymized busy intervals (no titles), published
--    by each user's own device for a rolling 14-day window.
-- 2) sharing_prefs: per-membership detail level (busy_only default).
-- 3) RLS: a user's availability_blocks are readable by anyone who shares
--    at least one project with them (via is_project_member(), from 0016).
-- Idempotent: safe to re-run.
-- ============================================================

-- ── 1. availability_blocks ──────────────────────────────────
create table if not exists availability_blocks (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null default auth.uid() references auth.users on delete cascade,
    start_at   timestamptz not null,
    end_at     timestamptz not null,
    source     text not null check (source in ('apple', 'google', 'atlas')),
    updated_at timestamptz not null default now()
);

create index if not exists availability_blocks_user_id_idx on availability_blocks(user_id);
create index if not exists availability_blocks_start_at_idx on availability_blocks(start_at);

alter table availability_blocks enable row level security;

-- Self: full access to your own published blocks (the publisher deletes and
-- re-inserts its own window on every publish).
drop policy if exists "availability_blocks: self access" on availability_blocks;
create policy "availability_blocks: self access" on availability_blocks
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Co-members: read-only access to a teammate's blocks, gated by sharing at
-- least one project. Reuses is_project_member() from migration 0016 — a
-- co-member relationship exists if BOTH users are members of the same
-- project (the viewer is a member of some project P, and the block owner is
-- also a member of that same P).
drop policy if exists "availability_blocks: co-member read" on availability_blocks;
create policy "availability_blocks: co-member read" on availability_blocks
    for select
    using (
        exists (
            select 1 from project_members mine
            join project_members theirs
              on theirs.project_id = mine.project_id
            where mine.user_id = auth.uid()
              and theirs.user_id = availability_blocks.user_id
        )
    );

-- ── 2. sharing_prefs ─────────────────────────────────────────
create table if not exists sharing_prefs (
    user_id      uuid not null default auth.uid() references auth.users on delete cascade,
    kind         text not null check (kind in ('space', 'project')),
    target_id    uuid not null,
    detail_level text not null default 'busy_only' check (detail_level in ('busy_only', 'details')),
    primary key (user_id, kind, target_id)
);

alter table sharing_prefs enable row level security;

-- Self: full access to your own preference rows.
drop policy if exists "sharing_prefs: self access" on sharing_prefs;
create policy "sharing_prefs: self access" on sharing_prefs
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Co-members: read-only, so a project's UI can tell whether a teammate has
-- opted into `details` for THIS project before requesting their event titles.
drop policy if exists "sharing_prefs: co-member read" on sharing_prefs;
create policy "sharing_prefs: co-member read" on sharing_prefs
    for select
    using (
        kind = 'project' and exists (
            select 1 from project_members pm
            where pm.project_id = sharing_prefs.target_id and pm.user_id = auth.uid()
        )
    );
