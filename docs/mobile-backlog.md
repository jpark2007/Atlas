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
