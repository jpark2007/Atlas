# Account-Creation Parity + Mobile Color Match — Design

**Date:** 2026-07-09 · **Status:** approved by Drew (mechanism, starter set, and color scope all chosen explicitly)

Two independent workstreams, buildable in parallel.

---

## Workstream 1 — Account-creation parity (server-side seed)

### Problem

A new account created on iOS gets nothing: no spaces, no projects. The Mac, meanwhile,
seeds any zero-space account **on every login** from `MockData`
(`Atlas/Data/AppState.swift:277-301`, guard at :285) — literal demo fixtures
("Data Structures / CS 201", Prof. Alvarez, fake events pinned to today, fake goals).
That contradicts the standing onboarding decision (**editable templates, not demo
data, not blank**) and means an empty iOS account gets stuffed with demo data the
moment it signs into the Mac. The only server-side signup behavior today is the
`profiles`-row trigger (`supabase/migrations/0015_collab_foundations.sql:56-78`).

### Decisions (Drew, 2026-07-09)

1. **Mechanism: Postgres signup trigger + one-time backfill** (over an edge function
   or heal-on-login RPC). Fires for every signup on any platform with zero client
   code — drift is structurally impossible.
2. **Heal existing accounts:** the backfill in the same migration seeds every
   currently-empty account (including Drew's iOS test account).
3. **Content: implement the editable-templates onboarding decision now** — do NOT
   copy `MockData`.

### Starter set (exact)

| Space | `color_token` | Starter project | Flags |
|---|---|---|---|
| School | `'school'` (blue) | My First Class | `is_class = true` |
| Personal | `'personal'` (green) | Getting Started | — |

No tasks, no events, no notes, no goals. Empty projects already render an editable
scaffold on Mac (`AtlasCore/Sources/AtlasCore/ProjectTemplate.swift`) — class-flavored
for `is_class` — so the template feel comes free without persisting placeholder rows.
`color_token` values verified against the persisted `ColorToken` enum
(`AtlasCore/Sources/AtlasCore/AtlasDB.swift:27` — literal strings `school`/`personal`;
clients map them back to `AtlasTheme.Colors` on load).

### Design

**One new migration `supabase/migrations/0024_seed_starter_content.sql`; zero client
code added.** Follows the repo migration conventions (idempotent, additive).

1. **Seed function** `public.seed_starter_content(uid uuid)` — `SECURITY DEFINER`,
   `set search_path = public` (same shape as `handle_new_user`; must be definer
   because the trigger fires before any JWT exists and RLS applies otherwise).
   - Guard: return immediately if the user already has any row in `spaces`
     (`where not exists`). This makes it idempotent, prevents double-seeding, and
     never re-seeds an account whose owner intentionally deleted everything.
   - Inserts: 2 spaces + 2 projects per the table above, with explicit
     `user_id = uid` (the column default `auth.uid()` is null in trigger context),
     `space_id` FKs wired from the freshly inserted space ids, and the legacy
     `projects.space_name` (NOT NULL) filled in.
2. **Trigger** — new trigger function + `AFTER INSERT ON auth.users` trigger
   (alongside the existing `on_auth_user_created`; `handle_new_user` is left
   untouched). The trigger body wraps the seed call in an exception handler that
   swallows errors: a seed failure must **never block a signup** (worst case the
   account lands empty — same as today).
3. **Backfill** — in the same migration, run the seed function once for every
   existing `auth.users` row with zero spaces. Mirrors the 0015 backfill pattern.
4. **Mac cleanup (the only app-code change)** — remove the `MockData` →
   `db.seedInitial(...)` path from `AppState.bootstrap`
   (`Atlas/Data/AppState.swift:284-301`): keep `loadAll()` + the offline fallback
   behavior, delete only the write-to-Supabase seeding. `MockData` itself stays as
   the in-memory/offline fallback. Remove whatever `seedInitial` plumbing this
   orphans (nothing else uses it → verify before deleting).
5. **iOS: zero changes.** `MobileStore.refresh()` already just loads; the server has
   seeded before the first `loadAll()` can run.

### Verification

- Migration applies cleanly to prod (Supabase CLI, project ref `jxrmozhgsebwtbdleyxp`).
- PostgREST query confirms Drew's existing empty test account now has the 2 spaces +
  2 projects (backfill proof).
- Fresh Sign-in-with-Apple on device creates an account that shows the starter set on
  iOS immediately (trigger proof) — **needs Drew's device check**.
- Existing seeded/active accounts unchanged (guard proof: query a known non-empty
  account before/after).
- Mac builds green after the seed-path removal; a Mac login on the healed account
  shows the starter set and does NOT write MockData.

---

## Workstream 2 — Mobile color match (colors only)

### Problem / scope decision

iOS sits on a cool off-white palette; the Mac is warm paper-editorial. Both apps are
**light-only** (each forces `.preferredColorScheme(.light)`), so this is a same-mode
hue remap, not a dark/light flip. Drew chose **colors only** — radii (iOS 13/19/24 vs
Mac 10/14/18) and the Mac's serif screen titles are explicitly out of scope; he
reviews the color result on device first, then decides whether to go further.

### Design — three files, zero view files

1. **`AtlasMobile/Theme/MobileTheme.swift:14-24`** — remap 6 tokens to the Mac values
   from `AtlasCore/Sources/AtlasCore/Theme.swift:35-71`:
   - `bg` `#fbfaf7` → `#f2efe6`
   - `ink` `#1a191d` → `#211d17`
   - `muted` `#6c6a72` → `#565145`
   - `faint` `#9a98a0` → `#7d7669`
   - `hairline` `black @ 8%` → `#211d17 @ 12%`
   - `danger` `#c0392b` → `#ff5c5c` (kills the live two-reds inconsistency: several
     iOS views already use the shared `AtlasTheme.Colors.danger` `#ff5c5c` directly
     while Settings uses `MobileTheme.danger`)
   - `accent`/`accentText` already match (`#d97757`/`#b04f2f`) — untouched. Space
     colors already flow shared from AtlasCore — untouched.
2. **`AtlasMobileWidgets/WidgetTheme.swift:7-13`** — same remap (widget extension
   can't link the app target; it's a hand-mirrored copy by necessity).
3. **`Atlas/App/WindowConfigurator.swift:34`** — pre-existing Mac drift: the NSWindow
   background hardcodes stale `#fbfaf7` "cream"; fix to current `bgBase` `#f2efe6`.

No new tokens added; nothing speculative.

### Verification

- Both app targets (+ widget extension) build green.
- Per the working agreement: **a green build does not prove UI** — Drew checks the
  result on device (app + widgets + lock screen) before this is called done.

---

## Out of scope (explicit)

- iOS radii/serif-title parity (Drew decides after seeing colors).
- Any change to seeded content beyond the 2-spaces/2-projects set.
- Onboarding UI/flows; template editing features.
- The Mac Sign-in-with-Apple -7003 (Apple-side, tracked separately).

## Build notes

- Workstreams are independent → implement in parallel (Opus subagent on the
  migration, Sonnet subagent on colors, per Drew's standing subagent rule).
- Migration must be reviewed against real column constraints in
  `supabase/migrations/0001_init.sql` (+ alters 0015/0016/0017/0018) before apply.
