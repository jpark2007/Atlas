# Mobile Polish v2 — Freshness, Feel, Color, Capture

**Date:** 2026-07-02 · **Branch:** feat/mobile-phase1 · **Status:** awaiting Drew's review
**Source:** Drew's first TestFlight pass. These are concept-level fixes, not one-offs — each
defines a system the app follows everywhere.

## Decisions made (conversation, 2026-07-02)

1. **Freshness:** client-side only for now (pull-to-refresh + refresh on foreground).
   Server-side Google sync stays a separate project (see notes-gmail-monetization-decision).
2. **Color:** space colors carry meaning everywhere; clay stays reserved for live/NOW/brand.
3. **Motion:** "satisfying but quiet" vocabulary app-wide — except Capture, which is the
   hero moment and gets expressive animation.
4. **OPEN — capture visual direction:** recommendation is Direction A ("the page is the
   input") with the hero-orb thinking moment; Drew hasn't picked yet.

---

## 1. Data freshness — "the phone never shows a stale world"

**Today:** `MobileStore.refresh()` runs once at bootstrap/sign-in and never again. No
pull-to-refresh; foregrounding only re-plans notifications, never re-fetches.

**Design:**
- `.refreshable` on the Tasks and Schedule screens → `await store.refresh()`.
- On `scenePhase → .active`, call `store.refresh()` (alongside the existing `reschedule()`).
  The existing guards already make this safe: `mutationsInFlight` defers a snapshot replace
  during optimistic writes, and `onChange(of: store.loading)` already re-plans notifications
  + rewrites the widget snapshot after every refresh — so freshness automatically freshens
  notifications and widgets too.
- No timer polling in v1. Launch + foreground + pull covers the real usage pattern.

**Known limit (accepted):** events created in Google land in Supabase only while the Mac app
is running. That gap is the server-sync project, explicitly out of scope here.

## 2. Truthful sources — fix the "Not connected" lie

**Bug found:** `EventRow.toDomain()` (AtlasCore/AtlasDB.swift) never sets `source`, so every
event loaded from Supabase is stamped `.atlas` — even rows carrying a `googleEventId`.
Settings' derived `googleConnected` checks `source == .google`, which is therefore always
false: the row reads "Not connected" forever. This violates the project's data-correctness
rule (a source label must reflect where the event actually came from).

**Design:**
- Derive source at ingest: in `toDomain()`, `source = googleEventId != nil ? .google : .atlas`.
  (AtlasCore is shared — verify the Mac app's load path benefits rather than regresses; the
  Mac re-stamps sources during its own Google sync, so this should only correct labels.)
- Settings copy tells the truth for a device that never itself connects to Google:
  value becomes **"Syncs via your Mac"** when Google events are present, "Not syncing" when
  none are. No fake "Connected/Not connected" binary.

## 3. Capture intelligence — stated times are sacred

**Bugs found (supabase/functions/capture/index.ts):**
- The prompt gives the model "now" in UTC and demands UTC output, but never tells it the
  user's timezone — "5:30" cannot be converted correctly.
- The schema example for `dueISO` is a midnight timestamp (`…T00:00:00Z`), teaching the
  model to return date-only deadlines. "Hard deadline at 5:30" → "due today", time lost.
- No rule forces time preservation. "Pick someone up at 5:30" → task with no deadline.
- Display side: `TaskItem.dueLabel(for:)` renders only "Today"/"Tomorrow"/"Thu"/"MMM d" —
  never a clock time. Times are dropped at both ends.

**Design:**
- Client sends `timezone` (IANA identifier, e.g. `America/Los_Angeles`) in the capture
  request body. Field is optional → old clients/deploys keep working.
- Edge function prompt: states "now" in the user's local time AND timezone; examples carry
  real clock times; new hard rules — *if the user states a clock time it MUST appear in
  dueISO/startISO; never return a date-only deadline when a time was given; a time-bound
  errand ("pick X up at 5:30") is an event at that time.*
- Relative dates ("next Friday", "tomorrow", "tonight") resolve against the user's LOCAL
  calendar day, not UTC — late-evening captures currently compute these from the wrong day.
  Applies identically to typed and spoken capture: both routes share the same `sortItOut`
  flow and edge function, so this is one fix.
- `dueLabel` gains the time when one is meaningful: "Today 5:30 PM" (suppress for
  midnight/start-of-day dates, which mean date-only). Applies wherever the label renders.
- Model stays gpt-4o-mini for now; upgrade is a follow-up lever if accuracy is still poor
  after the prompt fix.

## 4. Color system — color always means the space

The theme stays Editorial Minimal light; clay remains rationed to live/NOW/brand. New rule:
**when color appears on content, it is the item's space color** — informative, never
decorative. Surfaces to adopt it:

- Task rows: checkbox ring tinted per space; fills with the space color on completion.
- Space filter chips (Schedule + Tasks): selected chip shows its space color.
- Capture result cards: a space-color tab/edge per draft, so routing is visible at a glance.
- Needs-time section items and the manual-add space picker.
- Calendar event dots already do this — unchanged, now consistent with everything else.

`spaceColor`/`space.color` already exist in the models; no data changes.

## 5. Motion & feel — one vocabulary, defined in the theme

Add to `MobileTheme`: one standard spring (fast response, well-damped — "satisfying but
quiet") plus a slightly livelier hero spring used only by Capture; and a haptic map —
light impact on check-off, success notification on capture commit, selection tick on
toggles/filters. Views never invent their own curves or haptics.

**Check-off (the flagship interaction):** checkbox ring fills with the space color, the
checkmark draws in, the title strikes through, light haptic — the row lingers a beat, then
slides out gracefully. Same vocabulary for list insertions (new capture results appearing
in Tasks) and sheet confirmations.

## 6. Capture redesign — the hero moment (OPEN: direction)

Capture is the app's signature: dump your brain, watch it get sorted. It earns the accent
and real animation. Three directions considered:

- **A. "The page is the input" (recommended):** kill the floating 200-pt outlined box; the
  whole screen becomes the writing surface — cursor ready, big placeholder, mic prominent at
  the bottom. Thinking state: the clay dot becomes a breathing/morphing orb (the one big
  accent moment in the app) while the captured words visibly dissolve into it. Results
  materialize one-by-one with staggered springs and space-color tabs; commit fires the
  success haptic + a summary line ("Added 3 · 2 School, 1 Personal"). Keeps the editorial
  identity; fixes the "empty page with a box" look.
- **B. "The stage":** capture as an immersive dark modal moment (glow, waveform) distinct
  from the light app. Maximum drama, but forks the design language and costs more.
- **C. "Live preview":** split screen, drafts streaming in as you type/speak. Most
  informative, but needs a streaming edge function — infrastructure this pass shouldn't take on.

Recommendation: **A**, borrowing B's energy for the thinking orb only.

## 7. Navigation — jump to today

`ScheduleView` already has a snap-to-today mechanism (`scheduleFocusToday`, used by deep
links). Add the visible affordance: a small "Today" pill that appears whenever the visible
day ≠ today, tap = snap back + light haptic. Same behavior on the month page.

## Out of scope (explicitly)

- Server-side Google Calendar sync (Supabase cron/edge) — separate project, already spec'd
  in the monetization doc.
- APNs remote push — local notifications suffice once data refreshes; revisit after server sync.
- Any Mac-app UI changes.

## Verification

- Build: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile` (sim destination) green.
- Edge function: unit-test the prompt builder; manual curl for "deadline at 5:30" /
  "pick someone up at 5:30" in a non-UTC timezone returns correct local-time ISO values.
- `EventRow.toDomain()` source derivation: unit test (googleEventId ↔ source).
- Feel/visuals (check-off, capture, colors, pull-to-refresh) are **not provable by a green
  build** — Drew confirms on device via TestFlight.
