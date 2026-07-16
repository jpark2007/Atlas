-- ============================================================
-- 0034 — Security hardening: lock down definer RPC + waitlist grants
--
-- M1: seed_starter_content(uuid) is a SECURITY DEFINER function (0024). Every
-- other definer function in this schema REVOKEs execute from the public roles;
-- 0024 forgot to, leaving it callable over PostgREST by anon/authenticated — a
-- caller could seed content into any user id they name. Revoke it here. The auth
-- trigger + one-shot backfill are UNAFFECTED: they invoke the function as the
-- table owner / superuser inside handle_new_user_seed (itself definer), not via
-- the PostgREST RPC grant we're removing.
--
-- L4: public.waitlist already has RLS on with no policies (0014), so clients get
-- nothing — but revoke the base-table grants explicitly too, matching how the
-- rest of the schema treats service-role-only tables. Defense in depth.
--
-- Purely restrictive. Idempotent / safe to re-run.
-- ============================================================

revoke all on function public.seed_starter_content(uuid) from public, anon, authenticated;

revoke all on table public.waitlist from anon, authenticated;
