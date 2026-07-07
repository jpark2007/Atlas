-- ============================================================
-- 0017 — tasks.completed_at
-- Stamped when a task is checked off (cleared on un-check) so the
-- Completed view can order by finish date. Tasks completed before
-- this column existed stay NULL — undated, sorted oldest.
-- Idempotent: safe to re-run.
-- ============================================================

alter table tasks add column if not exists completed_at timestamptz;
