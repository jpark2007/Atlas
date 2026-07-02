-- ============================================================
-- Atlas — google-sync runner support (Task 3).
--
-- 1. read_google_secret(uuid) — the SERVICE-ROLE-only Vault READ wrapper the
--    sync runner needs. 0006 shipped create + delete wrappers but NO read one;
--    google-sync must decrypt a user's refresh token by vault_secret_id to mint
--    an access token. Vault's decrypted view isn't exposed over PostgREST, so we
--    reach it through this SECURITY DEFINER function (mirrors 0006's style).
--
-- 2. events.google_origin — the one bit the runner cannot infer from existing
--    columns. On a Google-side deletion the runner must DELETE a row that Google
--    owns but only UN-MIRROR (null the google_event_id) a row that is an
--    Atlas-origin mirror, so a user deleting the Google copy never destroys the
--    Atlas event. google_event_id alone can't tell the two apart (both carry a
--    gid), and subtitle is user-editable display text — mislabeling a source is
--    forbidden. This column is authoritative:
--        google_origin = true  ⇒ the runner must NEVER push this row to Google.
--    It is set true when the runner INSERTS a Google-origin row, and also when it
--    un-mirrors an Atlas row (gid nulled) so that detached row is never re-created
--    on Google (no resurrection loop). Every pre-existing row is an Atlas-origin
--    row (Google events were never persisted before this project), so the
--    default=false backfills correctly with no data touch.
--
-- Idempotent / safe to re-run.
-- ============================================================

-- ── Vault READ wrapper (SECURITY DEFINER, service-role only) ──
create or replace function public.read_google_secret(secret_id uuid)
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

revoke all on function public.read_google_secret(uuid) from public, anon, authenticated;
grant execute on function public.read_google_secret(uuid) to service_role;

-- ── events.google_origin (delete-vs-unmirror authority) ──────
alter table events add column if not exists google_origin boolean not null default false;
