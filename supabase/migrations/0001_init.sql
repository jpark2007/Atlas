-- ============================================================
-- Atlas Daily-Driver v1 — initial schema
-- Run once against a fresh Supabase project (or via supabase db push).
-- Every table uses auth.uid() default for user_id and RLS to restrict
-- rows to their owner.  Color is NEVER persisted except spaces.color_token.
-- ============================================================

-- ── spaces ──────────────────────────────────────────────────
create table if not exists spaces (
    id          uuid        primary key,
    user_id     uuid        not null default auth.uid()
                            references auth.users on delete cascade,
    name        text        not null,
    color_token text        not null default 'accent',
    sort        int         not null default 0
);

alter table spaces enable row level security;
create policy "spaces: owner access" on spaces
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── projects ─────────────────────────────────────────────────
-- Denormalized by space name (NOT a space_id FK) — keeps mapping simple
-- and matches the domain model.  Task 2 re-nests via spaceName after load.
create table if not exists projects (
    id             uuid    primary key,
    user_id        uuid    not null default auth.uid()
                           references auth.users on delete cascade,
    space_name     text    not null,
    name           text    not null,
    code           text,
    is_class       bool    not null default false,
    meeting_info   text,
    instructor     text,
    canvas_synced  bool    not null default false,
    overview       text    not null default ''
);

alter table projects enable row level security;
create policy "projects: owner access" on projects
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── tasks ────────────────────────────────────────────────────
create table if not exists tasks (
    id           uuid        primary key,
    user_id      uuid        not null default auth.uid()
                             references auth.users on delete cascade,
    project_id   uuid,       -- nullable FK, reserved for future linking (map to nil for now)
    space_name   text        not null,
    title        text        not null,
    due_date     timestamptz,
    status       text        not null default 'open',
    done         bool        not null default false,
    scheduled_at timestamptz
);

alter table tasks enable row level security;
create policy "tasks: owner access" on tasks
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── events ───────────────────────────────────────────────────
-- notes/is_all_day/project_id columns exist in schema for completeness;
-- init(domain:) writes nil/false until Task 5 adds those fields to CalendarEvent.
create table if not exists events (
    id          uuid        primary key,
    user_id     uuid        not null default auth.uid()
                            references auth.users on delete cascade,
    space_name  text        not null,
    title       text        not null,
    subtitle    text        not null default '',
    start_at    timestamptz not null,
    end_at      timestamptz not null,
    notes       text,
    is_all_day  bool        not null default false,
    project_id  uuid        -- nullable FK, reserved for future linking (map to nil for now)
);

alter table events enable row level security;
create policy "events: owner access" on events
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── notes ────────────────────────────────────────────────────
create table if not exists notes (
    id          uuid        primary key,
    user_id     uuid        not null default auth.uid()
                            references auth.users on delete cascade,
    space_name  text,       -- nullable: loose notes have no space
    project_id  uuid,       -- nullable FK, reserved for future linking (map to nil for now)
    title       text        not null,
    body        text        not null default '',
    updated_at  timestamptz not null,
    is_external bool        not null default false
);

alter table notes enable row level security;
create policy "notes: owner access" on notes
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── goals ────────────────────────────────────────────────────
create table if not exists goals (
    id       uuid    primary key,
    user_id  uuid    not null default auth.uid()
                     references auth.users on delete cascade,
    title    text    not null,
    progress float8  not null default 0,
    label    text    not null default ''
);

alter table goals enable row level security;
create policy "goals: owner access" on goals
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ── pinned_resources ──────────────────────────────────────────
-- Schema completeness only — v1 does not write to this table yet.
create table if not exists pinned_resources (
    id           uuid    primary key,
    user_id      uuid    not null default auth.uid()
                         references auth.users on delete cascade,
    project_id   uuid,
    title        text    not null,
    source       text    not null,
    system_image text    not null default 'link'
);

alter table pinned_resources enable row level security;
create policy "pinned_resources: owner access" on pinned_resources
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);
