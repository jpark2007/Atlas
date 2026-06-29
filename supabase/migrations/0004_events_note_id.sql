-- ============================================================
-- Atlas — link a calendar event to a Note (detail-view "tag to a note").
-- Nulls out automatically if the linked note is deleted.
-- ============================================================

alter table events add column if not exists note_id uuid references notes(id) on delete set null;
