-- ============================================================
-- Atlas — abuse limits: a shared, DB-backed fixed-window rate limiter.
--
-- One tiny table + one atomic RPC power every edge function's per-endpoint
-- budget (see supabase/functions/_shared/rate_limit.ts). A "hit" is a single
-- upsert that both records and counts the request for the current time window,
-- so two concurrent requests can never race past the limit (the increment +
-- read happens in one statement under the row lock).
--
-- The key is the caller's identity: the verified user id for authenticated
-- endpoints, or the client IP for the public waitlist. Rows are per
-- (key, endpoint, window) and are disposable — an old window is just dead
-- weight; a periodic reap (below) trims them. No client can read or write this
-- table; only the service-role edge functions call the RPC.
--
-- Purely additive. Idempotent / safe to re-run.
-- ============================================================

create table if not exists public.rate_limits (
  key          text        not null,
  endpoint     text        not null,
  window_start timestamptz not null,
  count        integer     not null default 0,
  primary key (key, endpoint, window_start)
);

-- Only the service role (the edge functions) may touch this table. RLS on with
-- NO policies = no client access at all.
alter table public.rate_limits enable row level security;

-- Reap helper: an index on window_start makes trimming stale windows cheap.
create index if not exists rate_limits_window_start_idx
  on public.rate_limits (window_start);

-- ── The atomic hit ──────────────────────────────────────────
-- Floor now() to the window boundary, bump this (key, endpoint, window)'s
-- counter, and report whether the caller is still under budget. `retry_after`
-- is the seconds until the current window rolls over (for the 429 Retry-After
-- header). A single upsert ... returning makes the read-modify-write atomic.
create or replace function public.rate_limit_hit(
  p_key             text,
  p_endpoint        text,
  p_limit           integer,
  p_window_seconds  integer
)
returns table (allowed boolean, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_start timestamptz;
  v_count        integer;
begin
  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limits (key, endpoint, window_start, count)
  values (p_key, p_endpoint, v_window_start, 1)
  on conflict (key, endpoint, window_start)
    do update set count = public.rate_limits.count + 1
  returning count into v_count;

  if v_count > p_limit then
    allowed := false;
    retry_after := ceil(
      extract(epoch from (v_window_start + make_interval(secs => p_window_seconds) - now()))
    )::integer;
    if retry_after < 1 then retry_after := 1; end if;
  else
    allowed := true;
    retry_after := 0;
  end if;
  return next;
end;
$$;

-- ── Optional reaper ─────────────────────────────────────────
-- Rows for windows older than a day are pure dead weight. This trims them; wire
-- it to pg_cron if the table ever grows, or call it ad hoc. Not scheduled here
-- (per-user cardinality is low; kept simple).
create or replace function public.reap_rate_limits()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.rate_limits where window_start < now() - interval '1 day';
$$;
