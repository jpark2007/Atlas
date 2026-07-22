# Onboarding & Tips — approved design (2026-07-21)

Status: **DESIGN APPROVED by Drew 2026-07-21.** Supersedes the discussion doc
(`2026-07-21-onboarding-tips-discussion.md`). Implementation plan to follow; all
building done by Opus subagents. **Everything here ships BEFORE the iOS App Store
v1 archive** (Drew's sequencing call).

## Shape (decided)

No forced tour on Mac. One deliberate exception on iOS (§5). Four pieces:

1. Mac hover tooltip sweep (`.help()`)
2. Shared TipKit tips, both platforms
3. Global Capture Key — first-run popup (new accounts) + permanent Settings rebind
4. iOS: getting-started checklist + a small skippable calendar-views spotlight

## 1. Mac `.help()` sweep

Every icon-only button in the Mac app gets SwiftUI `.help("…")` — native gray
tooltip after ~1s hover. Inventory built by grepping Mac views for icon-only
buttons. Copy: Atlas editorial voice, sentence case, no periods, one line each.
No state, no settings, no iOS equivalent (ambiguous iOS icons get clearer labels
or empty states instead, handled case-by-case, not part of this sweep).

## 2. TipKit tips (both platforms)

- Tip structs live in **AtlasCore**; anchor views + copy fork per platform with a
  one-line platform check ("Press ⌘K" vs "Tap search").
- **Trigger = anchored view appearing on screen while rules pass — never click or
  hover.** Reaches users who would never find the control.
- Event donations at the real call sites (⌘K open, drag commit, capture commit,
  connect success…). A tip retires itself via `invalidate(.actionPerformed)` the
  moment the user does the thing unprompted.
- ✕ = permanently dismissed (persists across launches). One tip displayed at a
  time. `Tips.configure()` once per app at launch; `Tips.showAllTipsForTesting()`
  in dev builds.
- **Existing users** (Drew, Jonah, beta testers) will see tips fire once after
  updating — accepted, doubles as visual QA.

### Final tip list

| # | Tip | Platforms | Rule |
|---|-----|-----------|------|
| 1 | ⌘K command palette / search | both | 2nd app open AND never used search |
| 2 | Drag-to-schedule | both | first calendar visit AND ≥1 unscheduled task |
| 3 | Connect Google/Canvas | both | 3rd open AND no connection |
| 4 | Per-calendar checkboxes | both | first connect (inside the auto-opened sheet) |
| 5 | Report a Bug | both | once, beta builds only, after a few sessions |
| 6 | Global capture reminder | Mac only | never captured after ~3 opens — "Press ⌘⇧K from any app" |
| 7 | Doc tabs basics | both | first time inside a note |
| 8 | Drive sync | both | first note in a Drive-linked project AND Google connected |
| 9 | Frozen islands | both | first time an island is visible |
| 10 | Invite people | Mac only | on a space page AND user is the only member |

Considered and cut: calendar list-scope tip (keep the list tight; revisit if
beta feedback asks).

## 3. Global Capture Key (Mac only)

The existing system-wide capture hotkey (`HotkeyService`, Carbon, default ⌘⇧K,
works from any app, type or click-to-talk dictation) gets a real surface:

- **First-run popup** — one sheet, shown once, **new accounts only** (existing
  users never see it): "Your Global Capture Key is ⌘⇧K — capture from any app,
  type or speak." Keep it, or press a new combo in a recorder field. Ends with a
  "Try it now" button that genuinely opens the capture overlay and points out the
  mic button. Skipping keeps the default; tip #6 catches non-users later.
- **Permanent Settings section** — the same recorder lives in Settings forever,
  so the key can be changed any time (the popup is a convenience, not the only
  door).
- **Conflict handling is best-effort by design**: check against Atlas's own
  shortcuts and well-known macOS system defaults; if Carbon registration fails,
  something else owns the combo — say so and prompt for another. There is no API
  to enumerate other apps' custom binds (e.g. Raycast); do not pretend otherwise.
- Recorder writes the UserDefaults keys `HotkeyService` reads AND keeps
  `ShortcutStore`'s Quick Capture binding in sync — the global and in-app binds
  must never drift.
- iOS: no global hotkeys on the platform; capture stays in-app, no equivalent.

## 4. iOS getting-started checklist

Dismissible "Get started" card on the iPhone home screen, "n of 4 done" style:

1. Connect Google or Canvas
2. Capture your first task
3. Put something on the calendar
4. Open a note
- Bonus (soft, NOT required for completion): Add the Atlas widget

Items auto-check via the same TipKit event donations — no separate tracking
layer. Card completes at 4/4 core items (widget is decorative extra credit) and
can be dismissed manually any time. Dismissal/completion persists.

## 5. iOS calendar-views spotlight (the one guided beat)

A short, **skippable** spotlight on first visit to the iOS calendar: dim +
cutout highlighting the view switcher, walking list → day → month. Max 2–3
steps, advances on real taps of the switcher, prominent skip, never shown again
after completion or skip. Custom SwiftUI (TipKit has no spotlight primitive) —
kept deliberately tiny; this is the ONLY spotlight anywhere. Mac gets none
(drag-to-schedule is tip #2, not a spotlight — Drew considered and passed).

## Out of scope

Spotlight anywhere else, welcome carousel, Mac getting-started checklist,
iOS global capture, Gmail/monetization anything, calendar list-scope tip.

## Constraints & notes

- macOS 14 / iOS 17 minimums — TipKit available on both; already satisfied.
- Ships before the iOS v1 App Store archive (this work gates the archive).
- UI behavior is not provable by a green build — Drew visually verifies tips,
  popup, checklist, and spotlight on device before anything is called done.
- All implementation by Opus subagents (Drew's standing rule).
