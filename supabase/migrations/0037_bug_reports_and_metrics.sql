-- ============================================================
-- 0037 — In-app bug reports + owner-dashboard metrics
--
-- Three service-role-facing tables that back the "Report a bug" flow and the
-- owner-only landing dashboard (admin-stats / track-download edge functions):
--
--   • bug_reports  — a beta tester files an issue from Settings. Clients INSERT
--       their own row (RLS); only the service-role admin fn reads them back.
--   • app_pings    — one row per (user, platform), upserted on app launch, so
--       the dashboard can count Mac vs mobile actives. User owns their rows.
--   • site_metrics — a tiny key→count store; seeded with dmg_downloads, bumped
--       by the public track-download fn (service role only).
--
-- Plus admin_user_count(): a definer helper so the service-role admin fn can
-- read the auth.users total (auth schema isn't exposed over PostgREST).
--
-- Purely additive. Idempotent / safe to re-run.
-- ============================================================

-- ── bug_reports ─────────────────────────────────────────────
create table if not exists public.bug_reports (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users on delete set null,
  message     text not null check (char_length(message) <= 4000),
  app_version text,
  platform    text,
  status      text not null default 'open',
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.bug_reports enable row level security;

-- Authenticated users may file their OWN report and nothing else. No SELECT
-- policy → clients can never read reports back; the owner reads via the
-- service-role admin-stats function.
drop policy if exists "bug_reports: insert own" on public.bug_reports;
create policy "bug_reports: insert own" on public.bug_reports
  for insert to authenticated
  with check (auth.uid() = user_id);

-- Owner reads/updates flow through the service role, which bypasses RLS. Revoke
-- the base-table grants that would otherwise let a client SELECT/UPDATE.
revoke all on table public.bug_reports from anon;
revoke select, update, delete on table public.bug_reports from authenticated;

create index if not exists bug_reports_status_created_idx
  on public.bug_reports (status, created_at desc);

-- ── app_pings ───────────────────────────────────────────────
create table if not exists public.app_pings (
  user_id      uuid not null references auth.users on delete cascade,
  platform     text not null,
  app_version  text,
  last_seen_at timestamptz not null default now(),
  primary key (user_id, platform)
);

alter table public.app_pings enable row level security;

-- A user may upsert (and read) only their own presence rows.
drop policy if exists "app_pings: owner access" on public.app_pings;
create policy "app_pings: owner access" on public.app_pings
  for all to authenticated
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on table public.app_pings from anon;

create index if not exists app_pings_platform_last_seen_idx
  on public.app_pings (platform, last_seen_at);

-- ── site_metrics ────────────────────────────────────────────
create table if not exists public.site_metrics (
  key   text primary key,
  count bigint not null default 0
);

-- Service-role only: RLS on with no policies = no client access at all. The
-- track-download fn (service role) bumps it; admin-stats reads it.
alter table public.site_metrics enable row level security;
revoke all on table public.site_metrics from anon, authenticated;

insert into public.site_metrics (key, count)
values ('dmg_downloads', 0)
on conflict (key) do nothing;

-- ── admin_config ────────────────────────────────────────────
-- The owner-dashboard access code, stored as a SHA-256 hex hash (never
-- plaintext) so it can be changed from inside the dashboard (admin-stats
-- "change_code"). Service-role only: RLS on with no policies + grants revoked.
-- Seeded with the hash of the initial code "2026" (maintainer changes it in-app).
create table if not exists public.admin_config (
  key   text primary key,
  value text not null
);

alter table public.admin_config enable row level security;
revoke all on table public.admin_config from anon, authenticated;

-- SHA-256 hex of "2026". Change the code from the dashboard, not here.
insert into public.admin_config (key, value)
values ('dash_code_hash',
        '158a323a7ba44870f23d96f1516dd70aa48e9a72db4ebb026b0a89e212a208ab')
on conflict (key) do nothing;

-- ── admin_user_count() ──────────────────────────────────────
-- The owner dashboard needs the total signup count. auth.users isn't reachable
-- over PostgREST, so expose just its count through a definer function the
-- service role can rpc. Locked to service_role; no client role may execute it.
create or replace function public.admin_user_count()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select count(*) from auth.users;
$$;

revoke all on function public.admin_user_count() from public, anon, authenticated;
grant execute on function public.admin_user_count() to service_role;
