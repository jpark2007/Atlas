-- =====================================================================
-- Atlas waitlist table — additive migration
--
--
-- Purely additive: creates one new table, touches nothing existing.
-- =====================================================================

create table if not exists public.waitlist (
  id         uuid        primary key default gen_random_uuid(),
  email      text        not null unique
             check (email = lower(email)),
  created_at timestamptz not null default now()
);

-- Row-level security on, with NO policies: only the service role (used by
-- the edge function) can read or write. No client can touch this table.
alter table public.waitlist enable row level security;
