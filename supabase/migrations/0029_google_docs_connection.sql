-- ============================================================
-- Atlas — dedicated Notes & Docs Google connection.
--
-- Drive/Docs background work (drive-writeback, drive-import's inline pull,
-- reference-pull, and the shared mintAccessToken fallback) must run off ONE
-- explicitly designated Google sign-in, independent of the N calendar
-- connections (google_connections, 0028). This is a per-user singleton — one
-- Docs account at a time — so it stays keyed by user_id (PK), like the original
-- google_connections in 0006. The calendar runner is untouched; it always mints
-- by an explicit connection secret.
--
-- Idempotent / safe to re-run (matches 0006 / 0028 style).
-- ============================================================

-- ── google_docs_connections: the singleton Drive/Docs sign-in ──
-- google_email = which login (display + dedupe); vault_secret_id points into
-- vault.secrets (refresh token) and is service-role only, never granted to clients.
create table if not exists google_docs_connections (
  user_id         uuid        primary key
                              references auth.users on delete cascade,
  google_email    text        not null,
  vault_secret_id uuid,
  status          text        not null default 'active'
                              check (status in ('active', 'error', 'revoked')),
  last_error      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists google_docs_connections_set_updated_at on google_docs_connections;
create trigger google_docs_connections_set_updated_at
  before update on google_docs_connections
  for each row
  execute function public.set_updated_at();

alter table google_docs_connections enable row level security;

-- Owner may read the non-secret columns and disconnect. Inserts/updates and the
-- vault_secret_id pointer are service-role only (google-connect edge fn), so the
-- refresh-token pointer is never exposed to authenticated clients. Mirrors the
-- google_connections grant/policy shape in 0028.
revoke all on table google_docs_connections from anon, authenticated;
grant select (user_id, google_email, status, last_error, created_at, updated_at)
  on table google_docs_connections to authenticated;
grant delete on table google_docs_connections to authenticated;
grant all on table google_docs_connections to service_role;

drop policy if exists "google_docs_connections: owner reads status" on google_docs_connections;
create policy "google_docs_connections: owner reads status" on google_docs_connections
  for select
  using (auth.uid() = user_id);

drop policy if exists "google_docs_connections: owner disconnects" on google_docs_connections;
create policy "google_docs_connections: owner disconnects" on google_docs_connections
  for delete
  using (auth.uid() = user_id);
