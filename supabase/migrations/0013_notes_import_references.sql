-- ============================================================
-- Atlas — Docs → Notes import: the project-scoped reference pool.
-- Design: docs/specs/2026-07-03-notes-import-design.md
--
-- Additive only — creates two new tables + indexes; alters nothing existing.
--   1. project_references   — the per-project pool. Three flavors keyed by `kind`:
--                             'doc_note' (linked Google Doc backing a Note),
--                             'file' (view-only Drive file), 'link' (external URL).
--                             The table is `project_references`, NOT `references`,
--                             because REFERENCES is a reserved SQL keyword.
--   2. reference_attachments — many-to-many join tying a reference to a task OR an
--                             event (a task/event can carry many refs; a ref can be
--                             on many items). Unlike the single-tag tasks.note_id /
--                             events.note_id, references need a pool, so a join.
--
-- Both use the standard auth.uid() owner default + owner-access RLS (mirrors 0001).
-- Ids are client-generated UUIDs (like every other table). Idempotent / safe to re-run.
-- ============================================================

-- ── project_references: the per-project reference pool ──────
create table if not exists project_references (
    id             uuid        primary key,
    user_id        uuid        not null default auth.uid()
                               references auth.users on delete cascade,
    project_id     uuid        not null
                               references projects(id) on delete cascade,
    kind           text        not null default 'file'
                               check (kind in ('doc_note', 'file', 'link')),
    title          text        not null default '',
    url            text,                      -- 'link': the external URL; null for Drive-backed
    drive_file_id  text,                      -- 'doc_note'/'file': the Drive file id; null for 'link'
    mime_type      text,                      -- Drive mimeType (routing + type glyph)
    modified_time  timestamptz,               -- Drive modifiedTime at last pull — the staleness-guard baseline
    last_synced_at timestamptz,               -- when Atlas last reconciled with Drive
    sync_state     text        not null default 'pending'
                               check (sync_state in ('pending', 'synced', 'stale', 'error')),
    note_id        uuid        references notes(id) on delete set null,  -- 'doc_note': the backing Note
    created_at     timestamptz not null default now()
);

alter table project_references enable row level security;
create policy "project_references: owner access" on project_references
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create index if not exists project_references_project_idx on project_references (project_id);
create index if not exists project_references_note_idx    on project_references (note_id);

-- ── reference_attachments: reference ⇄ task / event join ────
-- Exactly one of task_id/event_id is set per row (num_nonnulls check). Deleting the
-- reference, task, or event cascades the join away. Partial uniques stop a reference
-- being attached to the same item twice; the app also dedupes before insert, so the
-- upsert never relies on ON CONFLICT inferring these (the 0009/C1 lesson).
create table if not exists reference_attachments (
    id           uuid        primary key,
    user_id      uuid        not null default auth.uid()
                             references auth.users on delete cascade,
    reference_id uuid        not null
                             references project_references(id) on delete cascade,
    task_id      uuid        references tasks(id)  on delete cascade,
    event_id     uuid        references events(id) on delete cascade,
    created_at   timestamptz not null default now(),
    check (num_nonnulls(task_id, event_id) = 1)
);

alter table reference_attachments enable row level security;
create policy "reference_attachments: owner access" on reference_attachments
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create index if not exists reference_attachments_reference_idx on reference_attachments (reference_id);
create index if not exists reference_attachments_task_idx      on reference_attachments (task_id);
create index if not exists reference_attachments_event_idx     on reference_attachments (event_id);

create unique index if not exists reference_attachments_ref_task_uidx
    on reference_attachments (reference_id, task_id)  where task_id  is not null;
create unique index if not exists reference_attachments_ref_event_uidx
    on reference_attachments (reference_id, event_id) where event_id is not null;
