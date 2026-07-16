-- ============================================================
-- Atlas — multi-account Google Calendar (design 2026-07-15).
--
-- Atlas can connect N Google accounts. Each connection is a row:
--   (google login, calendar_id 'primary', user's name, destination space).
-- All connections read IN; writes route OUT by space — an event syncs to
-- whichever Google account its space is linked to; an unlinked space stays in
-- Atlas. The one-sentence law: "An event syncs to the Google account its space
-- is linked to; an unlinked space stays in Atlas."
--
-- google_connections was PK user_id (a per-user singleton). It is EMPTY in prod
-- (verified 2026-07-15), so this DROPS and RECREATES it keyed by a surrogate id.
-- Related events / deleted_google_events / claim RPC are re-scoped per connection.
--
-- Idempotent / safe to re-run (matches 0006–0011 style).
-- ============================================================

-- ── Drop dependents that reference the old table type, then the table ──
-- The claim RPC returns `setof google_connections`, so it depends on the table
-- type — drop it before recreating the table. 0028 re-creates it (renamed) below.
drop function if exists public.claim_google_sync_users(int);

-- The table is empty in prod; CASCADE also removes the old set_updated_at trigger
-- and any dependent objects. events.google_connection_id doesn't exist yet, so
-- nothing in `events` is touched by the drop.
drop table if exists google_connections cascade;

-- ── google_connections: per-connection server-sync registry ──
-- id surrogate PK (N connections per user). name = user's label ("School"),
-- google_email = which login (display + dedupe), space_id = routing link
-- (null = read-in only). vault_secret_id points into vault.secrets (refresh
-- token); it is service-role only and never granted to clients.
create table if not exists google_connections (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null
                              references auth.users on delete cascade,
  name            text        not null,
  google_email    text        not null,
  calendar_id     text        not null default 'primary',
  space_id        uuid        references spaces on delete set null,
  vault_secret_id uuid,
  sync_token      text,
  status          text        not null default 'active'
                              check (status in ('active', 'error', 'revoked')),
  last_error      text,
  last_synced_at  timestamptz,
  claimed_until   timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, google_email, calendar_id),  -- one row per (login, calendar)
  unique (space_id)                              -- one space, one account
);

drop trigger if exists google_connections_set_updated_at on google_connections;
create trigger google_connections_set_updated_at
  before update on google_connections
  for each row
  execute function public.set_updated_at();

alter table google_connections enable row level security;

-- Owner may read the non-secret columns and disconnect. Inserts/updates and the
-- vault_secret_id pointer are service-role only (google-connect edge fn), so the
-- refresh-token pointer is never exposed to authenticated clients; a `select *`
-- by an owner is intentionally rejected — clients select explicit columns.
-- Mirrors 0006's grant/policy shape; claimed_until stays internal (not granted).
revoke all on table google_connections from anon, authenticated;
grant select (id, user_id, name, google_email, calendar_id, space_id, sync_token,
              last_synced_at, status, last_error, created_at, updated_at)
  on table google_connections to authenticated;
grant delete on table google_connections to authenticated;
grant all on table google_connections to service_role;

drop policy if exists "google_connections: owner reads status" on google_connections;
create policy "google_connections: owner reads status" on google_connections
  for select
  using (auth.uid() = user_id);

drop policy if exists "google_connections: owner disconnects" on google_connections;
create policy "google_connections: owner disconnects" on google_connections
  for delete
  using (auth.uid() = user_id);

-- ── events.google_connection_id (attribution + single-owner invariant) ──
-- Which connection a mirrored row belongs to. `on delete set null` detaches a
-- row when its connection is removed; the runner IGNORES rows whose gid is set
-- but connection id is null (legacy/detached — never re-created on Google).
-- Add the column, then (re)attach the FK separately so a re-run — where the
-- CASCADE drop of google_connections above stripped the old FK but the column
-- survives — restores it. `add column if not exists` alone would skip the FK.
alter table events add column if not exists google_connection_id uuid;
alter table events drop constraint if exists events_google_connection_id_fkey;
alter table events
  add constraint events_google_connection_id_fkey
  foreign key (google_connection_id) references google_connections(id) on delete set null;

-- Single-owner invariant, re-scoped per connection: replace the old
-- unique (user_id, google_event_id) with unique (google_connection_id,
-- google_event_id). Non-partial so ON CONFLICT can infer it (0009/C1), and
-- NULLS DISTINCT keeps the many null-gid / null-connection Atlas rows legal.
drop index if exists events_user_google_event_uidx;
create unique index if not exists events_conn_google_event_uidx
  on events (google_connection_id, google_event_id);

-- ── deleted_google_events: per-connection tombstones ──
-- Add the connection column, drop legacy pre-connection tombstones (they can't be
-- routed to any account — google_connections was empty, so the cron never replayed
-- them), then make the column NOT NULL + FK cascade and re-key the PK on it. user_id
-- is kept for the auth.users cascade.
alter table deleted_google_events
  add column if not exists google_connection_id uuid;

delete from deleted_google_events where google_connection_id is null;

alter table deleted_google_events drop constraint if exists deleted_google_events_pkey;
alter table deleted_google_events alter column google_connection_id set not null;

alter table deleted_google_events
  drop constraint if exists deleted_google_events_google_connection_id_fkey;
alter table deleted_google_events
  add constraint deleted_google_events_google_connection_id_fkey
  foreign key (google_connection_id) references google_connections(id) on delete cascade;

alter table deleted_google_events
  add constraint deleted_google_events_pkey
  primary key (google_connection_id, google_event_id);

-- ── AFTER DELETE trigger: tombstone a deleted mirrored event, per connection ──
-- Copies old.google_connection_id. SKIP when it is null (a detached/legacy row has
-- no connection to replay the delete to — nothing to tombstone). Keeps 0027's
-- foreign_key_violation swallow so an account-deletion cascade (owner mid-delete)
-- doesn't abort. ON CONFLICT DO NOTHING keeps re-deletes / races idempotent.
create or replace function public.record_deleted_google_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.google_event_id is not null and old.google_connection_id is not null then
    begin
      insert into public.deleted_google_events (user_id, google_event_id, google_connection_id)
      values (old.user_id, old.google_event_id, old.google_connection_id)
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

-- ── claim_google_sync_connections RPC: lease due CONNECTION rows ──
-- Renamed from claim_google_sync_users (0009/0010). Same lease/skip-locked
-- semantics, but leases connection rows by id (oldest last_synced_at first),
-- status IN ('active','error') so a per-event/transient error self-heals next tick
-- (0010). Service-role only.
create or replace function public.claim_google_sync_connections(batch int)
returns setof public.google_connections
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.google_connections gc
     set claimed_until = now() + interval '4 minutes'
   where gc.id in (
     select c.id
       from public.google_connections c
      where c.status in ('active', 'error')
        and (c.claimed_until is null or c.claimed_until < now())
      order by c.last_synced_at nulls first
      limit batch
      for update skip locked
   )
  returning gc.*;
end;
$$;

revoke all on function public.claim_google_sync_connections(int) from public, anon, authenticated;
grant execute on function public.claim_google_sync_connections(int) to service_role;
