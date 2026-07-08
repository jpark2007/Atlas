-- ============================================================
-- Phase 4 RLS verification — run against a SCRATCH database only
-- (never production). Seeds two users and a shared space, then
-- asserts the access patterns this phase's migration enforces.
--
-- Usage: same as phase2_rls_test.sql — run via `supabase db query
-- --linked --file` against a disposable branch, or the Supabase SQL
-- editor's "run as user" impersonation, substituting real UUIDs.
-- ============================================================

-- 1. Seed: owner creates a space + a project INSIDE that space (no
--    separate project_members row); member is added via space_members only.
-- insert into spaces (id, user_id, name) values ('...', :'owner_id', 'Test Space');
-- insert into projects (id, user_id, space_id, name, is_class) values ('...', :'owner_id', '...', 'Space Project', false);
-- insert into space_members (space_id, user_id, role) values ('...', :'owner_id', 'owner'), ('...', :'member_id', 'member');

-- 2. Assert: space member CAN read the project INSIDE the shared space,
--    even though they were never added to that project's project_members.
-- set local request.jwt.claims = '{"sub": ":member_id"}';
-- select count(*) = 1 from projects where id = '...'; -- expect 1

-- 3. Assert: space member CAN read/write a task inside that project.
-- insert into tasks (id, user_id, project_id, space_id, title) values ('...', :'member_id', '...', '...', 'Space-member task'); -- expect success

-- 4. Assert: outsider (neither project- nor space-member) CANNOT read
--    the space, the project, or its tasks.
-- set local request.jwt.claims = '{"sub": ":outsider_id"}';
-- select count(*) = 0 from spaces   where id = '...'; -- expect 0
-- select count(*) = 0 from projects where id = '...'; -- expect 0

-- 5. Assert: a Phase 2 project-only member (added via project_members,
--    NOT space_members) still retains their existing project access —
--    confirms this phase's widening didn't regress Phase 2's grants.
-- (seed a separate project NOT in the shared space, add member via
--  project_members only, confirm they can still read/write it)

-- 6. Assert: space invite creation/accept round-trip works end-to-end.
-- (seed an invite with kind='space', target_id=the space id, accept via
--  accept_invite() as the invitee, confirm a space_members row appears)
