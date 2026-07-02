-- ============================================================
-- Atlas — server-side Google Calendar sync foundations.
--
-- 1. events.updated_at + trigger  — the sync runner needs a modified-at
--    timestamp for newest-wins conflict resolution.
-- 2. Dedupe + partial UNIQUE (user_id, google_event_id) — once the server
--    is a second writer, only a DB constraint can stop duplicate Google
--    rows (application-side dedupe lived only on the Mac). Dedupe first so
--    the constraint can be created, then enforce it.
-- 3. google_connections — per-user server-sync registry. Owner may read the
--    non-secret columns and disconnect; the vault pointer + writes are
--    service-role only.
-- 4. Vault helper RPCs (SECURITY DEFINER, service-role only) so the
--    google-connect edge function can stash/rotate/remove a refresh token
--    in Supabase Vault without the vault schema being exposed over PostgREST.
--
-- Idempotent / safe to re-run.
-- ============================================================

-- Supabase Vault (pre-installed on Supabase projects; declared for clarity).
create extension if not exists supabase_vault with schema vault;

-- ── shared updated_at trigger fn ─────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── events.updated_at + trigger (newest-wins support) ────────
alter table events add column if not exists updated_at timestamptz not null default now();

drop trigger if exists events_set_updated_at on events;
create trigger events_set_updated_at
  before update on events
  for each row
  execute function public.set_updated_at();

-- ── Dedupe existing Google-origin rows, then enforce uniqueness ──
-- Keep the newest (updated_at, then physical ctid) per
-- (user_id, google_event_id); delete the rest. Google-origin rows were never
-- persisted before this project, so this is a no-op in practice today — but it
-- makes the unique index below safe if any duplicate ever slipped in.
delete from events
where ctid in (
  select ctid from (
    select ctid,
           row_number() over (
             partition by user_id, google_event_id
             order by updated_at desc, ctid desc
           ) as rn
    from events
    where google_event_id is not null
  ) ranked
  where rn > 1
);

create unique index if not exists events_user_google_event_uidx
  on events (user_id, google_event_id)
  where google_event_id is not null;

-- ── google_connections: per-user server-sync registry ───────
create table if not exists google_connections (
  user_id         uuid        primary key
                              references auth.users on delete cascade,
  vault_secret_id uuid,                     -- pointer into vault.secrets (refresh token)
  calendar_id     text        not null default 'primary',
  sync_token      text,                     -- Google incremental sync cursor
  last_synced_at  timestamptz,
  status          text        not null default 'active'
                              check (status in ('active', 'error', 'revoked')),
  last_error      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists google_connections_set_updated_at on google_connections;
create trigger google_connections_set_updated_at
  before update on google_connections
  for each row
  execute function public.set_updated_at();

alter table google_connections enable row level security;

-- Owner may read the non-secret columns and disconnect (delete → RLS below).
-- Inserts/updates and the vault_secret_id pointer are service-role only, so the
-- refresh-token pointer is never exposed to authenticated clients; a `select *`
-- by an owner is intentionally rejected — clients select explicit columns.
revoke all on table google_connections from anon, authenticated;
grant select (user_id, calendar_id, sync_token, last_synced_at, status, last_error, created_at, updated_at)
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

-- ── Vault helper RPCs (SECURITY DEFINER, service-role only) ──
-- The vault schema isn't exposed over PostgREST, so google-connect reaches
-- Vault through these wrappers. Never grant to anon/authenticated.
create or replace function public.create_google_secret(secret text, name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  sid uuid;
begin
  sid := vault.create_secret(secret, name);
  return sid;
end;
$$;

create or replace function public.delete_google_secret(secret_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = secret_id;
end;
$$;

revoke all on function public.create_google_secret(text, text) from public, anon, authenticated;
revoke all on function public.delete_google_secret(uuid)      from public, anon, authenticated;
grant execute on function public.create_google_secret(text, text) to service_role;
grant execute on function public.delete_google_secret(uuid)      to service_role;
