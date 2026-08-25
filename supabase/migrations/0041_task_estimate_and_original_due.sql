-- ============================================================
-- Atlas — Phase 2 (time model & calendar language): two optional task columns.
--
-- `estimate_min`  — the user's optional estimate of how much TOTAL time a task needs.
--                   Distinct from `duration_min`, which is the length of the one planned
--                   work session. Drives the due marker's planned-time fill
--                   ("2.5 of 4h planned"); with no estimate the marker falls back to a
--                   session count instead. Nullable — estimates are opt-in, never required.
--
-- `original_due_date` — the due date a task carried BEFORE it was rescheduled off the
--                   Late bar. Written once, on the first late-reschedule, and never
--                   overwritten: the original date keeps a faded marker in the past so a
--                   missed deadline never silently vanishes ("pin, don't roll"). Nullable —
--                   the vast majority of tasks are never rescheduled while late.
--
-- Both round-trip through TaskRow so a client edit can never null them.
-- Idempotent / safe to re-run.
-- ============================================================

alter table tasks add column if not exists estimate_min integer;
alter table tasks add column if not exists original_due_date timestamptz;
