-- ============================================================
-- 0035 — doc_note_tabs.dropped_styling
-- A Google Docs tab keeps sync WRITABLE even when it carries cosmetic inline
-- styles the RichDocMarkdown dialect can't round-trip (text color, highlight,
-- strikethrough, small caps, super/subscript). Those styles are STRIPPED on
-- import (the text and its bold/italic/underline/link marks are kept) rather
-- than locking the whole tab read-only. This advisory flag records that at
-- least one such style was dropped, so the editor can show a non-blocking note
-- ("color/highlight kept in Google unless you edit this tab").
--
-- Structural lockers (nested lists, smart chips, TOC, breaks, footnotes,
-- equations, unknown styles, un-rehostable images) still set readonly_reason.
-- DEFAULT false so existing rows read as "nothing dropped" until re-pulled.
-- Idempotent: safe to re-run.
-- ============================================================

alter table doc_note_tabs add column if not exists dropped_styling boolean not null default false;
