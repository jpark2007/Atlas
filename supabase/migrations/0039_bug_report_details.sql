-- ============================================================
-- 0039 — Richer bug reports
--
-- The in-app "Report a bug" flow (0037) started as a single message field. The
-- report sheet now also collects an optional short title, an optional contact
-- email (for account-specific issues), and an auto-attached tail of recent
-- in-app logs. Add three nullable columns to back them.
--
-- Purely additive. RLS/grants unchanged from 0037 (insert-own; no client read).
-- Idempotent / safe to re-run.
-- ============================================================

alter table public.bug_reports
  add column if not exists title         text,
  add column if not exists contact_email text,
  add column if not exists log           text;

-- Bound them so a client can't stuff arbitrarily large payloads. NOT VALID would
-- be pointless (the columns are brand-new and empty), so validate immediately.
alter table public.bug_reports
  drop constraint if exists bug_reports_title_len;
alter table public.bug_reports
  add constraint bug_reports_title_len check (title is null or char_length(title) <= 200);

alter table public.bug_reports
  drop constraint if exists bug_reports_contact_email_len;
alter table public.bug_reports
  add constraint bug_reports_contact_email_len check (contact_email is null or char_length(contact_email) <= 320);

alter table public.bug_reports
  drop constraint if exists bug_reports_log_len;
alter table public.bug_reports
  add constraint bug_reports_log_len check (log is null or char_length(log) <= 16000);
