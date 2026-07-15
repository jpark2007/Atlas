-- ============================================================
-- Atlas — fix: account deletion fails for users with Google-mirrored events.
--
-- auth.admin.deleteUser cascades the user's `events` rows; each mirrored row
-- (google_event_id not null) fires `record_deleted_google_event`, which inserts
-- a tombstone referencing the very user being deleted. The parent auth.users row
-- is already gone mid-cascade, so the insert raises
-- `deleted_google_events_user_id_fkey` and aborts the whole account deletion
-- (delete-account edge function → 500 "Couldn't delete your account").
--
-- Fix: a tombstone is meaningless when the OWNER is being erased (their Google
-- connection dies with them), so the trigger now swallows the FK violation and
-- lets the cascade proceed. Normal single-event deletes are unchanged.
--
-- Idempotent / safe to re-run.
-- ============================================================

create or replace function public.record_deleted_google_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.google_event_id is not null then
    begin
      insert into public.deleted_google_events (user_id, google_event_id)
      values (old.user_id, old.google_event_id)
      on conflict (user_id, google_event_id) do nothing;
    exception when foreign_key_violation then
      -- The owning auth.users row is mid-delete (account deletion cascade):
      -- no Google connection will survive to replay this, so skip the tombstone.
      null;
    end;
  end if;
  return old;
end;
$$;
