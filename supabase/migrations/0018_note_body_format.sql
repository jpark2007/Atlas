-- ============================================================
-- 0018 — notes.body_format
-- 'plain' (legacy literal text) or 'md' (Markdown — what the rich
-- editor saves, same transport form linked Doc-notes use). Existing
-- bodies stay 'plain' and convert the first time they're edited;
-- no bulk rewrite.
-- Idempotent: safe to re-run.
-- ============================================================

alter table notes add column if not exists body_format text not null default 'plain';
