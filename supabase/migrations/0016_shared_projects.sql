-- ============================================================
-- 0016 — Collaboration Phase 2: shared projects
-- 1) project_members: who belongs to a shared project, and their role.
-- 2) invites: pending/accepted/declined invitations (email-based).
-- 3) Attribution columns: tasks.assignee_id/created_by, events.created_by.
-- 4) is_project_member() helper (security definer, avoids recursive RLS).
-- 5) Widen projects/tasks/events/notes RLS: owner OR project member.
-- Idempotent: safe to re-run.
-- ============================================================

-- ── 1. project_members ──────────────────────────────────────
create table if not exists project_members (
    project_id uuid not null references projects(id) on delete cascade,
    user_id    uuid not null references auth.users on delete cascade,
    role       text not null default 'member' check (role in ('owner', 'member')),
    added_at   timestamptz not null default now(),
    primary key (project_id, user_id)
);

create index if not exists project_members_user_id_idx on project_members(user_id);

alter table project_members enable row level security;

-- Members can see the roster of any project they belong to.
drop policy if exists "project_members: member read" on project_members;
create policy "project_members: member read" on project_members
    for select
    using (
        exists (
            select 1 from project_members pm
            where pm.project_id = project_members.project_id
              and pm.user_id = auth.uid()
        )
    );

-- Only the project's owner-member row can insert/delete membership rows.
drop policy if exists "project_members: owner manages" on project_members;
create policy "project_members: owner manages" on project_members
    for all
    using (
        exists (
            select 1 from project_members pm
            where pm.project_id = project_members.project_id
              and pm.user_id = auth.uid()
              and pm.role = 'owner'
        )
        or project_members.user_id = auth.uid() -- a user can always remove themselves (leave)
    )
    with check (
        exists (
            select 1 from project_members pm
            where pm.project_id = project_members.project_id
              and pm.user_id = auth.uid()
              and pm.role = 'owner'
        )
    );

-- Every existing project's creator becomes its owner-member row.
insert into project_members (project_id, user_id, role)
select p.id, p.user_id, 'owner' from projects p
on conflict (project_id, user_id) do nothing;

-- ── 2. invites ───────────────────────────────────────────────
create table if not exists invites (
    id            uuid primary key default gen_random_uuid(),
    kind          text not null check (kind in ('space', 'project')),
    target_id     uuid not null,
    inviter_id    uuid not null references auth.users on delete cascade,
    invitee_email text not null,
    status        text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
    created_at    timestamptz not null default now()
);

create index if not exists invites_invitee_email_idx on invites(invitee_email);
create index if not exists invites_target_id_idx on invites(target_id);

alter table invites enable row level security;

-- The inviter can see invites they sent; the invitee can see invites addressed
-- to their own verified email (auth.jwt() carries the signed-in user's email).
drop policy if exists "invites: inviter and invitee read" on invites;
create policy "invites: inviter and invitee read" on invites
    for select
    using (
        inviter_id = auth.uid()
        or invitee_email = (auth.jwt() ->> 'email')
    );

-- Only an existing project member can create an invite for that project.
drop policy if exists "invites: member creates" on invites;
create policy "invites: member creates" on invites
    for insert
    with check (
        inviter_id = auth.uid()
        and (
            (kind = 'project' and exists (
                select 1 from project_members pm
                where pm.project_id = invites.target_id and pm.user_id = auth.uid()
            ))
        )
    );

-- The invitee can update (accept/decline) only their own pending invite.
drop policy if exists "invites: invitee responds" on invites;
create policy "invites: invitee responds" on invites
    for update
    using (invitee_email = (auth.jwt() ->> 'email') and status = 'pending')
    with check (invitee_email = (auth.jwt() ->> 'email'));

-- ── 3. Attribution columns ──────────────────────────────────
alter table tasks  add column if not exists assignee_id uuid references auth.users on delete set null;
alter table tasks  add column if not exists created_by  uuid references auth.users;
alter table events add column if not exists created_by  uuid references auth.users;

update tasks  set created_by = user_id where created_by is null;
update events set created_by = user_id where created_by is null;

-- ── 4. is_project_member() helper ───────────────────────────
-- security definer so it can be called from RLS policies on OTHER tables
-- (projects/tasks/events/notes) without those policies needing direct
-- select-grants on project_members, and without recursive-policy issues.
create or replace function public.is_project_member(pid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
    select exists (
        select 1 from project_members
        where project_id = pid and user_id = auth.uid()
    );
$$;

-- ── 5. Widen RLS: owner OR project member ───────────────────
drop policy if exists "projects: owner access" on projects;
create policy "projects: owner access" on projects
    for all
    using  (auth.uid() = user_id or is_project_member(id))
    with check (auth.uid() = user_id or is_project_member(id));

drop policy if exists "tasks: owner access" on tasks;
create policy "tasks: owner access" on tasks
    for all
    using  (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)))
    with check (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)));

drop policy if exists "events: owner access" on events;
create policy "events: owner access" on events
    for all
    using  (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)))
    with check (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)));

drop policy if exists "notes: owner access" on notes;
create policy "notes: owner access" on notes
    for all
    using  (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)))
    with check (auth.uid() = user_id or (project_id is not null and is_project_member(project_id)));

-- ── 6. accept_invite() — server-side accept path ────────────
-- Accepting an invite grants membership even though the invitee isn't yet a
-- member (and so couldn't satisfy project_members' owner-only insert policy).
-- security definer lets this bypass that policy specifically for the
-- accept-your-own-invite case, which invites' own RLS already gates.
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
    end if;
end;
$$;
