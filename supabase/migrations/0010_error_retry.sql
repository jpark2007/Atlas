-- ============================================================
-- Atlas — google-sync incident fix: claim retries error connections.
--
-- Live incident: a run's PUSH phase PATCHed an immutable Google birthday event,
-- got `400 eventTypeRestriction`, threw, and aborted the whole run → the runner's
-- per-user catch set google_connections.status='error'. But claim_google_sync_users
-- (0009) only leased status='active' rows, so the cron never claimed that user
-- again — sync stalled permanently (every subsequent tick returned count:0).
--
-- Fix: claim status IN ('active','error'). Only 'revoked' (an invalid_grant / user
-- disconnect that needs a fresh OAuth consent) stays excluded. A transient or
-- per-event error now self-heals on the next 5-minute tick. The runner already
-- stamps status='active' + last_error=null on a clean success and last_error=<summary>
-- (status still 'active') on a per-event partial failure, so a recovered connection
-- leaves the 'error' state on its own.
--
-- The 0010 companion function change to the runner also makes per-event push
-- failures non-fatal, so 'error' is now reserved for genuinely fatal per-run faults
-- (vault/token/list failures) which are exactly what should be retried.
--
-- Idempotent / safe to re-run. Keeps 0009's security-definer + grant pattern verbatim.
-- ============================================================

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
      where c.status in ('active', 'error')
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
