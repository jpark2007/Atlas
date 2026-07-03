-- ============================================================
-- Atlas — google-sync hardening (fix wave for the Task-7 review).
--
-- C1  ON CONFLICT vs partial index. 0006's unique index is PARTIAL
--     (`where google_event_id is not null`), so Postgres will NOT infer it for
--     `ON CONFLICT (user_id, google_event_id)` — the runner's upsert failed with
--     42P10, blocking every Google→Atlas insert. Replace it with a NON-partial
--     unique index. The many Atlas rows with a NULL google_event_id do NOT collide
--     because a unique index treats NULLs as distinct (default NULLS DISTINCT; the
--     pre-15 behaviour too), so at most one non-null gid per (user, gid) is
--     enforced while unlimited null-gid Atlas rows remain legal.
--
-- C2  Two-timestamp reconcile. `events.google_updated_at` records the last Google
--     `updated` the runner APPLIED or OBSERVED, on Google's own clock. The runner
--     compares Google-vs-Atlas recency same-clock (`google.updated >
--     google_updated_at`) instead of cross-clock against `updated_at`, and stamps
--     pulled/pushed rows' `updated_at` explicitly so a mirrored event can never
--     drive a perpetual push↔pull storm (proof in the runner header).
--
--     To let the runner stamp `updated_at` deterministically, `set_updated_at`
--     now HONORS an explicitly-supplied value and only auto-stamps `now()` when
--     the writer left `updated_at` untouched. The Mac never sends `updated_at`
--     (it is not in EventRow's CodingKeys), so Mac writes still auto-stamp exactly
--     as before — this is backward compatible.
--
-- I3  Overlapping cron runs. `claim_google_sync_users(batch)` atomically leases a
--     batch of due connections with `for update skip locked`, so two overlapping
--     ticks never process the same user. `google_connections.claimed_until` holds
--     the lease; the runner clears it when a user finishes.
--
-- Idempotent / safe to re-run.
-- ============================================================

-- ── C1: non-partial unique (user_id, google_event_id) ───────────
-- Drop the partial index and recreate it without the WHERE clause so ON CONFLICT
-- can infer it. NULL gids stay distinct, so null-gid Atlas rows never collide.
drop index if exists events_user_google_event_uidx;
create unique index if not exists events_user_google_event_uidx
  on events (user_id, google_event_id);

-- ── C2: two-timestamp reconcile support ─────────────────────────
-- Last Google `updated` the runner applied/observed (Google clock). NULL for rows
-- that have never been reconciled against Google.
alter table events add column if not exists google_updated_at timestamptz;

-- set_updated_at now honors an explicit updated_at (runner control) and only
-- auto-stamps when the writer left it untouched. BEFORE UPDATE only, so `old` is
-- always present. Mac writers omit updated_at ⇒ new = old ⇒ auto-stamp (unchanged
-- behaviour); the runner passes an explicit value ⇒ honored.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at is distinct from old.updated_at then
    return new;              -- caller set it explicitly (runner) → honor it
  end if;
  new.updated_at = now();    -- default: stamp the modification time
  return new;
end;
$$;

-- ── I3: single-flight batching for the cron ─────────────────────
alter table google_connections add column if not exists claimed_until timestamptz;

-- Atomically lease the next `batch` due connections. `for update skip locked`
-- makes two overlapping ticks pick disjoint users; the 4-minute lease is longer
-- than a run and shorter than the 5-minute cron so a crashed run self-heals.
-- Service-role only (mirrors 0007's read_google_secret guards).
create or replace function public.claim_google_sync_users(batch int)
returns setof public.google_connections
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.google_connections gc
     set claimed_until = now() + interval '4 minutes'
   where gc.user_id in (
     select c.user_id
       from public.google_connections c
      where c.status = 'active'
        and (c.claimed_until is null or c.claimed_until < now())
      order by c.last_synced_at nulls first
      limit batch
      for update skip locked
   )
  returning gc.*;
end;
$$;

revoke all on function public.claim_google_sync_users(int) from public, anon, authenticated;
grant execute on function public.claim_google_sync_users(int) to service_role;
