# Step 0 — Visual pass, then ship (2026-09-02)

Everything on `main` since the released builds (iOS 1.1 (6), Mac 0.11.0) is unverified by eyes.
Builds are green; that proves nothing about how it looks or feels. Walk this list, tick boxes,
note anything off. When the list is clean, the ship steps at the bottom run.

**Run the Debug Mac app** (not the /Applications 0.11.0):
```
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
open build/Build/Products/Debug/Atlas.app
```
If `build/` path differs, run `xcodebuild ... -showBuildSettings | grep BUILT_PRODUCTS_DIR`.
iOS: run `AtlasMobile` scheme to your phone from Xcode (device, not simulator).

Legend: **Expect** = what correct looks like. **Bug if** = what to write down.

---

## A. Window chrome (Mac)

- [ ] Open a class, edit the Overview text, save.
  **Expect:** title bar stays dark/transparent edge to edge, traffic lights present.
  **Bug if:** a white or light band appears under the title bar, even briefly.
- [ ] Resize the window, toggle sidebar, switch spaces.
  **Expect:** same. **Bug if:** band returns on any of these.

## B. Sidebar (Mac)

- [ ] Right-click a class → **Change color…**
  **Expect:** popover with the color grid; picking one recolors the dot and calendar blocks.
- [ ] "Canvas feed stopped syncing" prompt above the class list.
  **Expect:** NOT visible if your Canvas feed synced in the last 24h. Only appears when the feed
  is revoked/errored or stale. If you see it while the feed is healthy → bug. Clicking it must
  open Settings → Calendars.

## C. Class page (Mac) — use Calc I or Gen Chem, not Psych

- [ ] **Term timeline folds.** Items grouped Overdue / This week / next weeks / months. Months
  past this week start collapsed. Events (exams) sit inside the folds next to tasks.
  **Bug if:** everything is expanded, or events are in a separate list.
- [ ] **Grading** and **Policies** are two separate cards.
- [ ] Grading weights add to 100% (or show a plain total). **Bug if:** 200% or a "TOTAL" row.
- [ ] Click the class-info card → sheet has ruled sections, chip-style weight rows, numbered
  policies. Edit a weight, save, reopen. **Bug if:** bare textbox, or edit didn't stick.
- [ ] "Scan a syllabus or schedule" button is visible even though class info already exists.
- [ ] Meetings card shows the pattern (Calc I is still the wrong Mon/Wed — known, ignore).
- [ ] Click the 14px color dot left of the class name → color popover.

## D. Scan sheet (Mac) — Calc I or Chem PDF, or paste text

- [ ] Two tabs: **PDF** and **Paste**.
- [ ] Wizard step tabs across the top; step box doesn't jump size between steps.
- [ ] Items grouped by month cards.
- [ ] Duplicate chips read one of: **Already in Canvas** / **Already from earlier scan** /
  **Already in class** — matching where the existing item actually came from. Matched rows are
  unchecked by default. **Bug if:** "Already in Canvas" on a non-Canvas item.
- [ ] Date-range items show an **approximate** chip.
- [ ] Rescan on a class that already has info: **Keep / Replace** rows per card, default Keep.
  Meetings card has a toggle. Flip it, commit, check the class page reflects your choice.
- [ ] Scan a long PDF (>20 pages if you have one): banner "N PAGES · M NOT READ".
- [ ] Amber warning if you switch to the other tab with content in the first.
- [ ] Dates on committed items are all-day (no "12 AM · 1h"). **Bug if:** any midnight time.
- [ ] Date pickers are dark (AtlasDateField), not white system pickers.

## E. Task detail + Unscheduled tray (Mac)

- [ ] Open any Canvas task. If Canvas moved its due date since import you get an amber
  **Due date moved** chip; dismiss clears it. Most likely NOT visible tonight — that's fine,
  only a bug if you see it on a task whose date never moved.
- [ ] Tray rows: long titles wrap at word boundaries. **Bug if:** mid-word breaks.
- [ ] Tray row shows a small marker for due-moved tasks (same caveat).

## F. Dashboard + week rail (Mac)

- [ ] Due-today items carry a class chip.
- [ ] Week rail: overdue pinned at the top; due-tonight pills sit at the bottom of the day column
  and same-time dues merge into one pill. **Bug if:** pills float mid-column or overlap.

## G. Calendar (Mac)

- [ ] **Month view with many Canvas assignments** (user report ssarkar, 0.11.0: right-side list
  of Canvas assignments, then the whole window froze, had to quit). Click Month on a space with
  all your classes' Canvas tasks. Scroll, click a day, open a task, switch back to Week.
  **Expect:** responsive throughout. **Bug if:** any beachball or a non-scrolling right list.
  This must be clean before 0.12.0 ships, because that user gets the update automatically.

Jonah's repeating events:

- [ ] New event → **Repeat** picker (daily/weekly/… until date).
- [ ] Create "yoga every Tue until Dec 12"; every Tuesday shows a block with a series badge.
- [ ] Edit one occurrence → dialog: **This event / This and following / All events**. Try each.
- [ ] Delete with scope; then Undo. **Expect:** series comes back intact.
- [ ] Drag one occurrence to another day → only that one moves (unless you chose "all").
- [ ] Quit and relaunch: series still there (persistence of series_id).

## H. iOS (device)

- [ ] Class hub → tap a class → two-column read-only detail sheet, no scroll needed, **Edit**
  button opens the editor.
- [ ] Class-info sheet matches the Mac redesign (sections, chips).
- [ ] Scan sheet: same chip wording rules as D. Commit → dates all-day.
- [ ] Item detail sheet: due-moved chip (same caveat as E).
- [ ] Schedule: repeat picker + scope dialog if Jonah built them on iOS; if absent, note it.
- [ ] Day and month views: all-day items sit in the all-day row, not at midnight.
- [ ] Widget still updates after a change (WidgetSnapshotWriter touched).

## I. Sync sanity (both)

- [ ] Add a task on iPhone → appears on Mac within ~5 min without relaunch.
- [ ] Add an event on Mac with a Google-linked space → shows in Google Calendar.
- [ ] Open an event detail on Mac, close it, wait 5 min → Mac still refreshes (Jonah's fix).

---

## Ship (only when the list above is clean)

1. **Bump versions in `project.yml`.** AtlasMobile target: `MARKETING_VERSION` 1.1 → **1.2**,
   `CURRENT_PROJECT_VERSION` 6 → **7**. Mac target: `MARKETING_VERSION` 0.11.0 → **0.12.0**.
   Then `xcodegen generate`. Commit.
2. **iOS:** Xcode → Product → Archive → Distribute → App Store Connect → TestFlight. Install
   on phone + iPad from TestFlight, 10-minute smoke (list H). Submit for review in ASC.
   iPad screenshots are required; reuse 1.1's if nothing changed visually.
3. **Mac:** `scripts/release-dmg.sh` (archive, sign, notarize, Sparkle-sign, appcast). Copy the
   versioned DMG into `landing/downloads/`. Landing deploy: coordinate with the other session —
   `landing/` has uncommitted work; deploy only what's committed.
4. **After BOTH are live:** `supabase functions deploy capture` (v22). Delete the PENDING
   DEPLOY block at the top of `CLAUDE.md` (its item 2 is already stale). Commit.
5. Tell Jonah: builds out, capture deployed, migrations 0046–0048 taken, task↔class link is ours.

What to send me: the ticked list, plus one line per bug (screen, what you saw, what you
expected). Screenshots help for chrome and layout items.
