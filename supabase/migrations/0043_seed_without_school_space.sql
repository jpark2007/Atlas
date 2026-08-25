-- ============================================================
-- 0043 — Starter seed: Personal only, no "School" space
--
-- 0024 seeded two spaces: School (+ "My First Class") and Personal
-- (+ "Getting Started"). Since the School framework shipped, school is
-- a top-level section of its own — a "School" SPACE sitting under the
-- School SECTION reads as two Schools, and the seeded class is exactly
-- the fake starter content the onboarding decision rules out.
--
-- New accounts now get:
--   Personal (color_token 'personal') → "Getting Started"
-- and nothing else. A student's classes arrive through School → Add
-- your classes, into whatever space that flow resolves.
--
-- Replaces the function body only. The trigger from 0024 stands, and
-- `create or replace` keeps the 0034 revokes in place (privileges
-- survive a replace) — they are restated anyway, defense in depth.
--
-- NO backfill: existing accounts keep whatever they already have. The
-- Mac client folds an empty leftover "School" space out of the sidebar
-- rather than deleting anyone's bucket.
--
-- Idempotent: safe to re-run.
-- ============================================================

create or replace function public.seed_starter_content(uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    personal_id uuid;
begin
    -- Guard: never touch an account that already has data.
    if exists (select 1 from spaces where user_id = uid) then
        return;
    end if;

    personal_id := gen_random_uuid();

    insert into spaces (id, user_id, name, color_token, sort) values
        (personal_id, uid, 'Personal', 'personal', 0);

    -- space_name is the legacy NOT NULL text column; space_id is the
    -- 0015 FK. Both filled, mirroring how the clients dual-write.
    insert into projects (id, user_id, space_name, space_id, name, is_class) values
        (gen_random_uuid(), uid, 'Personal', personal_id, 'Getting Started', false);
end;
$$;

revoke all on function public.seed_starter_content(uuid) from public, anon, authenticated;
