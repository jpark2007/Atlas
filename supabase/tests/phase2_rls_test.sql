-- ============================================================
-- Phase 2 RLS verification — run against a SCRATCH database only
-- (never production). Seeds two users and a shared project, then
-- asserts the access patterns migration 0016 is supposed to enforce.
--
-- Usage: run each block manually via `supabase db query --linked --file`
-- (against a disposable branch/scratch project) or through the Supabase
-- SQL editor's "run as user" impersonation, substituting real UUIDs for
-- the placeholders below after seeding two real auth.users rows.
-- ============================================================

-- Placeholders — replace with two real auth.users ids from your scratch project:
-- \set owner_id '00000000-0000-0000-0000-000000000001'
-- \set member_id '00000000-0000-0000-0000-000000000002'
-- \set outsider_id '00000000-0000-0000-0000-000000000003'

-- 1. Seed: owner creates a space + project; member is added via project_members.
-- insert into spaces (id, user_id, name) values ('...', :'owner_id', 'Test Space');
-- insert into projects (id, user_id, space_id, name, is_class) values ('...', :'owner_id', '...', 'Shared Project', false);
-- insert into project_members (project_id, user_id, role) values ('...', :'owner_id', 'owner'), ('...', :'member_id', 'member');

-- 2. Assert: member CAN read the shared project.
-- set local role authenticated; set local request.jwt.claims = '{"sub": ":member_id"}';
-- select count(*) = 1 from projects where id = '...'; -- expect 1

-- 3. Assert: outsider CANNOT read the shared project.
-- set local request.jwt.claims = '{"sub": ":outsider_id"}';
-- select count(*) = 0 from projects where id = '...'; -- expect 0 (RLS filters it out)

-- 4. Assert: member CAN insert a task into the shared project.
-- set local request.jwt.claims = '{"sub": ":member_id"}';
-- insert into tasks (id, user_id, project_id, space_id, title) values ('...', :'member_id', '...', '...', 'Member-created task'); -- expect success

-- 5. Assert: member CANNOT delete the project itself (owner-only per Task 1's
--    project_members RLS intent — projects RLS uses is_project_member() for
--    ALL operations, so re-check whether this needs a stricter delete-only
--    policy split if the human wants members unable to delete the project;
--    flag this as an open question in your report, don't silently add a
--    stricter policy not in Task 1's migration).

-- 6. Assert: member CAN see the project_members roster.
-- select count(*) = 2 from project_members where project_id = '...'; -- expect 2

-- 7. Assert: an invite addressed to a different email is invisible to member.
-- (seed an invite with invitee_email = 'someone-else@example.com', then
--  confirm the member's select returns 0 rows for it)
