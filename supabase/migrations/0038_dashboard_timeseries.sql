-- ============================================================
-- 0038 — Owner-dashboard time-series (charts)
--
-- Backs the graphs added to the landing owner dashboard. Additive only.
--
--   • download_events  — one timestamped row per DMG download, so downloads can
--       be charted per day. The all-time tile still reads the site_metrics
--       counter; track-download now writes BOTH (counter + one event row).
--   • metric_snapshots — a self-populating daily history. admin-stats upserts
--       today's row (total users, downloads, Mac/iOS 30-day actives) on every
--       "stats" call, so history accrues whenever the owner opens the dashboard.
--       This is the only way to chart actives over time: client pings only carry
--       a last_seen_at, so there's no retroactive per-day series to mine.
--   • admin_signup_days() — a definer helper returning per-day signup counts from
--       auth.users (full history; auth schema isn't reachable over PostgREST).
--
-- All service-role-only: RLS on, no policies, client grants revoked. The public
-- track-download fn (service role) writes download_events; the owner-only
-- admin-stats fn (service role) writes metric_snapshots and reads everything.
--
-- Idempotent / safe to re-run.
-- ============================================================

-- ── download_events ─────────────────────────────────────────
create table if not exists public.download_events (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table public.download_events enable row level security;
revoke all on table public.download_events from anon, authenticated;

create index if not exists download_events_created_idx
  on public.download_events (created_at);

-- ── metric_snapshots ────────────────────────────────────────
create table if not exists public.metric_snapshots (
  day            date primary key,
  total_users    bigint  not null default 0,
  dmg_downloads  bigint  not null default 0,
  mac_active_30d integer not null default 0,
  ios_active_30d integer not null default 0,
  updated_at     timestamptz not null default now()
);

alter table public.metric_snapshots enable row level security;
revoke all on table public.metric_snapshots from anon, authenticated;

-- ── admin_signup_days() ─────────────────────────────────────
-- Per-day signup counts across all history, for the cumulative-users chart.
-- Definer (like admin_user_count) so the service-role fn can reach auth.users.
create or replace function public.admin_signup_days()
returns table (day date, n bigint)
language sql
security definer
set search_path = ''
as $$
  select date_trunc('day', created_at)::date as day,
         count(*)::bigint                     as n
  from auth.users
  group by 1
  order by 1;
$$;

revoke all on function public.admin_signup_days() from public, anon, authenticated;
grant execute on function public.admin_signup_days() to service_role;
