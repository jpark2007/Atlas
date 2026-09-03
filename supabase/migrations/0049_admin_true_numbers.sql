-- ============================================================
-- 0049 — Owner dashboard: true numbers
--
-- The dashboard was counting us. Thirteen auth.users, seven of them the team
-- and the review/test accounts, all reported as "Total users". This migration
-- makes the exclusion a first-class, editable thing and moves every count
-- behind it.
--
--   • admin_config.excluded_emails — a JSON array of addresses that are not
--       real accounts. Seeded with the seven known ones; editable from the
--       dashboard (admin-stats "exclude_add"/"exclude_remove"). Anything on
--       @atlas-test.dev is excluded whether or not it is in the list.
--   • admin_is_excluded / admin_excluded_ids / admin_excluded_count /
--       admin_excluded_accounts — the predicate and its readers.
--   • admin_user_count / admin_signup_days — rewritten to exclude.
--   • admin_actives(win_days) — distinct REAL accounts with an app_ping in the
--       window, with the Mac/iOS split. Replaces the raw app_pings read the
--       edge function was doing (which could not see auth.users emails).
--   • metric_snapshots gains mac_active_7d / ios_active_7d and a `source`
--       column, plus a nightly pg_cron job (admin_snapshot_actives) at 00:00
--       UTC. The dashboard-open write stays as a fallback but can no longer
--       overwrite a cron row for the same day.
--   • download_hits — one row per (client-IP + UTC day) hash, so the download
--       counter stops counting the same visitor's repeat clicks.
--
-- Additive / idempotent. Safe to re-run.
-- ============================================================

-- ── the exclusion list ──────────────────────────────────────
-- Stored in admin_config next to the dash code hash: service-role only, no
-- client grants, editable through the same code-gated function.
insert into public.admin_config (key, value)
values ('excluded_emails', '[
  "apple.review@atlas-test.dev",
  "google.oauth.review@atlas-test.dev",
  "atlas.sim.test.claude@gmail.com",
  "gsync-verify-1783016889@atlas-test.dev",
  "jonahpark7@gmail.com",
  "drewkhalil@icloud.com",
  "lets.flowstate@gmail.com"
]')
on conflict (key) do nothing;

-- True when an address belongs to the team or to a test/review account. Two
-- rules: anything on the throwaway @atlas-test.dev domain, plus whatever the
-- list holds (matched case-insensitively). A null email is a real account.
create or replace function public.admin_is_excluded(p_email text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    lower(p_email) like '%@atlas-test.dev'
    or exists (
      select 1
        from public.admin_config c
        cross join lateral jsonb_array_elements_text(c.value::jsonb) as e(addr)
       where c.key = 'excluded_emails'
         and lower(e.addr) = lower(p_email)
    ),
    false);
$$;

revoke all on function public.admin_is_excluded(text) from public, anon, authenticated;
grant execute on function public.admin_is_excluded(text) to service_role;

-- ── headline counts, minus us ───────────────────────────────
create or replace function public.admin_user_count()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select count(*) from auth.users u
   where not public.admin_is_excluded(u.email);
$$;

revoke all on function public.admin_user_count() from public, anon, authenticated;
grant execute on function public.admin_user_count() to service_role;

create or replace function public.admin_excluded_count()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select count(*) from auth.users u
   where public.admin_is_excluded(u.email);
$$;

revoke all on function public.admin_excluded_count() from public, anon, authenticated;
grant execute on function public.admin_excluded_count() to service_role;

create or replace function public.admin_signup_days()
returns table (day date, n bigint)
language sql
security definer
set search_path = ''
as $$
  select date_trunc('day', u.created_at)::date as day,
         count(*)::bigint                       as n
    from auth.users u
   where not public.admin_is_excluded(u.email)
   group by 1
   order by 1;
$$;

revoke all on function public.admin_signup_days() from public, anon, authenticated;
grant execute on function public.admin_signup_days() to service_role;

-- ── actives ─────────────────────────────────────────────────
-- Distinct REAL accounts seen in the window, plus the per-platform split. An
-- account on both platforms counts once in `total` and once in each of
-- mac/ios — which is what the dashboard's headline + sub-line want.
create or replace function public.admin_actives(win_days integer)
returns table (total bigint, mac bigint, ios bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select count(distinct p.user_id)::bigint,
         count(distinct p.user_id) filter (where lower(p.platform) = 'macos')::bigint,
         count(distinct p.user_id) filter (where lower(p.platform) <> 'macos')::bigint
    from public.app_pings p
    join auth.users u on u.id = p.user_id
   where p.last_seen_at >= now() - make_interval(days => win_days)
     and not public.admin_is_excluded(u.email);
$$;

revoke all on function public.admin_actives(integer) from public, anon, authenticated;
grant execute on function public.admin_actives(integer) to service_role;

-- ── who is excluded, and why ────────────────────────────────
-- Feeds the dashboard's collapsed "excluded accounts" section. Reason is read
-- off the address: the throwaway domain and anything with "test" in it is a
-- test account, everything else on the list is team.
create or replace function public.admin_excluded_accounts()
returns table (email text, reason text, platform text, last_seen timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.email::text,
         case
           when lower(u.email) like '%@atlas-test.dev' then 'test'
           when lower(split_part(u.email, '@', 1)) like '%test%' then 'test'
           else 'team'
         end,
         p.platform,
         p.last_seen_at
    from auth.users u
    left join lateral (
      select ap.platform, ap.last_seen_at
        from public.app_pings ap
       where ap.user_id = u.id
       order by ap.last_seen_at desc
       limit 1
    ) p on true
   where public.admin_is_excluded(u.email)
   order by 2, 1;
$$;

revoke all on function public.admin_excluded_accounts() from public, anon, authenticated;
grant execute on function public.admin_excluded_accounts() to service_role;

-- ── snapshots: 7-day columns + provenance ───────────────────
alter table public.metric_snapshots
  add column if not exists mac_active_7d integer not null default 0,
  add column if not exists ios_active_7d integer not null default 0,
  add column if not exists source        text    not null default 'dashboard';

-- The nightly job. Writes today's row from the exclusion-aware counts and
-- stamps it 'cron' so the dashboard fallback below leaves it alone.
create or replace function public.admin_snapshot_actives()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  a7  record;
  a30 record;
  users bigint;
  dls   bigint;
begin
  select * into a7  from public.admin_actives(7);
  select * into a30 from public.admin_actives(30);
  select public.admin_user_count() into users;
  select coalesce(count, 0) into dls
    from public.site_metrics where key = 'dmg_downloads';

  insert into public.metric_snapshots
    (day, total_users, dmg_downloads,
     mac_active_30d, ios_active_30d, mac_active_7d, ios_active_7d,
     source, updated_at)
  values
    ((now() at time zone 'utc')::date, users, coalesce(dls, 0),
     a30.mac, a30.ios, a7.mac, a7.ios,
     'cron', now())
  on conflict (day) do update set
    total_users    = excluded.total_users,
    dmg_downloads  = excluded.dmg_downloads,
    mac_active_30d = excluded.mac_active_30d,
    ios_active_30d = excluded.ios_active_30d,
    mac_active_7d  = excluded.mac_active_7d,
    ios_active_7d  = excluded.ios_active_7d,
    source         = 'cron',
    updated_at     = now();
end;
$$;

revoke all on function public.admin_snapshot_actives() from public, anon, authenticated;
grant execute on function public.admin_snapshot_actives() to service_role;

-- The dashboard-open fallback. Same row, but it yields to a cron row for the
-- same day: history should come from the scheduled job, not from whenever the
-- owner happened to open the page.
create or replace function public.admin_snapshot_dashboard(
  p_day date, p_users bigint, p_downloads bigint,
  p_mac30 integer, p_ios30 integer, p_mac7 integer, p_ios7 integer)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.metric_snapshots as ms
    (day, total_users, dmg_downloads,
     mac_active_30d, ios_active_30d, mac_active_7d, ios_active_7d,
     source, updated_at)
  values
    (p_day, p_users, p_downloads, p_mac30, p_ios30, p_mac7, p_ios7,
     'dashboard', now())
  on conflict (day) do update set
    total_users    = excluded.total_users,
    dmg_downloads  = excluded.dmg_downloads,
    mac_active_30d = excluded.mac_active_30d,
    ios_active_30d = excluded.ios_active_30d,
    mac_active_7d  = excluded.mac_active_7d,
    ios_active_7d  = excluded.ios_active_7d,
    updated_at     = now()
  where ms.source <> 'cron';
$$;

revoke all on function public.admin_snapshot_dashboard(date, bigint, bigint, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.admin_snapshot_dashboard(date, bigint, bigint, integer, integer, integer, integer)
  to service_role;

-- ── cron: 00:00 UTC daily ───────────────────────────────────
-- pg_cron enabled by 0008; same upsert-by-name pattern as 0040's feeds-sync.
-- No http hop needed — the whole job is SQL.
create extension if not exists pg_cron;

select cron.schedule(
  'admin-snapshot-daily',
  '0 0 * * *',
  $job$ select public.admin_snapshot_actives(); $job$
);

-- ── download_hits ───────────────────────────────────────────
-- sha256(client IP + UTC day). One row per visitor per day; track-download
-- only bumps the counter when the insert is new. Service-role only.
create table if not exists public.download_hits (
  hash text primary key,
  day  date not null default (now() at time zone 'utc')::date
);

alter table public.download_hits enable row level security;
revoke all on table public.download_hits from anon, authenticated;

create index if not exists download_hits_day_idx on public.download_hits (day);
