-- ============================================================
-- 0051 — Signup attribution
--
-- One question asked once, right after account creation, on both Mac and iOS:
-- "How did you hear about Atlas?" and "What school are you at?". Three nullable
-- text columns on `profiles`, written through the existing self-only RLS policy
-- (0015), plus two exclusion-aware read RPCs for the owner dashboard.
--
--   • profiles.referral_source — a ReferralSource raw value: friend, tiktok,
--       instagram, reddit, google_search, professor, other, or 'skipped' when
--       the step was dismissed. Null = never asked (existing accounts).
--   • profiles.referral_detail — the free text behind "Other".
--   • profiles.school          — a name from the bundled US list, or free text.
--   • admin_referral_counts()  — counts by source, last 30 days and all time.
--   • admin_school_counts()    — counts by school, all time.
--
-- Additive, nullable, no backfill. Safe to re-run.
-- ============================================================

alter table public.profiles
  add column if not exists referral_source text,
  add column if not exists referral_detail text,
  add column if not exists school          text;

-- ── dashboard reads ─────────────────────────────────────────
-- Both go through admin_is_excluded (0049) so the team and the review/test
-- accounts never show up in the breakdown, and both window on auth.users
-- created_at — `profiles` has no timestamp of its own.

create or replace function public.admin_referral_counts()
returns table (source text, n_30d bigint, n_all bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select p.referral_source::text,
         count(*) filter (where u.created_at >= now() - interval '30 days')::bigint,
         count(*)::bigint
    from public.profiles p
    join auth.users u on u.id = p.user_id
   where p.referral_source is not null
     and not public.admin_is_excluded(u.email)
   group by 1
   order by 3 desc, 1;
$$;

revoke all on function public.admin_referral_counts() from public, anon, authenticated;
grant execute on function public.admin_referral_counts() to service_role;

create or replace function public.admin_school_counts()
returns table (school text, n bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select p.school::text,
         count(*)::bigint
    from public.profiles p
    join auth.users u on u.id = p.user_id
   where p.school is not null
     and length(btrim(p.school)) > 0
     and not public.admin_is_excluded(u.email)
   group by 1
   order by 2 desc, 1;
$$;

revoke all on function public.admin_school_counts() from public, anon, authenticated;
grant execute on function public.admin_school_counts() to service_role;
