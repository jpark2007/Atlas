-- ============================================================
-- 0015 — Collaboration Phase 1 foundations
-- 1) space_id FK columns on projects/tasks/events/notes (nullable,
--    dual-written with space_name until Phase 2 drops the text columns).
-- 2) Backfill space_id from (user_id, space_name).
-- 3) profiles: public identity per user, auto-created on signup.
-- Idempotent: safe to re-run.
-- ============================================================

-- ── 1. space_id columns ─────────────────────────────────────
alter table projects add column if not exists space_id uuid references spaces(id) on delete set null;
alter table tasks    add column if not exists space_id uuid references spaces(id) on delete set null;
alter table events   add column if not exists space_id uuid references spaces(id) on delete set null;
alter table notes    add column if not exists space_id uuid references spaces(id) on delete set null;

create index if not exists projects_space_id_idx on projects(space_id);
create index if not exists tasks_space_id_idx    on tasks(space_id);
create index if not exists events_space_id_idx   on events(space_id);
create index if not exists notes_space_id_idx    on notes(space_id);

-- ── 2. Backfill by owner + name ─────────────────────────────
update projects p set space_id = s.id
from spaces s
where p.space_id is null and s.user_id = p.user_id and s.name = p.space_name;

update tasks t set space_id = s.id
from spaces s
where t.space_id is null and s.user_id = t.user_id and s.name = t.space_name;

update events e set space_id = s.id
from spaces s
where e.space_id is null and s.user_id = e.user_id and s.name = e.space_name;

-- notes.space_name is nullable (loose notes) — the join naturally skips NULLs.
update notes n set space_id = s.id
from spaces s
where n.space_id is null and s.user_id = n.user_id and s.name = n.space_name;

-- ── 3. profiles ─────────────────────────────────────────────
create table if not exists profiles (
    user_id      uuid primary key references auth.users on delete cascade,
    display_name text not null default '',
    email        text not null default '',
    avatar_color text not null default 'accent'
);

alter table profiles enable row level security;

-- Phase 1: self-only. Phase 2 widens SELECT to co-members.
drop policy if exists "profiles: self access" on profiles;
create policy "profiles: self access" on profiles
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Auto-create a profile on signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (user_id, email)
    values (new.id, coalesce(new.email, ''))
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Backfill profiles for existing users.
insert into profiles (user_id, email)
select id, coalesce(email, '') from auth.users
on conflict (user_id) do nothing;
