-- ============================================================
-- Atlas — google-sync scheduling (Task 4).
--
-- Runs the google-sync Edge Function (the two-way runner) every 5 minutes so
-- Google ↔ Supabase stays in sync for every active connection while the Mac is
-- closed. pg_cron fires the tick; pg_net POSTs to the function URL.
--
-- Auth: the function is service-role-only. The cron must present the project's
-- service_role key as a Bearer token. That key is NEVER written into this
-- migration or into cron.job.command — it lives in Supabase Vault under the name
-- 'google_sync_service_role_key' and is read at tick time through the
-- SECURITY DEFINER helper below (mirrors 0006/0007's read_google_secret pattern).
--
-- One-time operational step (out of band, NOT in this migration — no secret is
-- committed): store the service_role key in Vault, e.g.
--     select vault.create_secret('<SERVICE_ROLE_KEY>', 'google_sync_service_role_key',
--                                 'service_role JWT used by the google-sync pg_cron');
-- The helper returns NULL until it exists, so a tick before setup is a harmless
-- 401 rather than an error.
--
-- To remove the schedule:
--     select cron.unschedule('google-sync-every-5m');
--
-- Idempotent / safe to re-run (extensions guarded; cron.schedule upserts by name;
-- the helper is create-or-replace).
-- ============================================================

-- ── Extensions (available on Supabase; no-op if already enabled) ──
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ── Vault READ wrapper for the service_role key (SECURITY DEFINER) ──
-- Reads the Bearer credential by name so cron.job.command never contains the key
-- itself. Vault's decrypted view isn't exposed over PostgREST; this reaches it
-- the same way 0007's read_google_secret does. Service-role / owner only.
create or replace function public.read_google_sync_service_key()
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
   where name = 'google_sync_service_role_key';
  return val;
end;
$$;

revoke all on function public.read_google_sync_service_key() from public, anon, authenticated;
grant execute on function public.read_google_sync_service_key() to service_role;

-- ── Schedule: POST google-sync every 5 minutes ──────────────
-- cron.schedule(name, ...) upserts by name, so re-running replaces the job.
-- The Authorization value is assembled at tick time from the Vault helper; the
-- key never appears here.
select cron.schedule(
  'google-sync-every-5m',
  '*/5 * * * *',
  $job$
  select net.http_post(
    url     := 'https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/google-sync',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || public.read_google_sync_service_key()
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $job$
);
