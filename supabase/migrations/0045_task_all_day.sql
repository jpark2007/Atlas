-- ============================================================
-- Atlas — tasks.all_day: Canvas due dates that are DATES, not instants.
--
-- Canvas's ICS feed exports assignment due dates date-only (`VALUE=DATE`); the parser
-- returns UTC midnight + an all-day flag, but the flag had nowhere to land, so a
-- "due Sep 9" assignment read "Due Sep 8, 8 PM" in EDT — and every dueDate-vs-now
-- comparison (isLate, buckets, the Late row, notifications) fired ~28h early.
--
-- `all_day = true` means the stored `due_date` is the canonical UTC-midnight encoding of
-- a calendar DATE (see AtlasCore/AllDayDate.swift), not an instant. Clients read the
-- effective deadline as 11:59:59 PM local on that UTC calendar day and render it
-- date-only ("Due Sep 9").
--
-- The backfill claims exactly the rows this describes: feed-ingested tasks (canvas_uid
-- non-null) sitting at exact UTC midnight. An Atlas-native task the user deliberately
-- set to midnight is left alone.
--
-- Round-trips through TaskRow so a client edit can never null it.
-- Idempotent / safe to re-run.
-- ============================================================

alter table tasks add column if not exists all_day boolean not null default false;

update tasks
   set all_day = true
 where canvas_uid is not null
   and due_date is not null
   and due_date = date_trunc('day', due_date at time zone 'utc') at time zone 'utc'
   and all_day = false;
