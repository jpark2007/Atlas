-- 0023_doc_images_and_note_keyed_tabs.sql
-- v2: (a) key doc tabs by NOTE so one Doc imported into many projects shares one
-- note + one tab set; (b) doc_note_images — re-hosted copies of Doc images
-- (downloaded at pull time while contentUri is fresh, stored in the private
-- doc-images bucket, re-inserted into the Doc at write time); (c) the bucket.

-- (a) note-keyed tabs
alter table doc_note_tabs add column if not exists note_id uuid references notes(id) on delete cascade;
update doc_note_tabs t
   set note_id = r.note_id
  from project_references r
 where r.id = t.reference_id and t.note_id is null;
delete from doc_note_tabs where note_id is null;  -- orphans (reference without note)
alter table doc_note_tabs alter column note_id set not null;
alter table doc_note_tabs alter column reference_id drop not null;
create unique index if not exists doc_note_tabs_note_tab_key on doc_note_tabs (note_id, tab_id);
create index if not exists doc_note_tabs_note_idx on doc_note_tabs (note_id);

-- (b) image map
create table if not exists doc_note_images (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  note_id       uuid not null references notes(id) on delete cascade,
  tab_id        text not null,
  object_id     text not null,           -- Docs inlineObject id at pull time
  storage_path  text not null,           -- doc-images object key: <user_id>/<note_id>/<object_id>.<ext>
  width_pt      numeric,                 -- EmbeddedObject.size at pull, preserved on re-insert
  height_pt     numeric,
  crop_locked   boolean not null default false, -- image has crop/rotation/adjustments -> tab read-only
  created_at    timestamptz not null default now(),
  unique (note_id, object_id)
);
create index if not exists doc_note_images_note_idx on doc_note_images (note_id);
alter table doc_note_images enable row level security;
drop policy if exists "doc_note_images: owner reads" on doc_note_images;
create policy "doc_note_images: owner reads" on doc_note_images
  for select using (user_id = auth.uid());

-- (c) private bucket + owner read (writes are service-role only, which bypasses RLS)
insert into storage.buckets (id, name, public)
values ('doc-images', 'doc-images', false)
on conflict (id) do nothing;
drop policy if exists "doc-images: owner reads" on storage.objects;
create policy "doc-images: owner reads" on storage.objects
  for select using (bucket_id = 'doc-images' and (storage.foldername(name))[1] = auth.uid()::text);
