# Mobile backlog — for the next mobile session

Small items parked by Drew; pick these up whenever mobile work resumes. (v1 shipped
2026-07-02 @ 2eb86ca; feature work since lives in git history + .superpowers/sdd/progress.md.)

- **Placement button icon + position (Drew, 2026-07-02):** the Schedule header's
  add/place button currently uses `calendar.badge.plus` — Drew wants it MOVED and
  simplified to just a plus (or similar minimal glyph). Decide placement with him
  when picked up; don't guess.
- **Timeline LIST done-rows:** grid keeps completed tasks visible (strikethrough);
  the list view's done rows can drop on refresh (shared `AgendaBuilder` — touching
  it affects the Mac). Drew hasn't decided; ask before changing.
- **Slot-hold while already placing:** the empty-slot long-press stays active during
  chip placement. Flagged as a possible feel issue — await Drew's device verdict.
- **Schedule header density:** 5 controls in the second row post-W5 — check crowding
  on smaller devices during the next visual pass.
- **Canvas-phase items (bigger, already agreed):** search, real project grouping,
  post-commit capture undo — land when Canvas ICS floods task volume.
- **Delete account (Drew, 2026-07-07) — DONE 2026-07-09 (with Sign in with Apple):** the Mac now ships a "Delete account" action
  (Settings → account) backed by the deployed `delete-account` edge function
  (service-role `auth.admin.deleteUser`; cascade-wipes every user-scoped row + purges
  Google/Canvas Vault secrets). Mobile needs the same — a delete-account button in iOS
  settings that POSTs to `/functions/v1/delete-account` with a refresh-aware JWT, then
  clears the local session. **Backend already exists + is deployed** — this is iOS UI +
  the client call only, no new server work.

## Where we're at (2026-07-09, end of night — three batches shipped same day)

**Shipped + live:**
- Sign in with Apple (iOS, device-confirmed) + delete-account on both platforms.
- **Account-creation parity:** server-side seed (migration 0024: `auth.users`
  trigger + backfill, editable starter templates — School/Personal, "My First
  Class"/"Getting Started"); Mac client MockData seeding deleted; prod-verified.
  Prod drift found+fixed en route: 0020/0021 had never been applied (availability
  + shared-spaces tables were missing) — applied with Drew's approval.
- **Paper palette on iOS** (colors-only match, MobileTheme + widget mirror;
  two-reds drift fixed; Mac stale window-bg hex fixed).
- **Batch 2 fixes from Drew's device pass:** day grid scrolls natively (slot
  long-press removed), floating + on the schedule surface (auto-hides while
  placing), Tasks SPACE view always shows the spaces→projects cascade (respects
  the shared space filter), Sign in / Create account toggle on the auth screen.
- **Batch 3:** grid overscroll past the day's end (grid 300 / list 160 bottom
  margins — first pass, tune by feel), "No upcoming deadlines" DUE empty copy,
  **long-press drag-to-move for writable blocks** on the day grid (armed-move
  pattern; writability mirrors ItemDetailSheet.isEditable — Apple/read-only never
  lifts; snap-15 shared math; confirm/cancel circles; state resets on day/view
  change).

**Awaiting Drew's TestFlight pass:** grid scroll + overscroll feel; FAB placement
+ swap with placement circles; drag-to-move (arm, move, re-grab, confirm/cancel,
read-only blocks don't lift, moved Google event keeps syncing); fresh-account
cascade in Tasks; auth-mode toggle; paper palette; delete-account red legibility;
"No upcoming deadlines" copy.

**Open tickets:**
1. **`space_members` forward gap (pre-existing, both platforms):** no owner row
   is created for new spaces since 0021's one-time backfill → sharing any new
   space (incl. server-seeded ones) likely fails at `createSpaceInvite`. Fix:
   forward trigger on `spaces` (the seed function then inherits it for free).
2. **Canvas source flag (pre-existing, rule-5 class):** Canvas-origin items are
   indistinguishable from Atlas items on iOS (no source field; `EventSource` has
   no `.canvas`) — the edit sheet AND drag-to-move treat them as freely editable,
   and a server sync could clobber local edits. Needs a source flag at ingest.
3. **Danger red decision (Drew):** unified `#ff5c5c` fails AA (~2.6:1) on paper
   as delete-account TEXT — accept or darken `AtlasTheme.Colors.danger` app-wide.
4. **UI parity beyond colors** (radii, serif titles, calendar/school view
   layouts) — Drew decides after living with the colors; discuss-first.
5. **"Forgot password?" shows in create-account mode** — harmless; tidy someday.
6. Existing parked items above still stand (done-rows decision, header density,
   Canvas-phase items). Placement-button + slot-hold items are RESOLVED by the
   FAB + long-press removal.

**Mac-side open:** Sign in with Apple -7003 (Apple-side only; iOS proves the
config — try the App ID "Enable as primary" re-save, Apple ID sign-out/in, or
propagation time).
