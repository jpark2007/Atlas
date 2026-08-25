-- ============================================================
-- 0042_school_terms.sql — School framework, stage A (data layer)
--
-- School stops being "projects with school names" and becomes a real
-- framework: Term → Class → work. This migration lays the storage the
-- UI stages build on.
--
--   1. `terms`    — a first-class object. A class belongs to exactly one
--                   term; the app filters by the active term. Key Dates
--                   (classes begin, add/drop, holidays, breaks) live HERE,
--                   on the term, as a jsonb array — a child table buys
--                   nothing when the whole list is always read and written
--                   with its term.
--   2. `projects` — gains `term_id` (a class's term), `archived_at`
--                   (SOFT archive: ending a term never wipes a class —
--                   grades/notes stay queryable, just out of the way),
--                   `meeting_pattern` (structured meeting blocks) and
--                   `class_info` (the syllabus-scan info card).
--                   Classes stay `projects` rows — extending the table
--                   the clients already round-trip beats a parallel
--                   `classes` table nobody else knows about.
--   3. `user_settings.school_enabled` — nullable on purpose. NULL means
--                   "not chosen": the client defaults School ON for a
--                   user who has any class and OFF otherwise, so nobody
--                   is asked a question they've already answered by
--                   having classes.
--   4. `seed_starter_content` re-created WITHOUT the fake 'My First
--                   Class' project. New accounts get the two spaces and
--                   'Getting Started'; School shows the "Set up your
--                   semester" wizard instead of a seeded example class.
--                   Re-created here rather than by editing 0024, per
--                   house style (migrations are append-only).
--
-- Idempotent; safe to re-run.
-- ============================================================

-- ── 1. terms ────────────────────────────────────────────────

create table if not exists terms (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,
  name        text not null,                 -- "Fall 2026"
  starts_on   date,
  ends_on     date,
  -- Key Dates: jsonb array of {label, date, kind?} —
  --   label : "Add/drop deadline"
  --   date  : 'YYYY-MM-DD'
  --   kind  : optional flag the calendar renders by —
  --           'classes_begin' | 'classes_end' | 'add_drop' | 'holiday'
  --           | 'break' | 'finals' | 'deadline' | 'other'
  -- Seeded from a registrar academic calendar when one is available,
  -- else typed once. Unknown kinds decode as 'other' client-side, so a
  -- future flag never breaks an older client.
  key_dates   jsonb not null default '[]'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists terms_user_id_idx on terms (user_id);

alter table terms enable row level security;

drop policy if exists "terms: owner access" on terms;
create policy "terms: owner access" on terms
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists terms_set_updated_at on terms;
create trigger terms_set_updated_at
  before update on terms
  for each row execute function public.set_updated_at();

-- ── 2. projects (classes) ───────────────────────────────────

-- `on delete set null`: deleting a term must never delete its classes.
-- An orphaned class surfaces as "needs a term" and is re-dated, never lost.
alter table projects add column if not exists term_id uuid references terms(id) on delete set null;

-- Soft archive. Ending a term stamps this; nothing is ever deleted.
-- NULL = active.
alter table projects add column if not exists archived_at timestamptz;

-- Structured meeting blocks: jsonb array of
--   { weekdays: [int], start: "HH:mm", end: "HH:mm", location?: text }
-- `weekdays` uses Foundation's 1 = Sunday … 7 = Saturday so the client
-- lays blocks out without a lookup table. An ARRAY of weekdays (not one
-- per row) keeps "MWF 10:00–10:50" a single block.
--
-- Rotation timetables (A/B days) are explicitly NOT built (college is the
-- target), but the shape allows them: a block is an open object, so a
-- later `rotation_day` key is additive and old clients ignore it.
-- Free-text `meeting_info` survives as an optional note, not as structure.
alter table projects add column if not exists meeting_pattern jsonb;

-- The syllabus-scan "Class info" card, filled by stage C:
--   { grade_weights: [text], policies: [text], office_hours?: text }
-- Static display strings only — no grades tracking (scope freeze).
alter table projects add column if not exists class_info jsonb;

create index if not exists projects_term_id_idx on projects (term_id);

-- ── 3. user_settings.school_enabled ─────────────────────────

-- NULL = never chosen ⇒ client default: ON when the user has any class.
alter table user_settings add column if not exists school_enabled boolean;

-- ── 4. seed_starter_content without the fake class ──────────

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

    -- No seeded class: School greets a new account with the "Set up your
    -- semester" wizard, which builds the real ones. space_name is the
    -- legacy NOT NULL text column; space_id is the 0015 FK — both filled,
    -- mirroring how the clients dual-write.
    insert into projects (id, user_id, space_name, space_id, name, is_class) values
        (gen_random_uuid(), uid, 'Personal', personal_id, 'Getting Started', false);
end;
$$;
