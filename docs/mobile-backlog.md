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

## Next steps (2026-07-09, from Drew's device test)

Sign in with Apple on iOS is CONFIRMED WORKING on device; mobile delete-account
shipped alongside it. What the test surfaced, in Drew's priority order:

1. **Account-creation parity (bug-class, do first):** a new account created on
   mobile gets NO auto-created spaces structure / starter templates — creating an
   account must be seamless and exactly the same on both platforms. Direction per
   Drew's standing onboarding decision: editable templates (not demo seed, not
   blank). Recommend seeding server-side (signup trigger/edge function) so Mac and
   iOS can't drift.
2. **UI matching pass:** bring the mobile app visually in line with the Mac
   (paper-editorial), including the calendar and school (Canvas) views. DISCUSS
   SCOPE WITH DREW FIRST — his standing rule for the mobile reskin.
3. Existing parked items above still stand (placement button, done-rows decision,
   slot-hold feel, header density, Canvas-phase items).
