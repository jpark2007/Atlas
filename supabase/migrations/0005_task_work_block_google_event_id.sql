-- ============================================================
-- Atlas — persist a scheduled task's work-block Google event id, so on relaunch the
-- work-block PATCHES the same Google event instead of re-creating it. Without this the
-- id was in-memory only, so every session re-pushed the block (duplicate events on
-- Google) and the read-back de-dupe couldn't match. Mirrors 0003 for events.
-- ============================================================

alter table tasks add column if not exists work_block_google_event_id text;
