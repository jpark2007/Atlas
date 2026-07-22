# Onboarding & Tips — discussion doc (2026-07-21)

Status: **SUPERSEDED 2026-07-21** by `2026-07-21-onboarding-tips-design.md` (approved
design — read that one). Kept for the landscape research. Original context: Drew asked
for this doc to continue the conversation in a fresh chat. Context: "tooltips/onboarding
tutorial = later" was parked on 07-16; Drew is now exploring it for both apps.

## What Drew asked for
A way to show new users what buttons do and teach the invisible features — he floated
a "force them to do it" tutorial. Question raised: how does teaching differ between
Mac (hover exists) and iPhone (no hover)?

## Landscape (what apps traditionally use)
1. **Spotlight/coach-mark tours** — dim screen, highlight one control, Next/Next/Done.
   Web libs: Intro.js, Shepherd, Driver.js, Joyride; SaaS: Appcues/Pendo. The "forced"
   variant only advances when the user performs the action. Consensus: tests poorly —
   users skip, forget by step 3, resent being blocked.
2. **Contextual tips** — small popovers that appear the first time a feature is
   relevant. Apple-native framework: **TipKit** (macOS 14+ / iOS 17+ — matches our
   deployment targets; used by Apple in Photos/Safari).
3. **Getting-started checklist** — persistent "3 of 5 done" card (Notion/Linear style).
4. **Welcome carousel** — cheap, low retention, everyone mashes through.
5. **Seeded content as teacher** — Atlas already has the strongest version of this:
   server-seeded School/Personal starter spaces (migration 0024).

## Recommended direction (Claude's call, Drew leaning yes — confirm in next chat)
**No forced tour.** Two layers instead:

### Layer 1 — Mac only: hover tooltips everywhere
SwiftUI `.help("…")` on every icon-only button → classic native gray tooltip after
~1s hover. One line per button, zero state management, no "don't show again" needed
(only appears on hover), Mac users expect it. Do a full sweep of icon buttons.
iPhone has no hover → this layer doesn't exist there; ambiguous icons get clearer
labels/empty states instead.

### Layer 2 — both platforms: TipKit for invisible features
- A tip = small Swift struct (title, message, SF Symbol, optional action buttons).
  Attach with `.popoverTip(tip)` (floating bubble w/ arrow at the control) or
  `TipView(tip)` inline (card in the layout, can have a "Try it" button running real
  code, e.g. actually opening ⌘K).
- **Trigger = the anchored view APPEARING on screen while rules pass — NOT click or
  hover.** This is how it reaches users who'd never find the button: tip shows even
  if they never interact with it.
- **Rules engine**: eligibility like "after 2 app opens", "never used ⌘K" — you
  donate events (`SearchUsedEvent.donate()`) and write `#Rule` predicates.
- **Dismissal handled free**: ✕ = permanently dismissed (persists across launches);
  `invalidate(reason: .actionPerformed)` retires a tip the moment the user does the
  thing themselves; can cap max display count; one-tip-at-a-time option so the app
  never becomes a tooltip minefield.
- Tip structs can live in AtlasCore and be shared; only anchor view + copy fork per
  platform ("Press ⌘K" vs "Tap search") — one-line platform check.
- If Drew still wants ONE "do it now" beat: a single inline tip with a "Try it"
  button (opens ⌘K for real). Forced-tutorial feel without blocking. A true
  spotlight overlay (dim + cutout + advance-on-real-click) would be custom SwiftUI —
  possible but custom work; keep to 1–2 steps max if ever.

## Draft tip list (starting point — refine in next chat)
| Tip | Anchor (Mac) | Anchor (iOS) | Suggested rule |
|---|---|---|---|
| ⌘K / search everything | toolbar search button | search affordance | 2nd app open, never used search |
| Drag-to-schedule | calendar day grid | day grid | first visit to calendar w/ ≥1 unscheduled task |
| Connect Google/Canvas | Settings connections | Settings | 3rd open, no connection yet |
| Per-calendar checkboxes | connection detail sheet | same | on first connect (sheet already auto-opens) |
| Report a Bug | sidebar row | Settings row | once, during beta, after a few sessions |
| Invite people | invite button | (Mac-first; social = Jonah's lane) | space page, solo user |

## Open questions for the next chat
1. Confirm: no forced tour? Or keep one "Try it" inline beat?
2. Final tip list + exact copy + rules per tip.
3. Does mobile need a getting-started checklist too, or is seeded content + tips enough?
4. Who does the Mac `.help()` sweep and where's the button inventory (agents can grep)?
5. Sequencing vs App Store v1: ship tips before iOS v1 submission, or v1.1?
   (TipKit is additive/low-risk, but every change delays archive → TestFlight.)

## Implementation notes (when built — by Opus/Sonnet subagents per Drew's rule)
- macOS 14 / iOS 17 minimum: satisfied by current deployment targets.
- `Tips.configure()` once at app launch; `Tips.showAllTipsForTesting()` for dev.
- Donate feature-usage events at the real call sites (⌘K open, drag commit, etc.).
- `.help()` strings: match Atlas's editorial voice, sentence case, no periods.
