-- ============================================================
-- Atlas — persist the Apple Calendar mirror id on events + tasks (Track C write-back).
--
-- When an Atlas event (or a task's scheduled work-block) is mirrored to Apple Calendar
-- via EventKit, we keep its `eventIdentifier` so a later edit/delete PATCHES the same
-- EKEvent instead of duplicating it — the Apple analog of google_event_id (0003) and
-- work_block_google_event_id (0005).
--
-- Best-effort continuity only: EventKit identifiers are PER-DEVICE, and the Mac is the
-- sole EventKit device in Atlas. This column is a convenience mirror the Mac reads back;
-- nothing else consumes it. Nullable — the vast majority of rows are never mirrored.
--
-- Idempotent / safe to re-run.
-- ============================================================

alter table events add column if not exists apple_event_id text;
alter table tasks  add column if not exists apple_event_id text;
