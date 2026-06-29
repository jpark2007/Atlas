-- ============================================================
-- Atlas — persist the Google Calendar event id on Atlas events.
-- Without this, write-back loses the id on relaunch and an edit
-- CREATES a duplicate on Google instead of PATCHing the original.
-- ============================================================

alter table events add column if not exists google_event_id text;
