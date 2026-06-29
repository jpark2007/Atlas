-- ============================================================
-- Atlas — detail-view fields: tag calendar items + tasks to a Note,
-- give tasks a description, and (finally) persist work-block duration.
--   events.note_id     : "tag this event to a note"
--   tasks.notes        : task description (editable in the detail view)
--   tasks.note_id      : "tag this task to a note"
--   tasks.duration_min : work-block length — was NOT persisted before, so a
--                        scheduled task's duration reset to 60 min on relaunch.
-- Note links null out automatically if the linked note is deleted.
-- ============================================================

alter table events add column if not exists note_id uuid references notes(id) on delete set null;

alter table tasks add column if not exists notes text;
alter table tasks add column if not exists note_id uuid references notes(id) on delete set null;
alter table tasks add column if not exists duration_min int;
