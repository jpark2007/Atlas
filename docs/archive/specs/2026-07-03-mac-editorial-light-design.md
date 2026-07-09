# Mac Editorial Light — reskin design (2026-07-03)

Reskin the macOS app to the mobile design system: **Editorial Minimal · LIGHT · clay**
(`AtlasMobile/Theme/MobileTheme.swift` is the source of truth). Approved by Drew 2026-07-03;
sequenced *before* Docs→notes import so new import UI is built on the new skin once.
Jonah has not weighed in yet — this doubles as the concrete artifact for that pitch.
Reversal path: the skin is token- and modifier-layer only; old dark values live in git.

## Rules (from mobile, non-negotiable)

- Accent clay `#d97757` is for **graphics only** — NOW line, live dots, brand. Never a button fill.
- Text-on-light accent uses the AA-dark variant `#b04f2f`.
- Controls are transparent with 1.5 pt ink outlines. No filled buttons.
- **No card chrome.** Content sits on the cream bg; sections separate with black-8% hairlines.
- Type is SF Pro Rounded everywhere.
- One motion vocabulary: standard spring (response 0.35, damping 0.8); hero spring reserved for capture.

## Token remap (`AtlasCore/Sources/AtlasCore/Theme.swift`)

Names are **kept** (nothing breaks mid-flight); values remap dark → light:

| Token | Dark (old) | Light (new) |
|---|---|---|
| bgBase | #16130f | #fbfaf7 |
| bgDeep | #100e0c | #f3f1ec (recessed) |
| bgSidebar | #1a140f | #f7f5f0 |
| bgCard / bgElevated | #1c1814 / #211d18 | cream family tints (near-invisible) |
| border / borderStrong | white 6% / 10% | black 8% / 14% |
| textPrimary / Secondary / Muted | #f3ede4 / #a89b8a / #6f655a | #1a191d / #6c6a72 / #9a98a0 |
| accent / accentDeep | #ff8c42 / #ff6b1a | #d97757 / #b04f2f |

Added: `hairline` (black 8%), `accentText` (#b04f2f), rule width 1.5, continuous radii at Mac
scale (card ~18, control ~14, chip ~10). `AtlasTheme.Font.*` gains `design: .rounded`.
`AtlasCard` restyled centrally: no fill, no stroke — padding + hairline rule below.
Editorial modifiers ported from mobile (Mac-flavored, no haptics): `edScreenTitle`,
`edCapsLabel`, `edOutlineControl`, `edHairlineBelow`.

Space identity colors (school/personal/side) keep hue; nudge only if they fail contrast on cream.
Mobile impact: AtlasMobile reads only `danger` (9×) + `accent` (1×) from AtlasTheme — both safe;
mobile must still build green after the change.

## Mac adaptations

- Density stays Mac: 13 pt body, tight rows — not touch-sized.
- Hover states (subtle ink-opacity) replace haptics.
- Calendar event blocks copy mobile `DayTimelineView` treatment on light — do not invent a new one.
- Window chrome: light, traffic lights untouched (`.hiddenTitleBar` stays).

## What does NOT change

Layout, navigation, the custom drag system, data, sync, services. Skin only.

## Execution

Branch `feat/mac-editorial-light`. Phase A: token layer (1 agent). Phase B: 5 parallel
area agents over all `Atlas/` view files (shell+sidebar / calendar grid / detail+edit
sheets / dashboard+metrics+focus+graph / auth+capture+palette+notes). Phase C: integration
sweep for dark leftovers, both apps build green, best-effort screenshots.
Done = "applied, builds, awaiting Drew's visual pass" — never "works" (house rule).
Drew's vet gates the notes-import build.
