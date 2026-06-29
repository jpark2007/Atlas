-- ============================================================
-- Atlas — tasks gain a description + note link + a persisted duration.
--   notes        : free-text description (editable from the detail view)
--   note_id      : "tag to a note" link (nulls out if the note is deleted)
--   duration_min : the work-block length — WAS NOT persisted before, so a
--                  scheduled task's duration reset to 60 min on every relaunch.
-- A task and its calendar work-block are the same thing, so these back the
-- detail view for scheduled tasks.
-- ============================================================

alter table tasks add column if not exists notes text;
alter table tasks add column if not exists note_id uuid references notes(id) on delete set null;
alter table tasks add column if not exists duration_min int;
