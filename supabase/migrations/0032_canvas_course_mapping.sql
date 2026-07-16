-- ============================================================
-- 0032 — Canvas course ↔ class (project) mapping
--
-- A Canvas ICS item carries its course only in the SUMMARY's trailing "[…]"
-- bracket (there is no numeric course id in the feed). 0012's routing parsed that
-- bracket, matched it to a project by code/name, then discarded it — so the course
-- identity was never persisted per item and could not be listed, linked, or remapped.
--
-- This migration persists that course label in three places:
--   • tasks.canvas_course  — the bracket label an assignment-style item came from.
--   • events.canvas_course — the bracket label a calendar item came from.
--   • projects.canvas_course — the ONE course a class is explicitly linked to.
--
-- With these, canvas-sync (next tick) backfills every existing Canvas row's course
-- and routes future items whose course == a project's canvas_course under that
-- project; the Mac class page lists the feed's courses and, at link time, remaps
-- already-imported items into the chosen class. All three are plain text (matching
-- the feed's own identity); nullable, so every non-Canvas / unlinked row is legal.
--
-- Projects/tasks/events RLS (0001, owner + shared access) already covers these
-- columns — nothing to add. Idempotent: safe to re-run.
-- ============================================================

alter table tasks    add column if not exists canvas_course text;
alter table events   add column if not exists canvas_course text;
alter table projects add column if not exists canvas_course text;
