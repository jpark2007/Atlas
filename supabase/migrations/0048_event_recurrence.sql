-- ============================================================
-- Atlas — repeating events (a class that meets MWF for a semester).
--
-- Atlas MATERIALIZES recurrence: a rule is expanded once, at capture/save time,
-- into real `events` rows — one per session — that share a `series_id`. Nothing
-- downstream has to learn about RRULEs: the grids, agenda, availability publish,
-- search, and the Google/Apple mirrors all keep working on plain dated rows, and
-- a single session can be moved or cancelled the way a real class is.
--
-- 1. events.series_id      — shared by every instance of one series; null = one-off.
--                            This is what makes "this and following" / "all events"
--                            addressable in a single scoped statement.
-- 2. events.recurrence_rule — the pattern as an RFC 5545 RRULE fragment
--                            ('FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261212'), copied
--                            onto every instance so any one row can describe the
--                            whole series without a join. Portable if real RRULE
--                            sync ever replaces materialization.
-- 3. Index on (user_id, series_id) — every series operation is "all rows of this
--                            series for this user"; partial so one-off rows (the
--                            overwhelming majority) cost nothing.
--
-- No backfill: existing rows are one-offs and correctly keep a null series_id.
-- RLS is unchanged — both columns live on `events`, already owner-scoped by 0001.
--
-- Idempotent / safe to re-run.
-- ============================================================

alter table events add column if not exists series_id       uuid;
alter table events add column if not exists recurrence_rule text;

comment on column events.series_id is
  'Shared by every materialized instance of one repeating series; null for a one-off event.';
comment on column events.recurrence_rule is
  'The series'' pattern as an RFC 5545 RRULE fragment, duplicated onto each instance.';

create index if not exists events_user_series_idx
    on events (user_id, series_id)
    where series_id is not null;
