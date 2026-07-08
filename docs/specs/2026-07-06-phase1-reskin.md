# Phase 1 — Reskin & styling ("paper minimal")

**Date:** 2026-07-06 · **Status:** DRAFT, direction locked — runs FIRST when Drew's limits reset.
Skin source of truth: mockup artifact version `paper-minimal-v4-12h`. Master plan:
`2026-07-06-dashboard-focus-perf-plan.md`. Mac app only (ignore AtlasMobile). **Styling only — zero
layout moves** (layout is Phase 3).

Baseline reality (from the 2026-07-06 code inventory): color discipline is GOOD — 675
`AtlasTheme` color refs, zero hardcoded `Color(hex:)` in Views/App. Typography discipline is the
cost driver — 378 inline `.font(.system(...))` vs. 22 token + 34 semantic-helper uses. So: token
swaps get colors nearly for free; fonts need helpers first, then a sweep.

---

## The locked skin

- **Surfaces:** one paper `#f2efe6`, flat. No card fills, no elevated fills, no shadows inside the
  window. Separation = 1px hairlines at ink@12%.
- **Ink:** `#211d17` / `#6f6a5e` / `#9c968a`.
- **Accent:** clay `#d97757` (deep `#b04f2f`) — unchanged; reserved for live/NOW/today/done/active.
- **Type roles:** MONO = every number, date, time + uppercase section labels (wide tracking).
  SERIF (New York) = content titles (screen/project/space/note titles). Rounded sans = body,
  tasks, nav.
- **Controls:** square checkboxes (done = solid accent square). Tags = tiny mono uppercase on soft
  color wash — no outlines, no pills. Outlined containers reserved for **instruments** (calendar,
  timer, pickers). Clock is 12-hour everywhere it appears.

## Step 0 — prep helpers (do FIRST; shrinks everything after)

Add to `AtlasCore/Sources/AtlasCore/Theme.swift`:
- `atlasMono(size:weight:)` / `atlasNumeric()` — mono role for numbers/dates/times.
- `atlasTitleSerif(size:)` — serif role for content titles.
- `wash(_ color)` → `color.opacity(0.13)` token for tag/chip backgrounds.
- `atlasTag(text:color:)` — THE shared tag: tiny mono uppercase on wash, no stroke. (Today ~10
  views roll their own pills — see C.c.)
- `hairlineWidth = 1` alongside the existing `rule = 1.5` (controls keep 1.5; hairlines are 1).

## Step A — token values (1 file: `Theme.swift`)

| Token (line) | Current | New |
|---|---|---|
| `bgDeep` (:17) | `f3f1ec` | `f2efe6` |
| `bgBase` (:18) | `fbfaf7` | `f2efe6` |
| `bgSidebar` (:19) | `f7f5f0` | `f2efe6` |
| `bgCard` (:20) | `faf8f4` | `f2efe6` (fills die) |
| `bgElevated` (:21) | `f8f6f1` | `f2efe6` (fills die) |
| `border` (:23) | black@0.08 | ink(`211d17`)@0.12 |
| `borderStrong` (:24) | black@0.14 | ink@0.28 |
| `hairline` (:27) | black@0.08 | ink@0.12 |
| `textPrimary` (:30) | `1a191d` | `211d17` |
| `textSecondary` (:31) | `6c6a72` | `6f6a5e` |
| `textMuted` (:32) | `9a98a0` | `9c968a` |
| `accent/accentDeep/accentText` (:35–38) | — | unchanged |
| space colors (:45–49) | — | unchanged (identity); add wash variants via helper |

Radii stay as values (harmless once pills/cards flatten). `warning`/`danger` unchanged pending the
contrast check (D).

## Step B — re-point semantic helpers (1 file; ~16 files inherit)

- `atlasCapsLabel()` (:111) → **MONO**, wide tracking (~+0.2em). Highest leverage: fixes
  Sidebar/Dashboard/Metrics/TaskDetail section labels at once.
- `atlasScreenTitle()` (:103) → **SERIF**. (Only Dashboard uses it today; C adopts it elsewhere.)
- `atlasHairlineBelow()` (:132) + `AtlasCard` (:75–92) — already chromeless; inherit new hairline
  token automatically. No structural change.
- `atlasOutlineControl()` (:120) — keep as the instrument/control outline. Audit call sites so
  outlines stay instruments-only.

## Step C — per-view sweep (~20–30 of 45 files, in buckets)

1. **Checkboxes → squares, done = accent** (~6 files): Dashboard already square but done-color is
   space color (`DashboardView.swift:274-276`) → accent. Circles → squares in
   `TaskDetailView:48`, `SpaceDetailView:78`, `ProjectDetailView:645`, `UnscheduledTray:135`,
   `AttachReferencePicker:168`, `TimeGridView:244`.
2. **Tags/chips → shared `atlasTag`** (~10 files): replace bespoke pills in `ProjectDetailView:477`,
   `AllDayRowView:84,108`, `TimeGridView:407,422`, `MonthGridView:112`, `CalendarView:209`,
   `TaskDetailView:134,204`, `UnscheduledTray:128`, `ReferenceRowView:125`,
   `CalendarEventDetailView:99`, `NoteEditorView:128`.
3. **Content titles → serif** (~4 files): `ProjectDetailView:494,498`, `SpaceDetailView:46`,
   `NoteEditorView:88`, `NotesListView` titles (adopt `atlasScreenTitle`/`atlasTitleSerif`).
4. **Sidebar** (1 file): remove active/hover ink-fill tint (`SidebarView:131-135`, clips at
   :237,292,359) → 2px accent left tick + bold ink; DESIGN A HOVER STATE (risk D6);
   `background(bgSidebar)` (:107) inherits paper. `AtlasSegmentedPicker` (:27) shares the tint idiom.
5. **Calendar numbers → mono** (3 files): day numbers `MonthGridView:103`, `WeekColumnHeader:38`;
   hour labels `TimeGridView:54`; weekday headers `MonthGridView:57`, `WeekColumnHeader:33`.
   Today/now accents already on-brand — keep. Event tiles re-map fills to wash.
6. **Inline uppercase labels → helper** (~6 files): `MonthGridView:57`, `WeekColumnHeader:33`,
   `FocusView:38`, `MetricsView:133,208,223`, `MetricsCard:48`.
7. **The broad mono sweep**: numbers/dates/times inside the 378 inline `.font(.system)` sites —
   worst files `ProjectDetailView (52)`, `SettingsView (48)`, `TaskDetailView (28)`,
   `DashboardView (24)`, `SidebarView (21)`, `CalendarEventDetailView (18)`, `TimeGridView (16)`,
   `UnscheduledTray (13)`. Only re-font the numeric/date/label cases; body text stays sans.
8. **Clock format**: 12-hour wherever time-of-day renders (dashboard clock in Phase 3, but any
   existing `HH:mm` displays adopt 12h + meridiem now if user-facing).

## Step D — risks & verification checklist (agents must check, not assume)

1. Accent + `accentText` AA contrast on the darker paper (`f2efe6`) — nav tick, today square.
2. Hairline hue shift (black→ink) at 12% vs old 8% — calendar grids must not get heavy.
3. Surface collapse: `TimeGridView` event tiles used `bgElevated` (:38) — confirm legibility with
   wash mapping; sidebar loses its tint delta by design.
4. Metrics donuts: "remaining" arc uses `border` (`MetricsView:45,53`) — re-check after border
   re-base; space-color sectors keep hue.
5. Sidebar hover feedback must exist after the fill is removed (D6 above).
6. **Overlay shadows (5 sites)**: `CaptureOverlay:167-168`, `CommandPalette:131`,
   `NoteCardOverlay:43`, `TimeGridView:42` — DECISION (Drew): floating overlays exempt from
   "no shadows" (recommended) or hairline-outline substitute?
7. `danger`/`warning` contrast on paper (`TimeGridView:334`, `TaskDetailView:184`).
8. Apple Charts internals don't take font roles — only overlay text is ours (`MetricsView:58`).

## Execution plan

- **Wave 0 (one agent):** Step 0 + A + B in `Theme.swift` → build → screenshot pass with Drew.
  This alone reskins most color + all compliant labels.
- **Wave 1 (parallel agents, disjoint files):** buckets C1–C6 (checkboxes / tags / serif titles /
  sidebar / calendar mono / label adoptions).
- **Wave 2 (one careful agent per worst file):** the C7 mono sweep on the 8 heavy files, then the
  long tail.
- Verify per wave: build green + Drew visual pass (style is UI — a green build proves nothing about
  looks). Check D-list items in the wave that touches them.
