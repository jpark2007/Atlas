-- ============================================================
-- 0019 — fix infinite recursion in project_members policies
-- 0016's project_members policies queried project_members inside
-- their own USING clause → Postgres 42P17 ("infinite recursion
-- detected in policy") on EVERY read of the table. The fix is the
-- pattern 0016 itself established in §4: route the membership
-- check through a security-definer helper, which bypasses RLS.
-- Idempotent: safe to re-run.
-- ============================================================

-- Owner-role variant of is_project_member() (0016 §4).
create or replace function public.is_project_owner(pid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
    select exists (
        select 1 from project_members
        where project_id = pid and user_id = auth.uid() and role = 'owner'
    );
$$;

-- Same semantics as 0016 §1, recursion-free.
drop policy if exists "project_members: member read" on project_members;
create policy "project_members: member read" on project_members
    for select
    using (is_project_member(project_id));

drop policy if exists "project_members: owner manages" on project_members;
create policy "project_members: owner manages" on project_members
    for all
    using (
        is_project_owner(project_id)
        or user_id = auth.uid() -- a user can always remove themselves (leave)
    )
    with check (is_project_owner(project_id));
