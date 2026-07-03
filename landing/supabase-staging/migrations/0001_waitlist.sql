-- =====================================================================
-- Atlas waitlist table — additive migration  (STAGING COPY — NOT APPLIED)
--
-- This SQL lives in landing/supabase-staging/ only. It is NOT part of the
-- app's real supabase/migrations tree. To apply it, move this file into
-- supabase/migrations/ (with a fresh timestamped name) and run the normal
-- migration flow. See landing/README.md.
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
