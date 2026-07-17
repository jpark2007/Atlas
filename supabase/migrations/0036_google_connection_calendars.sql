-- ============================================================
-- Atlas — per-calendar selection for Google Calendar sync (design 2026-07-17).
--
-- Until now every google_connections row synced exactly ONE calendar
-- (calendar_id 'primary', google-connect line ~315 "v1: one calendar per login").
-- University Google accounts keep the class schedule on SECONDARY calendars, which
-- therefore never synced. This adds a per-connection calendar registry so the user
-- can pick WHICH calendars of an account sync — default = primary only, so existing
-- and new connections keep today's behavior until the user opts a calendar in.
--
--   google_connection_calendars — one row per (connection, calendar). `selected`
--     drives the sync loop; `sync_token` is per-calendar (incremental cursors are
--     per-calendar in Google's API), replacing the single connection-level token.
--   events.google_calendar_id       — which calendar a mirrored row came from, so a
--                                      deselect can delete exactly that calendar's rows.
--   deleted_google_events.google_calendar_id — so an Atlas→Google delete replays to
--                                      the calendar the event actually lived on.
--
-- Backfill preserves existing users' incremental sync: one selected primary row per
-- connection carrying the connection's existing sync_token; existing mirrored events
-- are stamped calendar_id 'primary'. No full resync for anyone on deploy.
--
-- Idempotent / safe to re-run (matches 0006–0028 style).
-- ============================================================

-- ── events.google_calendar_id (per-calendar attribution) ──
-- Which Google calendar a mirrored row came from. Null for legacy/native rows.
-- Backfilled to 'primary' for every row already mirrored to a connection, matching
-- the calendar those rows were pulled from before this migration.
alter table events add column if not exists google_calendar_id text;

update events
   set google_calendar_id = 'primary'
 where google_connection_id is not null
   and google_event_id is not null
   and google_calendar_id is null;

-- ── deleted_google_events.google_calendar_id (per-calendar replay target) ──
-- So the runner replays an app-side delete to the calendar the event lived on. Null
-- (legacy tombstones) → the runner falls back to the connection's primary calendar.
alter table deleted_google_events add column if not exists google_calendar_id text;

-- ── AFTER DELETE trigger: also carry the calendar id onto the tombstone ──
-- Same shape as 0028 (per-connection tombstone, foreign_key_violation swallow, ON
-- CONFLICT idempotent) plus old.google_calendar_id so the replay hits the right
-- calendar.
create or replace function public.record_deleted_google_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.google_event_id is not null and old.google_connection_id is not null then
    begin
      insert into public.deleted_google_events
        (user_id, google_event_id, google_connection_id, google_calendar_id)
      values
        (old.user_id, old.google_event_id, old.google_connection_id, old.google_calendar_id)
      on conflict (google_connection_id, google_event_id) do nothing;
    exception when foreign_key_violation then
      -- The owning auth.users / connection row is mid-delete (cascade): no
      -- connection will survive to replay this, so skip the tombstone.
      null;
    end;
  end if;
  return old;
end;
$$;

-- ── google_connection_calendars: per-connection calendar registry ──
-- One row per (connection, calendar). `selected` drives the sync loop; the runner
-- syncs only selected calendars. `sync_token` is the per-calendar incremental cursor
-- (410 GONE → full resync of just that calendar). `is_primary` marks the account's
-- primary calendar (the write target: reads fan in from many, writes go to primary).
create table if not exists google_connection_calendars (
  connection_id uuid    not null references google_connections(id) on delete cascade,
  calendar_id   text    not null,
  summary       text    not null default '',
  is_primary    boolean not null default false,
  selected      boolean not null default false,
  sync_token    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (connection_id, calendar_id)
);

drop trigger if exists google_connection_calendars_set_updated_at on google_connection_calendars;
create trigger google_connection_calendars_set_updated_at
  before update on google_connection_calendars
  for each row
  execute function public.set_updated_at();

-- ── Backfill: one selected primary row per existing connection ──
-- Carries the connection's existing sync_token so existing users keep their
-- incremental cursor (no full resync). Idempotent via ON CONFLICT DO NOTHING.
insert into google_connection_calendars
  (connection_id, calendar_id, summary, is_primary, selected, sync_token)
select gc.id, 'primary', coalesce(gc.google_email, 'Primary'), true, true, gc.sync_token
  from google_connections gc
on conflict (connection_id, calendar_id) do nothing;

-- ── RLS: owner reads via connection ownership; writes are service-role only ──
-- Mirrors google_connections (0028): the owner may SELECT the non-secret columns
-- (sync_token stays server-only, like vault_secret_id), all writes go through the
-- google-connect edge function under the service role.
alter table google_connection_calendars enable row level security;

revoke all on table google_connection_calendars from anon, authenticated;
grant select (connection_id, calendar_id, summary, is_primary, selected)
  on table google_connection_calendars to authenticated;
grant all on table google_connection_calendars to service_role;

drop policy if exists "gcc: owner reads" on google_connection_calendars;
create policy "gcc: owner reads" on google_connection_calendars
  for select
  using (
    exists (
      select 1 from public.google_connections gc
       where gc.id = google_connection_calendars.connection_id
         and gc.user_id = auth.uid()
    )
  );
