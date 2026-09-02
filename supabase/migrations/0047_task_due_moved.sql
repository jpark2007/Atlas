-- ============================================================
-- Atlas — tasks.due_moved_from: Canvas moved the deadline, the plan didn't move with it.
--
-- feeds-sync/canvas-sync's USER-DATA-SAFE update path overwrites a task's `due_date`
-- unconditionally on every re-sync (it's feed-owned) but never touches `scheduled_at`
-- — so a student who dragged a work block onto the old due date silently ends up with
-- a plan that no longer matches the deadline.
--
-- `due_moved_from` records the PREVIOUS due_date the moment a sync actually changes it
-- on a non-done task, so the client can show a "Due date moved from <date>" chip. Set
-- once per move (the server never clears it — dismissing the chip is a client action);
-- overwritten again if Canvas moves the date a second time before the user notices.
--
-- Round-trips through TaskRow so a client edit can never null it out from under a
-- pending chip.
-- Idempotent / safe to re-run.
-- ============================================================

alter table tasks add column if not exists due_moved_from timestamptz;
