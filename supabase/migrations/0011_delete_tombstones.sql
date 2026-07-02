-- ============================================================
-- Atlas — two-way event deletion: Atlas→Google delete tombstones.
--
-- User decision: "deleted anywhere = deleted everywhere." An events row deleted
-- in the app (Mac or phone — both just DELETE the row today) must also be removed
-- on Google. In server-sync mode the app has no Google credential, so the deletion
-- can only propagate through the runner. This migration records that intent:
--
--   deleted_google_events — a tombstone (user_id, google_event_id) written by an
--   AFTER DELETE trigger on `events` whenever a row that carried a google_event_id
--   is deleted. The google-sync runner reads a user's tombstones at the START of
--   each cycle, replays them as Google `DELETE /events/{id}` (404/410 = already
--   gone = success), then clears them. The pull side skips any incoming event whose
--   id still has a pending tombstone (handled in the runner) so a not-yet-deleted
--   event is never resurrected.
--
-- The trigger fires for the runner's OWN pull-side deletions too (a Google-side
-- cancellation now deletes the local row regardless of origin); the runner clears
-- those self-tombstones in the same run so no redundant Google DELETE is issued
-- next cycle. Work-block mirror gids live on `tasks`, not `events`, so this trigger
-- never fires for them.
--
-- Security: service-role full access; the trigger function is SECURITY DEFINER so
-- the tombstone is written no matter who deleted the row (an authenticated owner
-- via RLS, or the service-role runner). No client ever touches this table — RLS is
-- on with no client grants/policies (mirrors the service-role-only style of
-- 0006-0010).
--
-- Idempotent / safe to re-run.
-- ============================================================

create table if not exists deleted_google_events (
  user_id         uuid        not null
                              references auth.users on delete cascade,
  google_event_id text        not null,
  deleted_at      timestamptz not null default now(),
  primary key (user_id, google_event_id)
);

alter table deleted_google_events enable row level security;

-- Service-role only. No client access — the runner (service-role) reads and clears
-- these, and the trigger below writes them definer-side. No policies: authenticated
-- clients have no grant, so RLS has nothing to permit for them.
revoke all on table deleted_google_events from anon, authenticated;
grant all on table deleted_google_events to service_role;

-- ── AFTER DELETE trigger: tombstone a deleted mirrored event ──
-- SECURITY DEFINER so the insert succeeds regardless of the deleter's role (an
-- authenticated owner deleting via RLS still triggers a tombstone). ON CONFLICT
-- DO NOTHING keeps re-deletes / races idempotent. Mirrors 0006/0007's definer style.
create or replace function public.record_deleted_google_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.google_event_id is not null then
    insert into public.deleted_google_events (user_id, google_event_id)
    values (old.user_id, old.google_event_id)
    on conflict (user_id, google_event_id) do nothing;
  end if;
  return old;
end;
$$;

revoke all on function public.record_deleted_google_event() from public, anon, authenticated;

drop trigger if exists events_record_deleted_google_event on events;
create trigger events_record_deleted_google_event
  after delete on events
  for each row
  execute function public.record_deleted_google_event();
