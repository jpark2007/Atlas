# Account-Creation Parity + Mobile Color Match — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every new account on any platform gets the editable starter set (School + Personal, one template project each) seeded server-side; existing empty accounts heal; iOS matches the Mac paper palette.

**Architecture:** One Postgres migration (seed function + `auth.users` trigger + backfill) replaces the Mac's client-side MockData seeding, which gets deleted. Separately, iOS's central `MobileTheme` (plus the widget mirror) gets a 6-token remap to the Mac values, and a stale Mac window-background hex is corrected.

**Tech Stack:** Supabase Postgres migrations (plain SQL, idempotent), SwiftUI (macOS 14 / iOS 17), XcodeGen project `Atlas.xcodeproj`.

**Spec:** `docs/specs/2026-07-09-account-parity-and-mobile-colors-design.md` (approved by Drew 2026-07-09).

## Global Constraints

- **NEVER touch the live Supabase project** (ref `jxrmozhgsebwtbdleyxp`) from a task — no `supabase db push`, no PostgREST writes, no function deploys. Applying the migration is Task 5, run by the controller/owner only.
- Mac build gate: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- iOS build gate: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` (builds the widget extension too — it's a target dependency).
- SourceKit "Cannot find AppState/AtlasTheme/…" single-file diagnostics are noise; `xcodebuild` is the source of truth.
- Surgical changes only: touch exactly the files each task lists. Match existing style.
- Starter-set strings are FROZEN (spec §Starter set): spaces `School` (`color_token 'school'`) and `Personal` (`'personal'`); projects `My First Class` (`is_class = true`, in School) and `Getting Started` (in Personal). No tasks/events/notes/goals are seeded.
- Commit after each task; end every commit message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- No test runner exists for SQL or these Swift surfaces; verification is read-through checks + build gates as written in each task (matches this repo's prior migration plans).

---

### Task 1: Migration 0024 — seed function, signup trigger, backfill

**Files:**
- Create: `supabase/migrations/0024_seed_starter_content.sql`
- Read (validation only): `supabase/migrations/0001_init.sql`, `supabase/migrations/0015_collab_foundations.sql`

**Interfaces:**
- Consumes: `spaces(id, user_id, name, color_token, sort)` and `projects(id, user_id, space_name, space_id, name, is_class)` as defined in 0001 (+ `projects.space_id` from 0015). Existing trigger `on_auth_user_created` / function `handle_new_user()` from 0015 stay untouched.
- Produces: `public.seed_starter_content(uid uuid) returns void` (idempotent), trigger `on_auth_user_created_seed` on `auth.users`. Task 2's Mac cleanup and Task 5's apply/verify rely on exactly these names and the frozen starter strings.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0024_seed_starter_content.sql` with exactly:

```sql
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
```

- [ ] **Step 2: Read-through validation (no DB access)**

Read `supabase/migrations/0001_init.sql` and `supabase/migrations/0015_collab_foundations.sql` and confirm every referenced column exists and constraints are satisfied:
- `spaces`: `id` (uuid PK, no default — we supply it), `user_id` (NOT NULL — supplied explicitly because `auth.uid()` is NULL in trigger/definer context), `name`, `color_token`, `sort` — all NOT NULL columns covered.
- `projects`: `id`, `user_id`, `space_name` (NOT NULL text), `name` (NOT NULL) supplied; `space_id` FK references the space inserted two statements earlier in the same transaction; `code/meeting_info/instructor` nullable, `canvas_synced/overview` defaulted — safe to omit.
- Function style matches `handle_new_user` (0015): `security definer set search_path = public`, `drop trigger if exists` + `create trigger`.
- Trigger name `on_auth_user_created_seed` does not collide with the existing `on_auth_user_created`.

Expected: every check passes. If any column/constraint does not match, STOP and report the mismatch instead of adapting silently.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0024_seed_starter_content.sql
git commit -m "feat(db): 0024 server-side starter-content seed (signup trigger + backfill)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Remove the Mac's client-side MockData seeding

**Files:**
- Modify: `Atlas/Data/AppState.swift:270-301` (doc comment + `bootstrap`)
- Modify: `AtlasCore/Sources/AtlasCore/AtlasDB.swift` (delete `seedInitial` and helpers it orphans)

**Interfaces:**
- Consumes: server-side seeding from Task 1 (migration 0024) — the Mac no longer detects/first-run-seeds; it only loads.
- Produces: `AppState.bootstrap(db:userID:)` keeps its exact signature and all post-load behavior (applySnapshot, expandedSpaces, profile/collab/Google/Canvas tail). `AtlasDB.seedInitial` ceases to exist — nothing outside `bootstrap` calls it today.

- [ ] **Step 1: Replace the seeding block in `bootstrap`**

In `Atlas/Data/AppState.swift`, the method currently reads (lines 272-301):

```swift
    /// Load all persisted data for the signed-in user. Seeds from MockData on
    /// first run (empty DB). On any failure keeps the existing in-memory MockData
    /// so the UI is never left blank. Stores the `db` reference for write-through.
    /// Keyed on `userID` so signing into a different account re-loads instead of
    /// keeping (and writing into) the previous user's data.
    func bootstrap(db: AtlasDB, userID: String?) async {
        guard bootstrappedUser != userID else { return }
        bootstrappedUser = userID
        self.db = db
        do {
            var snapshot = try await db.loadAll()

            // First-run detection: no spaces means a fresh account.
            if snapshot.spaces.isEmpty {
                // Flatten nested MockData into the AtlasSnapshot shape AtlasDB expects.
                let flatSpaces = MockData.spaces.map {
                    Space(id: $0.id, name: $0.name, color: $0.color, projects: [])
                }
                let flatProjects = MockData.spaces.flatMap { $0.projects }
                let seed = AtlasSnapshot(
                    spaces:   flatSpaces,
                    projects: flatProjects,
                    tasks:    MockData.tasks,
                    events:   MockData.events,
                    notes:    MockData.notes,
                    goals:    MockData.goals
                )
                try await db.seedInitial(seed)
                snapshot = try await db.loadAll()
            }
```

Replace that region (doc comment through the seeding `if` block, keeping everything from `applySnapshot(snapshot)` on unchanged) with:

```swift
    /// Load all persisted data for the signed-in user. Starter content for a
    /// fresh account is seeded SERVER-SIDE (migration 0024's signup trigger),
    /// so this only loads. On any failure keeps the existing in-memory MockData
    /// so the UI is never left blank. Stores the `db` reference for write-through.
    /// Keyed on `userID` so signing into a different account re-loads instead of
    /// keeping (and writing into) the previous user's data.
    func bootstrap(db: AtlasDB, userID: String?) async {
        guard bootstrappedUser != userID else { return }
        bootstrappedUser = userID
        self.db = db
        do {
            let snapshot = try await db.loadAll()
```

(`var snapshot` becomes `let snapshot`; the `// First-run detection…` block is gone entirely. `MockData` remains referenced by the initial in-memory state and the catch-branch fallback — do NOT touch `MockData.swift` or the `catch` block.)

- [ ] **Step 2: Delete the code this orphans in AtlasCore**

`AppState.swift:299` was the ONLY caller of `seedInitial`. Verify, then delete:

```bash
grep -rn "seedInitial" --include="*.swift" . | grep -v ".build"
```
Expected after the Step 1 edit: only the `AtlasCore/Sources/AtlasCore/AtlasDB.swift:1294` definition remains.

Delete from `AtlasCore/Sources/AtlasCore/AtlasDB.swift`: the `seedInitial` method **including its doc comment** (`/// Seed all tables from a snapshot…`, currently lines ~1290-1327). Then check its two private helpers:

```bash
grep -n "columnList\|seedRows" AtlasCore/Sources/AtlasCore/AtlasDB.swift
```
Expected: after deleting `seedInitial`, `columnList` and `seedRows` (and their doc comments) have no remaining callers — delete both. If either DOES have another caller, keep it and report which.

- [ ] **Step 3: Build the Mac app**

```bash
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`. Also build iOS (AtlasCore is shared; confirm nothing mobile referenced the deleted helpers):

```bash
xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Atlas/Data/AppState.swift AtlasCore/Sources/AtlasCore/AtlasDB.swift
git commit -m "feat(mac): drop client-side MockData seeding — server seeds starter content (0024)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: iOS + widget palette remap to Mac paper values

**Files:**
- Modify: `AtlasMobile/Theme/MobileTheme.swift:14-24` (+ one stale comment at :81)
- Modify: `AtlasMobileWidgets/WidgetTheme.swift:7-13`

**Interfaces:**
- Consumes: Mac values from `AtlasCore/Sources/AtlasCore/Theme.swift:35-71` (source of truth; do not modify it).
- Produces: same token NAMES (`bg/ink/muted/faint/hairline/accent/accentText/danger`) — no call-site changes anywhere; 16 view files pick the new values up automatically.

- [ ] **Step 1: Remap `MobileTheme` tokens**

In `AtlasMobile/Theme/MobileTheme.swift`, replace lines 13-24:

```swift
    // MARK: Colors  (Color(hex:) comes from AtlasCore)
    static let bg      = Color(hex: "fbfaf7")
    static let ink     = Color(hex: "1a191d")
    static let muted   = Color(hex: "6c6a72")
    static let faint   = Color(hex: "9a98a0")
    static let hairline = Color.black.opacity(0.08)
    /// Clay accent — graphics only (NOW / live / brand). Never a fill.
    static let accent     = Color(hex: "d97757")
    /// Darkened accent for TEXT on light surfaces (AA).
    static let accentText = Color(hex: "b04f2f")
    /// Danger red for destructive TEXT (delete account) — darkened for light bg (AA).
    static let danger     = Color(hex: "c0392b")
```

with (values = Mac `AtlasTheme.Colors`, `Theme.swift:35-71`):

```swift
    // MARK: Colors  (Color(hex:) comes from AtlasCore; values match the Mac's
    // AtlasTheme.Colors paper palette — keep the two in lockstep)
    static let bg      = Color(hex: "f2efe6")
    static let ink     = Color(hex: "211d17")
    static let muted   = Color(hex: "565145")
    static let faint   = Color(hex: "7d7669")
    static let hairline = Color(hex: "211d17").opacity(0.12)
    /// Clay accent — graphics only (NOW / live / brand). Never a fill.
    static let accent     = Color(hex: "d97757")
    /// Darkened accent for TEXT on light surfaces (AA).
    static let accentText = Color(hex: "b04f2f")
    /// Danger red — same token as AtlasTheme.Colors.danger (several views
    /// already use the shared value directly; this ends the two-reds drift).
    static let danger     = Color(hex: "ff5c5c")
```

Also update the now-stale comment at line 81 — `/// Hairline rule (black 8%) along the bottom edge — the editorial row separator.` → `/// Hairline rule (ink 12%) along the bottom edge — the editorial row separator.`

- [ ] **Step 2: Remap `WidgetTheme` (hand-mirrored copy — can't link the app target)**

In `AtlasMobileWidgets/WidgetTheme.swift`, replace lines 6-14:

```swift
enum WidgetTheme {
    static let bg      = Color(hex: "fbfaf7")
    static let ink     = Color(hex: "1a191d")
    static let muted   = Color(hex: "6c6a72")
    static let faint   = Color(hex: "9a98a0")
    static let hairline = Color.black.opacity(0.08)
    static let accent     = Color(hex: "d97757")
    static let accentText = Color(hex: "b04f2f")
}
```

with:

```swift
enum WidgetTheme {
    static let bg      = Color(hex: "f2efe6")
    static let ink     = Color(hex: "211d17")
    static let muted   = Color(hex: "565145")
    static let faint   = Color(hex: "7d7669")
    static let hairline = Color(hex: "211d17").opacity(0.12)
    static let accent     = Color(hex: "d97757")
    static let accentText = Color(hex: "b04f2f")
}
```

(No `danger` token here today — do not add one.)

- [ ] **Step 3: Build iOS (app + widget extension)**

```bash
xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add AtlasMobile/Theme/MobileTheme.swift AtlasMobileWidgets/WidgetTheme.swift
git commit -m "feat(mobile): match Mac paper palette — 6-token remap, ends two-reds drift

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Fix the Mac's stale window-background hex

**Files:**
- Modify: `Atlas/App/WindowConfigurator.swift:34`

**Interfaces:**
- Consumes: current `bgBase` = `#f2efe6` (`AtlasCore/Sources/AtlasCore/Theme.swift`, flat paper surface).
- Produces: nothing downstream — cosmetic correctness fix.

- [ ] **Step 1: Replace the hardcoded color**

Line 34 currently:

```swift
        window.backgroundColor = NSColor(srgbRed: 0xfb/255, green: 0xfa/255, blue: 0xf7/255, alpha: 1) // bgBase (cream)
```

Replace with:

```swift
        window.backgroundColor = NSColor(srgbRed: 0xf2/255, green: 0xef/255, blue: 0xe6/255, alpha: 1) // bgBase (paper #f2efe6)
```

- [ ] **Step 2: Build the Mac app**

```bash
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Atlas/App/WindowConfigurator.swift
git commit -m "fix(mac): window background matches current bgBase (#f2efe6), was stale cream

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Apply + verify (CONTROLLER/OWNER ONLY — not a subagent task)

**Files:** none (live operations against project ref `jxrmozhgsebwtbdleyxp`).

**Interfaces:**
- Consumes: Task 1's migration; Tasks 2-4 merged.
- Produces: live parity. Order matters: apply the migration BEFORE anyone signs up on a build that no longer client-seeds.

- [ ] **Step 1: Apply the migration** — `supabase db push` (linked project). Expected: `0024_seed_starter_content.sql` listed as applied, no errors.
- [ ] **Step 2: Verify backfill healed the empty iOS test account** — with the service-role key (from `supabase projects api-keys --project-ref jxrmozhgsebwtbdleyxp`):

```bash
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/rest/v1/profiles?select=user_id,email" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY"
# find the test account's user_id, then:
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/rest/v1/spaces?user_id=eq.<uid>&select=name,color_token,sort" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY"
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/rest/v1/projects?user_id=eq.<uid>&select=name,space_name,is_class" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY"
```
Expected: exactly `School('school',0)` + `Personal('personal',1)`; `My First Class(School,true)` + `Getting Started(Personal,false)`.
- [ ] **Step 3: Verify the guard (no-op on seeded accounts)** — same queries for Drew's main account: space/project counts UNCHANGED from before the push.
- [ ] **Step 4: Drew's device checks (UI is not provable by a green build)** — (a) fresh Sign-in-with-Apple account on iPhone shows School/Personal + the two starter projects immediately; (b) iOS + widgets show the paper palette; (c) Mac window background matches. Status stays "applied, builds, needs your check" until confirmed.
