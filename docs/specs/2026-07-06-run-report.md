# Attack-plan run report — 2026-07-06

All three phases of `docs/archive/specs/2026-07-06-dashboard-focus-perf-plan.md` are **implemented, code-reviewed,
and pushed to `origin/main`**. Every commit built green (`xcodebuild`, macOS Debug). Per the
mid-run instruction, no UI was launched or screenshotted after Wave 0 — **everything visual below
needs Drew's pass** (§4 is the test list).

## 1. What shipped

**Phase 1 — reskin** (`f4c0285`, `d0c5274`, `4e68f73`, fix `a2a945d`)
- Theme tokens → paper `#f2efe6` / ink triplet / ink-12% hairlines; type-role helpers
  (`atlasMono`, `atlasTitleSerif`, `atlasTag`, `wash`).
- App-wide: square checkboxes (done = clay), wash tags (no pills/outlines), serif content
  titles, sidebar clay-tick + ink-wash hover (fills removed), calendar numerals mono, ~56-site
  mono sweep, 12-hour verified everywhere.
- Review: 0 Critical / 1 Important / 5 Minor → Important + 3 minors fixed; Settings dead fills
  deferred to P3.2 (done there).

**Phase 2 — features & fixes** (`872e543`, `e048b6b`, `2dd53e3`, fix `ef108fc`)
- **2.1** Task ↔ note linking: LINKED NOTE section on task detail (pick / new / unlink), linked
  note + `.docNote` reference rows open the in-app corner-card editor; "Open in Google Docs"
  demoted to a secondary "Doc ↗" button. New `AppState.setTaskNote`.
- **2.2/2.3** Perf: collab members P fetches → 1 grouped fetch (also on realtime events);
  bootstrap tail (profile/collab/Google/Canvas) now concurrent; first-run seed = 6 batch POSTs
  with explicit `?columns=` (was dozens of serial row POSTs). 67/67 AtlasCore tests.
- **2.4** Editor bugs: underline `<u>` round-trip + Done-hides-window were **already fixed at
  HEAD** (committed `ae149a1`; verified, 24/24 tests). `access_denied` root-caused as a consent
  denial → humanized banner + one-click **Reconnect** in Settings. Native (non-Doc) notes now
  hide B/I/U instead of offering-then-eating them (see decision D4).
- **2.5** Doc-note freshness: 30s foreground refresh while a doc-note is open (45s at project
  level), dirty-buffer guard ("newer version synced" banner + explicit Reload — never clobbers),
  live "Last synced Xm ago", **Sync now** on rows + editor (see decision D5).
- **2.7** Focus mode: sidebar "Start focus" + dashboard entry → true fullscreen; corner
  instrument-timer (pause/skip/end); `NotesListView` as the in-session work surface; ⌘K scoped
  to notes in-session (picks/creates open the corner card); quick sticky note (no project, no
  Doc); menu-bar `MM:SS` countdown + Pause/Resume/End, visible when Atlas isn't frontmost;
  Esc order: palette → corner card → end session. Session-owned fullscreen (a user's own
  fullscreen is never yanked).
- Review: 0 Critical / 3 Important / 6 Minor → all 3 Important + 4 minors fixed (`ef108fc`).

**Phase 3 — layout** (`7c96e7c`, `4d06531`)
- **3.1** Dashboard restructured to the locked mockup: tiny mono greeting/date title bar (serif
  header gone); live 12h clock block (clay colons, muted seconds, mono dateline, per-second tick
  contained to the clock subtree); "TODAY'S FOCUS" = next 8 open tasks by deadline (dated before
  undated, `scheduledAt` tiebreak, not day-scoped); plain recent-note rows → corner card; right
  rail = outlined mini-month **date navigator** (today = solid clay, selected = outline,
  "← TODAY", month paging) + selected-day agenda (events + work blocks, NOW clay wash,
  "FULL VIEW ›"). Removed: ScheduleCard, FocusCard, GoalsCard, MetricsCard (deleted; Metrics
  lives in Settings→Metrics + ⌘K).
- **3.2** Month grid + idle focus ring in the same instrument-container language; 8 uniform
  mono+hairline project-detail headers; palette keycaps fixed (hairline chips); Settings groups
  → hairline idiom (dead invisible fills gone).
- Review: 0 Critical / 0 Important / 6 Minor — all product-call or accepted notes (below).

## 2. Multi-tab Docs write-back — research only (NO code changed)

Full memo: `docs/archive/specs/2026-07-06-multitab-writeback-research.md`. Short version:
- Today both paths are tab-blind: pull = Markdown export (all tabs flatten to `# H1` sections —
  your live test confirmed all tabs DO export); write-back re-uploads whole-doc Markdown and
  lets Drive reconvert, which is what mangles the tab tree (your tab→sub-tab observation).
  Markdown⇄tabs has **no documented mapping** — option D ("make Markdown round-trip tabs") is
  impossible.
- Decisive finding: the app already holds the full Docs scope (`GoogleAuthService.swift:26`),
  so tab detection (`documents.get?includeTabsContent=true`) and **per-tab writes**
  (`batchUpdate` with `tabId`) need no new scope and no re-consent.
- **Option A — detect tabs + block write-back with a clear warning.** Low effort, zero data
  risk. Recommended NOW to stop the damage.
- **Option B — write only tab 1 via the Docs API.** Medium effort; confusing half-product; skip.
- **Option C — full per-tab two-way via the Docs API** (split note by H1 → write each tab).
  High effort; the real fix; the orphaned `GoogleDocsService.swift` path is the natural home.
- Recommendation: **A now, C later.** Your call — nothing was changed this run.

## 3. Decisions for Drew

- **D1** Dashboard check-off now only marks done (row leaves the focus list) — the old dashboard
  *deleted* the task 2s after checking. Keep non-destructive? (I'd keep it.)
- **D2** Focus list includes OVERDUE tasks at the top (spec said "upcoming"; implementer read it
  as ordering, not future-only). Keep overdue visible? (I'd keep it.)
- **D3** "FULL VIEW ›" opens the calendar on today, not the navigated day (spec-compliant).
  Want the selection carried?
- **D4** Native notes hide B/I/U now (plain-text storage eats marks). Want rich native notes
  later? That's a storage migration (Markdown + one-time escape) — a real mini-project.
- **D5** "Sync now" re-reads what the cron already landed (the `google-sync` fn is
  service-role-only, global tick — `index.ts:918-922`). True on-demand Drive pull = small edge-fn
  change + deploy. Want it?
- **D6** Multi-tab write-back: pick option A / C / do-nothing (§2).
- **D7** Reference-row sync chip lost its little status dot (state now carried by tag color
  alone) — fine, or restore the dot?
- **D8** Screen titles are now New York serif **semibold** (mockup said "chunky") — if too
  light, it's a one-line weight bump.

## 4. Manual test list (visual/behavioral — build can't prove these)

Full detail lives in the three review files' visual sections (scratch), consolidated here.

**A. Skin (Phase 1)**
1. Paper `#f2efe6` everywhere; no card fills or in-window shadows; hairlines don't read heavy on
   calendar grids.
2. Clay accent legibility on paper: nav tick, today square, done squares, NOW row; overdue red /
   warning amber still read.
3. Sidebar: active = 2px clay left tick + bold ink; hover = faint ink wash (visible enough?);
   tick alignment across nav/space/project/profile rows.
4. Tags are uppercase mono on soft washes ("CLASS", "GOOGLE DOC", "ASSIGNED") — confirm intended.
5. Type roles: numbers/dates/times mono everywhere; serif only on content titles (weight OK? D8);
   body still rounded sans. Focus countdown digits (96pt SF Mono ultralight) render cleanly.
6. Metrics donuts: ink-12% "remaining" arc weight on the small card vs the page.
7. Calendar filter chips: hidden state = dim + strikethrough (outline removed) — still obvious?
8. Overlays (⌘K palette, ⌘⇧K capture, note corner card) still float convincingly (shadows kept);
   palette `esc`/`⌘K` keycaps read as bordered chips.

**B. Features (Phase 2)**
9. Task → LINKED NOTE: link, open (corner card, not a sheet), edit, re-link, unlink; relaunch —
   link survived.
10. Reference row: body click → Atlas editor; small "Doc ↗" → browser.
11. Doc-note freshness: edit the Doc in Google → open note updates within ~30s + cron tick,
    no navigation needed; "Last synced" ticks by itself (never "in 3 sec ago"); dirty buffer
    shows the "newer version" banner, Reload adopts Google's, Done still offers Overwrite/Keep.
12. Sync now spins and refreshes (remember D5's limitation).
13. Underline in a DOC note: apply → Done → reopen → still there → check the Google Doc renders
    underline after the next writeback+pull cycle.
14. Native note: style bar shows no B/I/U (honest UI).
15. Settings: Google shows Reconnect when connected; a denied consent shows the humanized banner.
16. Focus: enter from sidebar AND dashboard; true fullscreen; corner timer works; Esc order
    (palette → card → session); green-button/⌃⌘F exit ends session cleanly; traffic lights +
    title bar intact after; if the app was ALREADY fullscreen before the session, ending doesn't
    yank you out.
17. Menu bar: MM:SS ticks every second while a session runs (TOP RISK — macOS 14 label refresh),
    controls work while Atlas isn't frontmost, label reverts on end.
18. ⌘K in Focus: notes-only + create; outside Focus unchanged. Sticky note: new note with no
    project saves and persists.
19. Fresh-account seed (needs a throwaway account): all spaces/projects/tasks/events/notes/goals
    appear with correct FIELD VALUES (due dates, scheduled times, project code/instructor) — this
    validates the batched seed (was finding I-1).
20. Collab: shared projects still show members; teammate edits still land live.
21. Cold launch feels faster with several projects (bootstrap now parallel; members 1 fetch).

**C. Dashboard & layout (Phase 3)**
22. Title bar: "GOOD AFTERNOON" left / "MON — JUL 6, 2026" right, tiny mono; no serif greeting.
23. Clock: seconds tick, clay colons, muted seconds, small AM/PM, 12h no leading zero; dateline
    "MONDAY —— JUL 6 / 2026"; hairline below.
24. Focus list: correct deadline order (overdue at top — D2), wash tags, mono due labels;
    checking animates out without deleting (D1); "+ Add a task" plain text link → capture.
25. Recent notes: plain rows, serif titles, GOOGLE DOC tag only on linked notes; click → corner
    card with dashboard visible behind.
26. Mini-month: the ONLY outlined box on the dashboard; chevrons page months without moving
    selection; today solid clay / selected outlined; dots on active days (legible on the clay
    square); "← TODAY" appears only off-today and resets.
27. Agenda follows the selected day (label "TODAY" vs "THU, JUL 9"); NOW wash only on today's
    in-progress event; "FULL VIEW ›" → calendar (lands on today — D3); deadline-only days show a
    dot but "Nothing scheduled."
28. Proportions: rail fixed ~348pt, main column flexes, nothing clips at narrow widths.
29. Calendar screen: outlined month container reads well full-size; corner cells clip cleanly.
30. Project detail: 8 hairlined headers read calm, not cluttered.
31. Focus screen idle: outlined panel around the ring looks like one instrument family with the
    corner capsule.
32. Settings: groups read via hairlines (no invisible boxes); shortcut-recording accent box
    still shows; Canvas feed input still reads as a field.

## 5. Known left-behinds (intentional, small)

- `AppState.todaysEvents` orphaned (old ScheduleCard's helper) and a stale `MetricsCard` comment
  in MetricsView — flagged, not removed (outside task scopes).
- `AtlasDB.loadProjectMembers(projectId:)` is now unused (superseded by the batched fetch) —
  left as pre-existing API.
- Pre-existing unused-`withAnimation` warning at the old `scheduleRemoval` site (now removed
  with the dashboard rewrite — verify it's gone on next build).
- Dashboard `dayHasItems` recomputes per cell each minute (O(42·N) per tick) — fine at current
  scale; memoize if it ever matters.
- `selectedDay` doesn't auto-rollover at midnight (an always-open window shows "← TODAY" for
  yesterday until clicked).
- Phase-2 Wave 4 gated ideas (auto-hide sidebar, dual editors, global calendar popup) remain
  unbuilt, as instructed.
