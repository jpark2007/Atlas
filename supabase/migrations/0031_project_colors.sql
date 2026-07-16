-- ============================================================
-- 0031 — projects.color_token
-- Lets a project (a Class, in the School space) carry its own color,
-- mirroring how `spaces.color_token` (0001) works. NULL means "inherit
-- the parent space's color" — today's behavior. Only the DAY-GRID event/
-- work blocks wear the project color; month dots, chips, sidebar and
-- routing keep the space color.
--
-- Values are the same short tokens spaces use (school/personal/side/accent);
-- no new color storage format is introduced. Projects RLS (0001, owner
-- access) already covers reads/writes to this column — nothing to add.
-- Idempotent: safe to re-run.
-- ============================================================

alter table projects add column if not exists color_token text;
