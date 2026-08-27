-- ============================================================
-- 0044_syllabus_storage.sql — keep the syllabus the scan was read from
--
-- The syllabus scan reads pages and throws them away. The document itself
-- is the thing a student goes back to ("what exactly does the attendance
-- policy say?"), so it is now KEPT:
--
--   1. `syllabi` — a PRIVATE storage bucket. Objects are laid out as
--                  `{user_id}/{project_id}/syllabus.{ext}`, so the owner
--                  check is the first path segment. Owner-only: no public
--                  reads, no cross-user reads, ever.
--   2. `projects.syllabus_path` — the pointer. NULL means "no syllabus
--                  stored" (every existing class). A rescan overwrites
--                  the same object; there is no versioning by design.
--
-- Idempotent; safe to re-run.
-- ============================================================

-- ── 1. the pointer column ───────────────────────────────────

alter table projects add column if not exists syllabus_path text;

comment on column projects.syllabus_path is
  'Object path in the private `syllabi` bucket for the file this class''s '
  'syllabus scan was read from. NULL = nothing stored. Shape: '
  '{user_id}/{project_id}/syllabus.{ext}. Overwritten on rescan.';

-- ── 2. the bucket ───────────────────────────────────────────
-- Private (public = false): every read goes through RLS below, so a leaked
-- path is not a leaked document.

insert into storage.buckets (id, name, public)
values ('syllabi', 'syllabi', false)
on conflict (id) do update set public = false;

-- ── 3. owner-only RLS on the objects ────────────────────────
-- `storage.objects` already has RLS enabled by the storage extension; these
-- policies scope the `syllabi` bucket to the folder named after the caller.
-- `(storage.foldername(name))[1]` is the first path segment — the user id.

drop policy if exists "syllabi owner read"   on storage.objects;
drop policy if exists "syllabi owner insert" on storage.objects;
drop policy if exists "syllabi owner update" on storage.objects;
drop policy if exists "syllabi owner delete" on storage.objects;

create policy "syllabi owner read" on storage.objects
  for select to authenticated
  using (bucket_id = 'syllabi'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "syllabi owner insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'syllabi'
              and (storage.foldername(name))[1] = auth.uid()::text);

-- Rescan is an upsert, which storage performs as an UPDATE on the existing
-- object — without this a second scan of the same class would 403.
create policy "syllabi owner update" on storage.objects
  for update to authenticated
  using (bucket_id = 'syllabi'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'syllabi'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "syllabi owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'syllabi'
         and (storage.foldername(name))[1] = auth.uid()::text);
