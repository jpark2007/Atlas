-- ============================================================
-- 0046_syllabus_scans.sql — where an item came from, when a scan made it
--
-- A syllabus/schedule scan commits real tasks and events, and until now those
-- were indistinguishable from hand-typed ones: no way to answer "where did
-- this deadline come from?", and no way to undo an import wholesale.
--
--   1. `syllabus_scans` — one row per COMMIT of the scan sheet. It records the
--                  document the scan was read from (`file_name`) and how the
--                  text got in (`kind`: syllabus / schedule / paste). It is a
--                  receipt, not a job record — nothing writes it but the commit.
--   2. `tasks.scan_id` / `events.scan_id` — nullable pointers back at that
--                  receipt. NULL is the norm: every hand-made item, every
--                  Canvas item (those already carry `canvas_uid`/`canvas_course`),
--                  and every row that predates this migration.
--
-- `on delete set null`, deliberately: deleting the receipt must never delete a
-- student's coursework. Removing what a scan added is a later, explicit action
-- with its own UI — not a foreign-key side effect.
--
-- Provenance is only ever STAMPED at creation, never inferred later: an item
-- with no scan_id and no canvas_uid is hand-made and displays no source at all
-- (CLAUDE.md rule 5 — never label a source the data doesn't prove).
--
-- Idempotent; safe to re-run.
-- ============================================================

-- ── 1. the receipt ──────────────────────────────────────────

create table if not exists syllabus_scans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,
  -- The class this scan was committed against. `on delete set null` so deleting
  -- a class leaves its scan history readable rather than vanishing mid-audit.
  project_id  uuid references projects(id) on delete set null,
  -- What the user actually handed Atlas: the picked file's name ("BIO101
  -- syllabus.pdf"), or "Pasted text" when there was no file. Display copy —
  -- the stored document itself lives in the `syllabi` bucket (0044).
  file_name   text not null,
  -- How the text got in. Open text rather than an enum: an unknown kind on an
  -- older client reads as a plain label, it never fails a decode.
  --   'syllabus' | 'schedule' | 'paste'
  kind        text not null default 'syllabus',
  created_at  timestamptz not null default now()
);

create index if not exists syllabus_scans_user_id_idx    on syllabus_scans (user_id);
create index if not exists syllabus_scans_project_id_idx on syllabus_scans (project_id);

alter table syllabus_scans enable row level security;

drop policy if exists "syllabus_scans: owner access" on syllabus_scans;
create policy "syllabus_scans: owner access" on syllabus_scans
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── 2. the pointers ─────────────────────────────────────────

alter table tasks  add column if not exists scan_id uuid references syllabus_scans(id) on delete set null;
alter table events add column if not exists scan_id uuid references syllabus_scans(id) on delete set null;

create index if not exists tasks_scan_id_idx  on tasks  (scan_id);
create index if not exists events_scan_id_idx on events (scan_id);

comment on column tasks.scan_id is
  'The syllabus_scans commit that created this task. NULL = hand-made, Canvas, '
  'or predates 0046. Stamped once at creation and round-tripped by the clients, '
  'so an edit never nulls the origin.';

comment on column events.scan_id is
  'The syllabus_scans commit that created this event. NULL = hand-made, synced, '
  'or predates 0046. Stamped once at creation and round-tripped by the clients.';
