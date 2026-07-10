# Text size & weight — design

## Problem

Text across the Mac app is hardcoded per-view (`.font(.system(size: N, ...))`), inconsistent in scale, and generally too small. Secondary/muted grey text (`textSecondary`, `textMuted`) is too low-contrast and too light-weight to read comfortably. There is no way for the user to bump text size themselves.

## Scope

Mac app only (`Atlas/`). Mobile app and widgets are out of scope.

## Findings

- All 326 font declarations in `Atlas/Views` use the single-line shape `.font(.system(size: X[, weight: W][, design: D]))` — no semantic text styles (`.body`, `.title`, etc.), no multiline splits, no nested parens inside `.system(...)`. This makes a scripted, mechanical migration safe.
- A small shared helper file, `AtlasCore/Sources/AtlasCore/Theme.swift`, already defines the color/font tokens (`AtlasTheme.Colors`, `AtlasTheme.Font`, `atlasMono`, `atlasTitleSerif`, `atlasScreenTitle`, `atlasCapsLabel`) used across ~130 additional call sites. Routing everything through this one file gives a single choke point for scaling.
- `textSecondary` / `textMuted` colors are applied via `.foregroundStyle(...)` independently of font weight, so darkening color is a one-line change, but "boldness" requires touching call sites that pair one of these colors with an *implicit* `.regular` weight font call.

## Design

### 1. Global, user-adjustable text scale

- Add `EnvironmentValues.atlasTextScale: CGFloat` (default `1.0`) in `Theme.swift`.
- Add `@AppStorage("appearance.textScale")` at the app root (`RootView`/`AtlasApp`), injected into the environment via `.environment(\.atlasTextScale, textScale)`.
- Add `View.atlasFont(size:weight:design:)` in `Theme.swift`: reads `atlasTextScale` from the environment and returns `.font(.system(size: size * scale, weight: weight, design: design))`.
- Rewrite existing shared helpers (`atlasMono`, `atlasTitleSerif`, `atlasScreenTitle`, `atlasCapsLabel`, `AtlasTheme.Font.*`) to route through the same scale so all ~130 existing call sites pick it up for free.
- Add a "Text size" control to `SettingsView` (general section), bound to the same `@AppStorage` key, following the existing settings patterns in that file (segmented control, consistent with `AtlasSegmentedPicker` already used for sidebar mode etc.). Steps: Small (0.9x) / Default (1.0x) / Large (1.15x) / X-Large (1.3x).

### 2. Base size bump (~10%, independent of user setting)

- Increase the base point size argument at each of the 326 call sites by ~10% (rounded to the nearest sensible pt), e.g. 11→12, 13→14, 12→13, 14→15, 28→31.
- Applied as part of the same scripted migration in step 3 (bump the literal, then wrap in `atlasFont`).

### 3. Scripted migration of the 326 raw call sites

- Regex-replace `.font(.system(size: X[, weight: W][, design: D]))` → `.atlasFont(size: X'[, weight: W][, design: D])` across `Atlas/Views`, where `X'` is the ~10%-bumped size.
- Build (`xcodebuild`) after the mechanical rewrite to confirm no syntax breakage before doing anything else.

### 4. Secondary/muted text — darker + bolder

- Darken `AtlasTheme.Colors.textSecondary` (`#6f6a5e`) and `textMuted` (`#9c968a`) hex values in `Theme.swift` — single edit, affects all current usages.
- Script-detect call sites where a font call with **no explicit weight** (implicit `.regular`) is chained (same statement/modifier chain) with `.foregroundStyle(AtlasTheme.Colors.textSecondary)` or `.textMuted` and bump those specifically to `.medium`. Leave any call site that already explicitly sets a weight (e.g. `.semibold`) untouched — that was a deliberate choice.

### 5. Verification

- `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` must pass.
- Since this is a visual/UI change, per the project's working agreement a green build does not prove correctness — the user must eyeball the running app (Settings, Calendar, Sidebar, at minimum) and confirm sizing/weight/contrast look right, and that the new text-size setting in Settings actually rescales the app live.

## Out of scope

- Mobile app (`AtlasMobile`) and widgets (`AtlasMobileWidgets`) — separate theme files, not touched.
- Full Dynamic Type / accessibility text-size system integration (macOS `NSApplication` text size prefs) — this is a custom in-app setting only, not tied to system accessibility settings.
