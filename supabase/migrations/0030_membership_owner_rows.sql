-- ============================================================
-- 0030 — Auto-create owner membership rows for new spaces/projects
-- The gap: space_members/project_members owner rows were only ever
-- minted by the one-time backfills in 0021/0016 and by accept_invite()
-- (0016 §6, 0021 §4). Nothing creates an owner row for a space or
-- project created AFTER those migrations — no trigger, and the clients
-- (AtlasDB.upsertSpace/upsertProject) write only the entity row.
-- Consequence: the invites INSERT policy demands is_space_member(target_id)
-- / is_project_member(target_id) (0021 §4, 0016 §2), so the owner of any
-- post-backfill space/project is silently RLS-rejected when inviting —
-- prod's invites table has been empty since launch. The 0024 signup seed
-- inherits the gap, so every new account is born un-shareable.
-- 1) AFTER INSERT triggers on spaces/projects → mint the owner row.
-- 2) One-time backfill for existing entities missing an owner row,
--    mirroring 0016 §1 / 0021 §1.
-- Idempotent: safe to re-run.
-- ============================================================

-- ── 1. Owner-row triggers ────────────────────────────────────
-- security definer for the same chicken-and-egg reason accept_invite() is
-- (0016 §6): space_members/project_members' "owner manages" WITH CHECK
-- requires is_space_owner()/is_project_owner(), which is false until the
-- very row we're inserting exists. An invoker-rights trigger would be
-- RLS-rejected on the authenticated-client insert path. definer (owned by
-- a role that bypasses RLS) makes the insert succeed in BOTH contexts —
-- the authenticated owner's client write, and the 0024 seed trigger which
-- itself runs as definer with auth.uid() = null. ON CONFLICT keeps it safe
-- against the 0016/0021 backfills, this file's own backfill, and races.
create or replace function public.handle_new_space_owner()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into space_members (space_id, user_id, role)
    values (new.id, new.user_id, 'owner')
    on conflict (space_id, user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_space_created_owner on spaces;
create trigger on_space_created_owner
    after insert on spaces
    for each row execute function public.handle_new_space_owner();

create or replace function public.handle_new_project_owner()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into project_members (project_id, user_id, role)
    values (new.id, new.user_id, 'owner')
    on conflict (project_id, user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_project_created_owner on projects;
create trigger on_project_created_owner
    after insert on projects
    for each row execute function public.handle_new_project_owner();

-- ── 2. Backfill missing owner rows ───────────────────────────
-- Heal every space/project that predates this trigger and lacks its
-- creator's owner row (mirrors 0021 §1 / 0016 §1).
insert into space_members (space_id, user_id, role)
select s.id, s.user_id, 'owner' from spaces s
on conflict (space_id, user_id) do nothing;

insert into project_members (project_id, user_id, role)
select p.id, p.user_id, 'owner' from projects p
on conflict (project_id, user_id) do nothing;
