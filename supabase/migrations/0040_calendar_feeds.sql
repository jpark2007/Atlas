-- ============================================================
-- Atlas — multi-feed calendar sync (generalizes Canvas → N feeds).
--
-- 0012 gave every user ONE Canvas feed (canvas_connections, PK user_id). This
-- generalizes that into `calendar_feeds`: N feeds per user, each either a Canvas
-- feed (assignment→task split + [COURSE] routing) or a generic ICS feed (every
-- VEVENT → an event, e.g. Schoology or a personal .ics). It rides the exact rails
-- 0012 built — Vault-held feed URL, owner-reads-status RLS, a claim RPC with
-- `for update skip locked`, a pg_cron tick — and reuses 0012's Vault wrappers
-- (create/read/delete_canvas_secret) unchanged.
--
-- 1. calendar_feeds — per-feed server-sync registry (owner reads non-secret cols +
--    deletes; the vault pointer and writes are service-role only). Partial unique
--    index: one ACTIVE Canvas feed per user; generic ICS feeds unlimited.
-- 2. tasks/events gain feed_id + feed_type (which feed a synced row came from).
-- 3. Backfill: one calendar_feeds row per existing canvas_connections row, then
--    stamp feed_id/feed_type onto every existing canvas_uid task/event. Idempotent.
-- 4. New unique keys (user_id, feed_id, canvas_uid) for the per-feed upsert. The old
--    (user_id, canvas_uid) uniques are KEPT (later-cleanup); no data collides.
-- 5. claim_calendar_feed_sync(batch) — 0012's claim RPC, now over calendar_feeds.
-- 6. canvas_connections is left INTACT + untouched (frozen; canvas-sync still reads
--    it as a compatibility endpoint until retired).
-- 7. CRON CUTOVER, atomically: unschedule 'canvas-sync-every-15m', schedule
--    'feeds-sync-every-15m' with the SAME schedule + Authorization header as 0012.
--    (Deploy the feeds-sync function BEFORE applying this so the first tick lands.)
--
-- Idempotent / safe to re-run.
-- ============================================================

create extension if not exists supabase_vault with schema vault;

-- ── calendar_feeds: per-feed server-sync registry ───────────
create table if not exists calendar_feeds (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null
                              references auth.users on delete cascade,
  feed_type       text        not null default 'ics'
                              check (feed_type in ('canvas', 'ics')),
  display_name    text        not null,                  -- the feed's shown name (event subtitle)
  space_name      text        not null default 'School', -- Atlas space unmatched items land in
  vault_secret_id uuid,                                  -- pointer into vault.secrets (the feed URL)
  etag            text,                                  -- conditional-GET cache (If-None-Match)
  last_modified   text,                                  -- conditional-GET cache (If-Modified-Since)
  status          text        not null default 'active'
                              check (status in ('active', 'error', 'revoked')),
  last_error      text,
  claimed_until   timestamptz,                           -- single-flight lease (see claim RPC)
  last_synced_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists calendar_feeds_set_updated_at on calendar_feeds;
create trigger calendar_feeds_set_updated_at
  before update on calendar_feeds
  for each row
  execute function public.set_updated_at();

alter table calendar_feeds enable row level security;

-- Owner may read the non-secret columns and delete their feed. Inserts/updates and
-- the vault_secret_id pointer are service-role only — the feed-URL pointer is never
-- exposed to authenticated clients (a `select *` by an owner is intentionally rejected).
revoke all on table calendar_feeds from anon, authenticated;
grant select (id, user_id, feed_type, display_name, space_name, last_synced_at, status, last_error, created_at, updated_at)
  on table calendar_feeds to authenticated;
grant delete on table calendar_feeds to authenticated;
grant all on table calendar_feeds to service_role;

drop policy if exists "calendar_feeds: owner reads status" on calendar_feeds;
create policy "calendar_feeds: owner reads status" on calendar_feeds
  for select
  using (auth.uid() = user_id);

drop policy if exists "calendar_feeds: owner deletes" on calendar_feeds;
create policy "calendar_feeds: owner deletes" on calendar_feeds
  for delete
  using (auth.uid() = user_id);

-- One ACTIVE (non-revoked) Canvas feed per user — the connect function relies on
-- this to reject a second Canvas card. Generic ICS feeds are unlimited (not covered).
create unique index if not exists calendar_feeds_one_active_canvas_uidx
  on calendar_feeds (user_id)
  where feed_type = 'canvas' and status <> 'revoked';

-- ── tasks/events: which feed a synced row came from ─────────
alter table tasks  add column if not exists feed_id   uuid references calendar_feeds(id) on delete set null;
alter table tasks  add column if not exists feed_type text;
alter table events add column if not exists feed_id   uuid references calendar_feeds(id) on delete set null;
alter table events add column if not exists feed_type text;

-- ── Backfill: canvas_connections → calendar_feeds ───────────
-- One 'canvas' feed per existing connection (display_name 'Canvas'), copying its
-- sync state. Guarded by NOT EXISTS so a re-run inserts nothing (the partial unique
-- index would also reject a second active canvas feed, but the guard covers revoked
-- rows too and keeps the migration cleanly idempotent).
insert into calendar_feeds (user_id, feed_type, display_name, space_name, vault_secret_id, etag, last_modified, status, last_error, claimed_until, last_synced_at)
select cc.user_id, 'canvas', 'Canvas', cc.space_name, cc.vault_secret_id, cc.etag, cc.last_modified, cc.status, cc.last_error, cc.claimed_until, cc.last_synced_at
  from canvas_connections cc
 where not exists (
   select 1 from calendar_feeds cf
    where cf.user_id = cc.user_id and cf.feed_type = 'canvas'
 );

-- Stamp feed_id/feed_type onto every existing Canvas-synced row. One canvas feed per
-- user makes the join unambiguous; only rows missing feed_id are touched (idempotent).
update tasks t
   set feed_id = cf.id, feed_type = 'canvas'
  from calendar_feeds cf
 where cf.user_id = t.user_id
   and cf.feed_type = 'canvas'
   and t.canvas_uid is not null
   and t.feed_id is null;

update events e
   set feed_id = cf.id, feed_type = 'canvas'
  from calendar_feeds cf
 where cf.user_id = e.user_id
   and cf.feed_type = 'canvas'
   and e.canvas_uid is not null
   and e.feed_id is null;

-- ── Per-feed upsert keys (the new ON CONFLICT target) ───────
-- canvas_uid keeps its name; it now means "the ICS UID" for any feed type. The old
-- (user_id, canvas_uid) uniques from 0012 are intentionally KEPT (later cleanup) —
-- no existing data collides, and NULLS DISTINCT leaves every null-uid Atlas row legal.
create unique index if not exists tasks_user_feed_canvas_uid_uidx
  on tasks (user_id, feed_id, canvas_uid);
create unique index if not exists events_user_feed_canvas_uid_uidx
  on events (user_id, feed_id, canvas_uid);

-- ── single-flight batching for the cron (mirrors 0012's claim) ──
-- Atomically lease the next `batch` due feeds. `for update skip locked` makes two
-- overlapping ticks pick disjoint feeds; the 8-minute lease is longer than a run and
-- shorter than the 15-minute cron so a crashed run self-heals. status in
-- ('active','error') so a transient/per-item error self-heals; only 'revoked' (bad/
-- reset feed URL needing a re-paste) stays excluded. Service-role only.
create or replace function public.claim_calendar_feed_sync(batch int)
returns setof public.calendar_feeds
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.calendar_feeds cf
     set claimed_until = now() + interval '8 minutes'
   where cf.id in (
     select f.id
       from public.calendar_feeds f
      where f.status in ('active', 'error')
        and (f.claimed_until is null or f.claimed_until < now())
      order by f.last_synced_at nulls first
      limit batch
      for update skip locked
   )
  returning cf.*;
end;
$$;

revoke all on function public.claim_calendar_feed_sync(int) from public, anon, authenticated;
grant execute on function public.claim_calendar_feed_sync(int) to service_role;

-- ── CRON CUTOVER (atomic): canvas-sync → feeds-sync ─────────
-- pg_cron / pg_net enabled by 0008. Retire the 0012 canvas-sync tick and schedule
-- feeds-sync on the SAME cadence + the SAME vault-keyed Authorization header. Deploy
-- the feeds-sync function BEFORE applying this migration so the first tick is live.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Unschedule the old job (guarded: cron.unschedule errors on a missing name).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'canvas-sync-every-15m') then
    perform cron.unschedule('canvas-sync-every-15m');
  end if;
end;
$$;

-- Same schedule pattern (minutes 2,17,32,47 — offset from google's */5) and the same
-- Bearer read_google_sync_service_key() header 0012 used for canvas-sync. Upserts by name.
select cron.schedule(
  'feeds-sync-every-15m',
  '2-59/15 * * * *',
  $job$
  select net.http_post(
    url     := 'https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/feeds-sync',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || public.read_google_sync_service_key()
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $job$
);
