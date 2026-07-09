-- ============================================================
-- 0024 — Server-side starter-content seed (account-creation parity)
-- A new account on ANY platform (Mac, iOS, future clients) gets the
-- editable starter set the moment the auth.users row exists:
--   School   (color_token 'school')   → "My First Class"  (is_class)
--   Personal (color_token 'personal') → "Getting Started"
-- No tasks/events/notes/goals — editable templates, not demo data
-- (per the standing onboarding decision; replaces the Mac's
-- client-side MockData seeding, removed in the same change set).
-- 1) seed function — skips any account that already has spaces, so it
--    never double-seeds and never re-seeds an intentionally emptied one.
-- 2) AFTER INSERT trigger on auth.users — exceptions swallowed so a
--    seed failure can never block a signup.
-- 3) one-shot backfill for existing zero-space accounts.
-- Idempotent: safe to re-run.
-- ============================================================

create or replace function public.seed_starter_content(uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    school_id   uuid;
    personal_id uuid;
begin
    -- Guard: never touch an account that already has data.
    if exists (select 1 from spaces where user_id = uid) then
        return;
    end if;

    school_id   := gen_random_uuid();
    personal_id := gen_random_uuid();

    insert into spaces (id, user_id, name, color_token, sort) values
        (school_id,   uid, 'School',   'school',   0),
        (personal_id, uid, 'Personal', 'personal', 1);

    -- space_name is the legacy NOT NULL text column; space_id is the
    -- 0015 FK. Both filled, mirroring how the clients dual-write.
    insert into projects (id, user_id, space_name, space_id, name, is_class) values
        (gen_random_uuid(), uid, 'School',   school_id,   'My First Class',  true),
        (gen_random_uuid(), uid, 'Personal', personal_id, 'Getting Started', false);
end;
$$;

-- Trigger wrapper: seeding must NEVER block account creation. Worst
-- case (seed bug) the account lands empty — same as before 0024.
create or replace function public.handle_new_user_seed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    begin
        perform public.seed_starter_content(new.id);
    exception when others then
        raise warning 'seed_starter_content failed for %: %', new.id, sqlerrm;
    end;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created_seed on auth.users;
create trigger on_auth_user_created_seed
    after insert on auth.users
    for each row execute function public.handle_new_user_seed();

-- Backfill: heal every existing zero-space account (the function's own
-- guard skips everyone who already has data).
do $$
declare u record;
begin
    for u in select id from auth.users loop
        perform public.seed_starter_content(u.id);
    end loop;
end $$;
