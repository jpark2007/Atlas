-- ============================================================
-- Collaboration Phase 4: shared spaces
-- 1) space_members: mirrors project_members exactly.
-- 2) is_space_member()/is_space_owner(): security-definer helpers,
--    following the FIXED pattern from 0019 (self-referential policies
--    on space_members itself must use these helpers, never a raw
--    subquery on space_members — that caused 42P17 recursion on
--    project_members before 0019 fixed it).
-- 3) Widen spaces/projects/tasks/events/notes RLS: owner OR
--    project-member (existing, from 0016) OR space-member (new).
-- 4) invites + accept_invite(): activate the kind='space' branch that
--    has been schema-present but dead since 0016.
-- Idempotent: safe to re-run.
-- ============================================================

-- ── 1. space_members ─────────────────────────────────────────
create table if not exists space_members (
    space_id uuid not null references spaces(id) on delete cascade,
    user_id  uuid not null references auth.users on delete cascade,
    role     text not null default 'member' check (role in ('owner', 'member')),
    added_at timestamptz not null default now(),
    primary key (space_id, user_id)
);

create index if not exists space_members_user_id_idx on space_members(user_id);

alter table space_members enable row level security;

-- ── 2. is_space_member() / is_space_owner() ─────────────────
-- security definer + stable, exactly mirroring is_project_member()/
-- is_project_owner() (0016 §4, 0019). Used by space_members' OWN
-- policies below (not just other tables') to avoid the exact recursion
-- bug 0019 fixed on project_members.
create or replace function public.is_space_member(sid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
    select exists (
        select 1 from space_members
        where space_id = sid and user_id = auth.uid()
    );
$$;

create or replace function public.is_space_owner(sid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
    select exists (
        select 1 from space_members
        where space_id = sid and user_id = auth.uid() and role = 'owner'
    );
$$;

-- space_members' own policies route through the helpers above —
-- NOT a raw self-referential subquery on space_members, learning
-- directly from the 0019 incident.
drop policy if exists "space_members: member read" on space_members;
create policy "space_members: member read" on space_members
    for select
    using (is_space_member(space_id));

drop policy if exists "space_members: owner manages" on space_members;
create policy "space_members: owner manages" on space_members
    for all
    using (
        is_space_owner(space_id)
        or user_id = auth.uid() -- a user can always remove themselves (leave)
    )
    with check (is_space_owner(space_id));

-- Every existing space's creator becomes its owner-member row.
insert into space_members (space_id, user_id, role)
select s.id, s.user_id, 'owner' from spaces s
on conflict (space_id, user_id) do nothing;

-- ── 3. Widen RLS: owner OR project-member OR space-member ──────
drop policy if exists "spaces: owner access" on spaces;
create policy "spaces: owner access" on spaces
    for all
    using  (auth.uid() = user_id or is_space_member(id))
    with check (auth.uid() = user_id or is_space_member(id));

drop policy if exists "projects: owner access" on projects;
create policy "projects: owner access" on projects
    for all
    using  (auth.uid() = user_id or is_project_member(id) or (space_id is not null and is_space_member(space_id)))
    with check (auth.uid() = user_id or is_project_member(id) or (space_id is not null and is_space_member(space_id)));

drop policy if exists "tasks: owner access" on tasks;
create policy "tasks: owner access" on tasks
    for all
    using  (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    )
    with check (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    );

drop policy if exists "events: owner access" on events;
create policy "events: owner access" on events
    for all
    using  (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    )
    with check (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    );

drop policy if exists "notes: owner access" on notes;
create policy "notes: owner access" on notes
    for all
    using  (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    )
    with check (
        auth.uid() = user_id
        or (project_id is not null and is_project_member(project_id))
        or (space_id is not null and is_space_member(space_id))
    );

-- ── 4. Activate invites/accept_invite's kind='space' branch ────
-- Insert policy: an existing SPACE member (not just project member)
-- may invite others to that space.
drop policy if exists "invites: member creates" on invites;
create policy "invites: member creates" on invites
    for insert
    with check (
        inviter_id = auth.uid()
        and (
            (kind = 'project' and is_project_member(target_id))
            or (kind = 'space' and is_space_member(target_id))
        )
    );

create or replace function public.accept_invite(invite_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    inv invites%rowtype;
begin
    select * into inv from invites where id = invite_id and invitee_email = (auth.jwt() ->> 'email') and status = 'pending';
    if not found then
        raise exception 'invite not found or not pending';
    end if;

    update invites set status = 'accepted' where id = invite_id;

    if inv.kind = 'project' then
        insert into project_members (project_id, user_id, role)
        values (inv.target_id, auth.uid(), 'member')
        on conflict (project_id, user_id) do nothing;
    elsif inv.kind = 'space' then
        insert into space_members (space_id, user_id, role)
        values (inv.target_id, auth.uid(), 'member')
        on conflict (space_id, user_id) do nothing;
    end if;
end;
$$;
