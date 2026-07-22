# Atlas Onboarding — Manual QA Checklist

Generated 2026-07-22 (Task 9 final integration pass). Covers TipKit tips, `.help()`
tooltips, the Global Capture Key, capture event parsing, and the iOS getting-started
flow (checklist + calendar spotlight).

**Run on a device, not the simulator** (per Drew's testing rule).

**To sweep every Mac/iOS tip in one pass:** in
`AtlasCore/Sources/AtlasCore/AtlasTips.swift` → `configureOnce()`, uncomment the
`// Tips.showAllTipsForTesting()` line (Debug-only, force-shows all tips ignoring
rules), run a Debug build, then **re-comment it** and do a clean run to confirm the
real rule/session-count timing. Never commit with it enabled.

---

## Mac tips (10)

Deviation notes: tip #6 anchors on the **sidebar logo** (not a menu item); tips
#1/#7/#8/#9/#10 and the per-calendar #4 are **Mac-only**; #2/#3/#5 appear on both
platforms.

- [ ] **#1 Command palette** — ⌘K tip appears on the sidebar search after ≥2 app opens; retires after using search.
- [ ] **#2 Drag-to-schedule** — appears on the unscheduled-task tray when ≥1 task needs a time; retires after a drag-drop schedule.
- [ ] **#3 Connect a source** — appears in Integrations after ≥3 app opens with nothing connected; retires after connecting Google or Canvas.
- [ ] **#4 Per-calendar picker** — appears inside the auto-opened connection sheet on first connect; retires on dismiss.
- [ ] **#5 Report a Bug** — appears on the sidebar after ≥4 app opens (beta builds only); retires after reporting a bug.
- [ ] **#6 Global capture** — appears anchored on the **sidebar logo** after ≥3 app opens; retires after pressing the global capture key (⌘⇧K).
- [ ] **#7 Doc tabs** — appears the first time you open a note that has more than one tab.
- [ ] **#8 Drive sync** — appears on the first note inside a Drive-linked project (Google connected).
- [ ] **#9 Frozen islands** — appears the first time a shaded read-only island block is visible; retires once seen.
- [ ] **#10 Invite people** — appears on a solo space page (you are the only member); retires after sending an invite.
- [ ] Only **one tip shows at a time**; each stays dismissed across relaunch.

## Mac `.help()` tooltips

- [ ] Hover every icon-only button (toolbar, sidebar, sheets) → each shows a correct one-line tooltip, no missing/placeholder text.

## Mac Global Capture Key

- [ ] **New account** → first-run capture popup shows exactly once; record / keep / skip / "try it now" all work; popup never reappears after any of them.
- [ ] **Existing account** → popup never appears (DEBUG log shows a real `created_at`).
- [ ] Settings → SHORTCUTS no longer says "deferred (v2)".
- [ ] Rebinding **Quick Capture** updates BOTH the in-app shortcut and the global hotkey (single sync point across both UserDefaults encodings).
- [ ] The global hotkey fires while another app is frontmost.
- [ ] Best-effort conflict handling: a taken combo is handled gracefully (Carbon registration failure + system shortcut table) rather than silently dead.

## Mac capture — event parsing

- [ ] Press ⌘⇧K, **paste a multi-event schedule email** (several dated items) → capture parses each into a separate event, not one blob.

## iOS tips (3)

Deviation note: iOS ships **only** tips #2, #3, #5 — no search/notes/tabs/islands/invite tips on iOS.

- [ ] **#2 Tap-to-place** — appears on the calendar with an unscheduled task; retires after placing a task on the day (copy reads "tap … then place it on the day").
- [ ] **#3 Canvas connect** — appears after ≥3 app opens with nothing connected; retires after connecting.
- [ ] **#5 Report a Bug** — appears after ≥4 app opens (beta only); retires after reporting.

## iOS capture — event parsing

- [ ] In iOS capture, **paste a multi-event schedule email** → each event is parsed out separately (matches Mac ⌘⇧K behavior).

## iOS getting-started checklist

- [ ] Card starts at 0/4 on the Schedule home; items auto-tick as you: **connect** a source, **capture** something, **schedule** an item, **peek at month view** (the old "open a note" item is now **month view**).
- [ ] Card disappears at 4/4.
- [ ] ✕ dismisses the card early and it stays dismissed across relaunch.
- [ ] Widget row **soft-ticks** as a bonus after adding the Atlas widget.

## iOS calendar spotlight (2 steps)

- [ ] First visit to Schedule → spotlight **step 1** highlights the **ScheduleView toggle**; **step 2** highlights the **calendar/month glyph**; ends on month view.
- [ ] Dim + cutout renders correctly around each anchor.
- [ ] **Skip** exits immediately.
- [ ] Spotlight never shows again after the first run (persists across relaunch).
