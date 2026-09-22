-- ============================================================
-- 0052 — Bug reports: fixed / replied timestamps
--
-- The owner dashboard now runs support as an inbox. Resolving a report says
-- "put away"; it doesn't say whether the bug was actually fixed or whether the
-- reporter ever heard back. Two nullable stamps, set by admin-stats
-- ("mark_fixed" / "unmark_fixed" / "mark_replied"):
--
--   • fixed_at   — when the fix landed (cleared again by unmark_fixed).
--   • replied_at — the last time the owner hit Reply on the report.
--
-- Purely additive. RLS/grants unchanged from 0037 (insert-own; no client read).
-- Idempotent / safe to re-run.
-- ============================================================

alter table public.bug_reports
  add column if not exists fixed_at   timestamptz,
  add column if not exists replied_at timestamptz;
