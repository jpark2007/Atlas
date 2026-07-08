-- 0020_doc_note_tabs.sql
-- Per-tab storage for multi-tab Google Doc notes (Option C).
-- One row per Docs tab, keyed by the stable Docs tabId. body_md is the tab's
-- content in the RichDocMarkdown dialect. `writable` is computed at pull time
-- from the tab's ACTUAL structure (tables/images/exotic formatting => false)
-- and re-verified server-side at write time — never hardcoded.

create table if not exists doc_note_tabs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  reference_id  uuid not null references project_references(id) on delete cascade,
  tab_id        text not null,
  parent_tab_id text,
  title         text not null default '',
  ord           integer not null default 0,
  body_md       text not null default '',
  writable      boolean not null default true,
  readonly_reason text,
  updated_at    timestamptz not null default now(),
  unique (reference_id, tab_id)
);

create index if not exists doc_note_tabs_reference_idx on doc_note_tabs (reference_id);

alter table doc_note_tabs enable row level security;

-- Clients only ever READ tabs; all writes flow through service-role edge functions.
drop policy if exists "doc_note_tabs: owner reads" on doc_note_tabs;
create policy "doc_note_tabs: owner reads" on doc_note_tabs
  for select using (user_id = auth.uid());
