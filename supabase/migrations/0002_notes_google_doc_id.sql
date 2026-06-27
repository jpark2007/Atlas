-- WS-10: Notes <-> Google Docs two-way sync.
-- NoteRow now encodes `google_doc_id` on upsert; without this column PostgREST
-- rejects every note write at runtime (note stays in memory, never persists).
-- Safe to run repeatedly.
alter table notes add column if not exists google_doc_id text;
