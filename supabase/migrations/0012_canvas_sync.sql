-- ============================================================
-- Atlas — server-side Canvas ICS sync foundations.
--
-- Rides the exact rails Google sync built (0006–0010): Vault-held secret,
-- owner-reads-status RLS, a claim RPC with `for update skip locked`, and a
-- pg_cron tick. The one Canvas difference: the per-user secret is a *feed URL*
-- (Canvas Calendar Feed — a capability URL whose token IS the auth), not an
-- OAuth refresh token, and the runner is PULL-only (Canvas is read-only).
--
-- 1. canvas_connections — per-user server-sync registry. Owner reads the
--    non-secret columns + disconnects; the vault pointer and writes are
--    service-role only (mirrors google_connections exactly).
-- 2. Vault create/read/delete wrappers for the feed URL (SECURITY DEFINER,
--    service-role only) — same pattern as 0006/0007's google secret wrappers.
-- 3. tasks.canvas_uid + events.canvas_uid, each with a NON-partial unique
--    (user_id, canvas_uid). Non-partial is deliberate: PostgREST ON CONFLICT
--    can't infer a partial index (the 0009/C1 lesson), and NULLS DISTINCT means
--    the unlimited null-canvas_uid Atlas rows never collide.
-- 4. claim_canvas_sync_users(batch) — atomic lease of due connections
--    (status in active,error; skip locked; 4-min lease) — mirrors 0010.
-- 5. cron 'canvas-sync-every-15m' at 2-59/15 (minutes 2,17,32,47 — offset from
--    google's */5 so ticks never stack), reusing 0008's service-key Vault helper.
--
-- Idempotent / safe to re-run.
-- ============================================================

-- Supabase Vault (pre-installed on Supabase projects; declared for clarity).
create extension if not exists supabase_vault with schema vault;

-- ── canvas_connections: per-user server-sync registry ───────
create table if not exists canvas_connections (
  user_id         uuid        primary key
                              references auth.users on delete cascade,
  vault_secret_id uuid,                     -- pointer into vault.secrets (the feed URL)
  space_name      text        not null default 'School', -- Atlas space unmatched Canvas items land in
  last_synced_at  timestamptz,
  etag            text,                     -- conditional-GET cache (If-None-Match)
  last_modified   text,                     -- conditional-GET cache (If-Modified-Since)
  status          text        not null default 'active'
                              check (status in ('active', 'error', 'revoked')),
  last_error      text,
  claimed_until   timestamptz,              -- single-flight lease (see claim RPC)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists canvas_connections_set_updated_at on canvas_connections;
create trigger canvas_connections_set_updated_at
  before update on canvas_connections
  for each row
  execute function public.set_updated_at();

alter table canvas_connections enable row level security;

-- Owner may read the non-secret columns and disconnect. Inserts/updates and the
-- vault_secret_id pointer are service-role only — the feed-URL pointer is never
-- exposed to authenticated clients. Clients select explicit columns (a `select *`
-- by an owner is intentionally rejected).
revoke all on table canvas_connections from anon, authenticated;
grant select (user_id, space_name, last_synced_at, status, last_error, created_at, updated_at)
  on table canvas_connections to authenticated;
grant delete on table canvas_connections to authenticated;
grant all on table canvas_connections to service_role;

drop policy if exists "canvas_connections: owner reads status" on canvas_connections;
create policy "canvas_connections: owner reads status" on canvas_connections
  for select
  using (auth.uid() = user_id);

drop policy if exists "canvas_connections: owner disconnects" on canvas_connections;
create policy "canvas_connections: owner disconnects" on canvas_connections
  for delete
  using (auth.uid() = user_id);

-- ── Vault helper RPCs (SECURITY DEFINER, service-role only) ──
-- The vault schema isn't exposed over PostgREST, so canvas-connect/canvas-sync
-- reach Vault through these wrappers. Never grant to anon/authenticated.
create or replace function public.create_canvas_secret(secret text, name text)
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

create or replace function public.read_canvas_secret(secret_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  val text;
begin
  select decrypted_secret into val
    from vault.decrypted_secrets
   where id = secret_id;
  return val;
end;
$$;

create or replace function public.delete_canvas_secret(secret_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = secret_id;
end;
$$;

revoke all on function public.create_canvas_secret(text, text) from public, anon, authenticated;
revoke all on function public.read_canvas_secret(uuid)         from public, anon, authenticated;
revoke all on function public.delete_canvas_secret(uuid)       from public, anon, authenticated;
grant execute on function public.create_canvas_secret(text, text) to service_role;
grant execute on function public.read_canvas_secret(uuid)         to service_role;
grant execute on function public.delete_canvas_secret(uuid)       to service_role;

-- ── canvas_uid keys (idempotent upsert target for both tables) ──
-- A Canvas feed carries assignments → tasks and calendar events → events; a stable
-- ICS UID keys each. Non-partial unique so ON CONFLICT (user_id, canvas_uid) infers
-- it. canvas_uid is a brand-new column, so no dedupe pass is needed (no existing
-- values can collide), and NULLS DISTINCT leaves every null-uid Atlas row legal.
alter table tasks  add column if not exists canvas_uid text;
alter table events add column if not exists canvas_uid text;

create unique index if not exists tasks_user_canvas_uid_uidx
  on tasks (user_id, canvas_uid);
create unique index if not exists events_user_canvas_uid_uidx
  on events (user_id, canvas_uid);

-- ── single-flight batching for the cron (mirrors 0010) ──────
-- Atomically lease the next `batch` due connections. `for update skip locked` makes
-- two overlapping ticks pick disjoint users; the 8-minute lease is longer than a run
-- and shorter than the 15-minute cron so a crashed run self-heals. status in
-- ('active','error') so a transient/per-item error self-heals next tick; only
-- 'revoked' (bad/reset feed URL needing a re-paste) stays excluded.
-- Service-role only.
create or replace function public.claim_canvas_sync_users(batch int)
returns setof public.canvas_connections
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.canvas_connections cc
     set claimed_until = now() + interval '8 minutes'
   where cc.user_id in (
     select c.user_id
       from public.canvas_connections c
      where c.status in ('active', 'error')
        and (c.claimed_until is null or c.claimed_until < now())
      order by c.last_synced_at nulls first
      limit batch
      for update skip locked
   )
  returning cc.*;
end;
$$;

revoke all on function public.claim_canvas_sync_users(int) from public, anon, authenticated;
grant execute on function public.claim_canvas_sync_users(int) to service_role;

-- ── Schedule: POST canvas-sync every 15 minutes ─────────────
-- pg_cron / pg_net were enabled by 0008. Reuses 0008's read_google_sync_service_key()
-- helper — the service_role key is a single project-wide credential already stored in
-- Vault as 'google_sync_service_role_key', so no second secret is needed. The key never
-- appears here; it is assembled at tick time. cron.schedule upserts by name.
--
-- Offset schedule: minutes 2,17,32,47 — never coincides with google-sync's */5
-- (0,5,10,…), so the two runners' ticks don't stack.
--
-- To remove: select cron.unschedule('canvas-sync-every-15m');
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'canvas-sync-every-15m',
  '2-59/15 * * * *',
  $job$
  select net.http_post(
    url     := 'https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/canvas-sync',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || public.read_google_sync_service_key()
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $job$
);
