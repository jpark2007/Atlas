# Text Size & Weight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make text across the Mac app bigger and bolder/darker where it's currently too grey, and give the user a live-adjustable text-size setting.

**Architecture:** A single environment-driven scale (`atlasTextScale`, backed by `@AppStorage`) flows from the app root into one shared font helper (`View.atlasFont(size:weight:design:)`) in `AtlasCore/Theme.swift`. Every existing font call site — both the ~130 that already use shared helpers (`atlasMono`, `atlasTitleSerif`, etc.) and the ~343 that hardcode `.font(.system(size:...))` or `AtlasTheme.Font.*()` directly — is migrated to route through that one helper, so the scale (and any future global type-scale change) only needs to be edited in one place. The ~10% base-size bump and the secondary/muted-text weight bump are applied as part of that same migration, via two scripted, mechanical passes (verified by exact grep counts, not hand-editing 38 files).

**Tech Stack:** Swift, SwiftUI, `@AppStorage`, custom `EnvironmentKey`. Python 3 (already on this machine) for the two mechanical migration scripts — scripts live in the scratchpad only, never committed.

## Global Constraints

- Mac app only (`Atlas/`, `AtlasCore/`). Do not touch `AtlasMobile/`, `AtlasMobileWidgets/`, or their theme files.
- Every task must end with `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` passing before moving on.
- Per this project's working agreement, a green build does NOT prove a visual/UI change is correct — the final task requires the user to run the app and confirm sizing/weight/contrast and the live-rescaling setting.
- Follow existing code style: `AtlasTheme.Colors.*` tokens, `.rounded` design by default, existing settings-section pattern in `SettingsView.swift` (see `sidebarSection` for the template).
- Surgical changes only: don't refactor unrelated code. Remove the `AtlasTheme.Font` enum in Task 5 specifically because that task's migration is what orphans it — not a general cleanup.

---

### Task 1: Add the scale-aware font helper to `AtlasCore/Theme.swift`

**Files:**
- Modify: `AtlasCore/Sources/AtlasCore/Theme.swift`

**Interfaces:**
- Produces: `EnvironmentValues.atlasTextScale: CGFloat` (default `1.0`), `View.atlasFont(size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .rounded) -> some View`. Later tasks (2, 3, 5, 6) depend on both existing under these exact names.

- [ ] **Step 1: Add the environment key**

Add this near the top of `Theme.swift`, after the `import SwiftUI` line:

```swift
public struct AtlasTextScaleKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// Global user-adjustable text scale, set once at the app root from
    /// `@AppStorage("appearance.textScale")` (see `AtlasApp.swift`). Every
    /// font in the Mac app should render through `atlasFont` so it responds
    /// to this value — see that function for the single choke point.
    public var atlasTextScale: CGFloat {
        get { self[AtlasTextScaleKey.self] }
        set { self[AtlasTextScaleKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Add the `atlasFont` view modifier**

In the `extension View { ... }` block that already contains `atlasMono`, `atlasNumeric`, `atlasTitleSerif`, `atlasScreenTitle`, `atlasCapsLabel`, add:

```swift
    /// THE font entry point — every text style in the Mac app should render
    /// through this so it responds to the user's `atlasTextScale` setting.
    public func atlasFont(size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .rounded) -> some View {
        modifier(AtlasScaledFont(size: size, weight: weight, design: design))
    }
```

Directly above that `extension View { ... }` block, add the modifier it references:

```swift
private struct AtlasScaledFont: ViewModifier {
    @Environment(\.atlasTextScale) private var scale
    let size: CGFloat
    let weight: SwiftUI.Font.Weight
    let design: SwiftUI.Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}
```

- [ ] **Step 3: Route the existing shared helpers through `atlasFont`**

Replace the bodies of `atlasMono` and `atlasTitleSerif` (the two primitives the others build on) so they scale too:

```swift
    /// MONO type role (SF Mono) — every number, date, time, and uppercase section label.
    public func atlasMono(size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> some View {
        self.atlasFont(size: size, weight: weight, design: .monospaced)
    }
```

```swift
    /// SERIF type role (New York) — content titles.
    public func atlasTitleSerif(size: CGFloat) -> some View {
        self.atlasFont(size: size, weight: .semibold, design: .serif)
    }
```

(`atlasNumeric`, `atlasScreenTitle`, and `atlasCapsLabel` already call `atlasMono`/`atlasTitleSerif` internally, so they inherit the scaling automatically — leave them as-is.)

- [ ] **Step 4: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AtlasCore/Sources/AtlasCore/Theme.swift
git commit -m "feat(theme): add atlasTextScale environment + atlasFont helper"
```

---

### Task 2: Wire the user setting into the environment at the app root

**Files:**
- Modify: `Atlas/App/AtlasApp.swift`

**Interfaces:**
- Consumes: `EnvironmentValues.atlasTextScale` (Task 1).
- Produces: `@AppStorage("appearance.textScale")` — Task 3's Settings UI binds to this exact key and default.

- [ ] **Step 1: Add the `@AppStorage` property**

In `AtlasApp.swift`, alongside the existing `@StateObject` properties (near `@StateObject private var focus = FocusViewModel()`), add:

```swift
    /// User-adjustable global text scale (Settings → General → Appearance).
    /// 1.0 = default; see `AtlasTextScaleKey` in AtlasCore/Theme.swift.
    @AppStorage("appearance.textScale") private var textScale: Double = 1.0
```

- [ ] **Step 2: Inject it into the environment**

In the `WindowGroup`'s modifier chain on `AppGate()`, next to the existing `.environment(\.docNoteWriteBack, ...)` line, add:

```swift
                .environment(\.atlasTextScale, CGFloat(textScale))
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Atlas/App/AtlasApp.swift
git commit -m "feat(theme): inject user text-scale setting into environment"
```

---

### Task 3: Add the "Text size" control to Settings

**Files:**
- Modify: `Atlas/Views/Auth/SettingsView.swift`

**Interfaces:**
- Consumes: `@AppStorage("appearance.textScale")` (Task 2's exact key/default/type).

- [ ] **Step 1: Add the `@AppStorage` property to `SettingsView`**

Next to the other `@AppStorage` properties near the top of `SettingsView` (e.g. right after `sidebarMode`), add:

```swift
    /// User-adjustable global text scale — same AppStorage key AtlasApp injects into the environment.
    @AppStorage("appearance.textScale") private var textScale: Double = 1.0
```

- [ ] **Step 2: Add an "appearance" section**

Add a new private computed property, following the exact style of `sidebarSection` (same file, defined right below it):

```swift
    // MARK: – Appearance section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("APPEARANCE")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text size")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Applies everywhere, immediately")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Picker("Text size", selection: $textScale) {
                    Text("Small").tag(0.9)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                    Text("X-Large").tag(1.3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()
        }
    }
```

- [ ] **Step 3: Insert it into the General tab**

In `sectionContent`, in the `.general` case's `VStack`, add `appearanceSection` right after `account` and before the `sidebarSection` divider (so the order becomes account → appearance → tasks → sidebar → shortcuts):

```swift
                VStack(alignment: .leading, spacing: 22) {
                    account
                    Divider().overlay(AtlasTheme.Colors.border)
                    appearanceSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    tasksSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    sidebarSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    shortcutsSection
                    Spacer(minLength: 8)
                }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual checkpoint (do not skip)**

Run the app, open Settings → General, and toggle the new "Text size" segmented control. Confirm:
- Text already routed through `atlasMono`/`atlasCapsLabel`/`atlasScreenTitle` (e.g. the sidebar's uppercase section labels, or the "Settings" screen title) visibly grows/shrinks live as you switch segments.
- Nothing crashes or lays out obviously broken.

This proves the scaling pipeline end-to-end before Task 5's big mechanical migration touches the other 343 call sites.

- [ ] **Step 6: Commit**

```bash
git add Atlas/Views/Auth/SettingsView.swift
git commit -m "feat(settings): add live text-size control"
```

---

### Task 4: Darken the secondary/muted text colors

**Files:**
- Modify: `AtlasCore/Sources/AtlasCore/Theme.swift`

- [ ] **Step 1: Edit the two hex values**

In `AtlasTheme.Colors`, change:

```swift
        public static let textSecondary = Color(hex: "6f6a5e")
        public static let textMuted      = Color(hex: "9c968a")
```

to darker tones (same hue, ~15% darker each):

```swift
        public static let textSecondary = Color(hex: "565145")
        public static let textMuted      = Color(hex: "7d7669")
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add AtlasCore/Sources/AtlasCore/Theme.swift
git commit -m "style(theme): darken secondary/muted text colors for contrast"
```

---

### Task 5: Migrate all hardcoded font call sites to `atlasFont` (+ ~10% size bump)

**Files:**
- Modify: all 38 files under `Atlas/` matching raw `.font(.system(size: ...))` (found via the grep in Step 1 below).
- Modify: the 6 files using `AtlasTheme.Font.*()` — `Atlas/Views/Metrics/MetricsView.swift`, `Atlas/Views/Calendar/UnscheduledTray.swift`, `Atlas/Views/References/AttachReferencePicker.swift`, `Atlas/Views/Search/CommandPalette.swift`, `Atlas/Views/Notes/NoteEditorView.swift`, `Atlas/Views/Notes/NotesListView.swift`.
- Modify: `AtlasCore/Sources/AtlasCore/Theme.swift` (delete the now-unused `AtlasTheme.Font` enum).
- Create (scratchpad only, not committed): a one-off migration script.

**Interfaces:**
- Consumes: `View.atlasFont(size:weight:design:)` (Task 1).
- Produces: no raw `.font(.system(size:` or `AtlasTheme.Font.` call sites remain under `Atlas/`.

This is a scripted, mechanical migration — verified by exact counts, not manual review of every line. All 326 raw call sites were confirmed during design to follow the single-line shape `.font(.system(size: N[, weight: W][, design: D]))` with no nested parens and no multiline splits, so a regex substitution is safe.

- [ ] **Step 1: Confirm the baseline count**

Run: `grep -rn "\.font(\.system(size:" --include="*.swift" Atlas | grep -v build | wc -l`
Expected: `326`

- [ ] **Step 2: Write the migration script**

Write to `/private/tmp/claude-501/migrate_fonts.py` (adjust path to your scratchpad):

```python
import re, sys, pathlib

# ~10% bump, rounded to the nearest whole point, for every distinct size
# found in the codebase during design.
SIZE_MAP = {
    "6": "7", "7": "8", "8": "9", "9": "10", "9.5": "10",
    "10": "11", "10.5": "12", "11": "12", "11.5": "13", "12": "13",
    "12.5": "14", "13": "14", "14": "15", "15": "17", "16": "18",
    "17": "19", "22": "24", "24": "26", "26": "29", "28": "31",
    "30": "33", "36": "40",
}

RAW_FONT_RE = re.compile(
    r"\.font\(\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)"
    r"(?:\s*,\s*weight:\s*(\.[A-Za-z]+))?"
    r"(?:\s*,\s*design:\s*(\.[A-Za-z]+))?\)\)"
)

def replace_raw(m):
    old_size, weight, design = m.group(1), m.group(2), m.group(3)
    new_size = SIZE_MAP[old_size]
    parts = [f"size: {new_size}"]
    if weight:
        parts.append(f"weight: {weight}")
    if design:
        parts.append(f"design: {design}")
    return f".atlasFont({', '.join(parts)})"

root = pathlib.Path("Atlas")
changed = 0
for path in root.rglob("*.swift"):
    if "build" in path.parts:
        continue
    text = path.read_text()
    new_text, n = RAW_FONT_RE.subn(replace_raw, text)
    if n:
        path.write_text(new_text)
        changed += n
        print(f"{path}: {n} replacements")

print(f"TOTAL: {changed}")
```

- [ ] **Step 3: Run it and verify the count**

Run: `cd /Users/jonahpark/Atlas && python3 /private/tmp/claude-501/migrate_fonts.py`
Expected: `TOTAL: 326`

- [ ] **Step 4: Verify zero raw call sites remain**

Run: `grep -rn "\.font(\.system(size:" --include="*.swift" Atlas | grep -v build | wc -l`
Expected: `0`

Run: `grep -rn "\.atlasFont(size:" --include="*.swift" Atlas | grep -v build | wc -l`
Expected: `326` (or slightly more once Step 5 below adds the `AtlasTheme.Font.*` conversions)

- [ ] **Step 5: Convert the 6 `AtlasTheme.Font.*()` files by hand**

These are only 17 call sites across 6 files — convert them directly (KeyError-safe, no script needed) using this mapping (base size × ~1.1, matching Task 5's scale):

| Old | New |
|---|---|
| `AtlasTheme.Font.small()` | `.atlasFont(size: 12)` |
| `AtlasTheme.Font.body()` | `.atlasFont(size: 14)` |
| `AtlasTheme.Font.bodyMedium()` | `.atlasFont(size: 14, weight: .medium)` |
| `AtlasTheme.Font.cardTitle()` | `.atlasFont(size: 15, weight: .semibold)` |

For the 16 sites of the form `.font(AtlasTheme.Font.X())`, replace with `.X-mapped` directly (drop the `.font(...)` wrapper since `atlasFont` already returns a modified view), e.g.:

```swift
// before
.font(AtlasTheme.Font.small())
// after
.atlasFont(size: 12)
```

Run this to find every site to convert: `grep -rn "AtlasTheme\.Font\." --include="*.swift" Atlas | grep -v build`

For the one exception — `Atlas/Views/Notes/NoteEditorView.swift`, the `font(for:)` helper (search for `private func font(for kind: RichDoc.BlockKind) -> Font`) — this one returns a plain `Font` value rather than applying a modifier, so it needs a slightly different fix. Give it access to the scale and multiply directly:

```swift
    private func font(for kind: RichDoc.BlockKind) -> Font {
        switch kind {
        case .heading:    return .system(size: 24 * textScale, weight: .bold, design: .rounded)
        case .subheading: return .system(size: 19 * textScale, weight: .semibold, design: .rounded)
        case .normal, .bulleted, .numbered: return .system(size: 14 * textScale, weight: .regular, design: .rounded)
        }
    }
```

(22→24, 17→19 per the size map; body's 13→14 as above.) Add `@Environment(\.atlasTextScale) private var textScale` as a property on the `NoteEditorView` struct (alongside its other `@Environment`/`@State` properties) so `textScale` is in scope.

- [ ] **Step 6: Delete the now-unused `AtlasTheme.Font` enum**

In `AtlasCore/Sources/AtlasCore/Theme.swift`, delete the entire `public enum Font { ... }` block (the one with `kicker()`, `sectionLabel()`, `greeting()`, `cardTitle()`, `body()`, `bodyMedium()`, `small()`).

Verify nothing else references it: `grep -rn "AtlasTheme\.Font\." --include="*.swift" Atlas AtlasMobile AtlasMobileWidgets | grep -v build` → expect no output.

- [ ] **Step 7: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

If it fails, the most likely cause is a call site where `SIZE_MAP` didn't have a key (a size not seen during design) — check the script's stderr/traceback, add the missing size (bumped ~10%, rounded), and re-run only on the affected file.

- [ ] **Step 8: Delete the scratch script and commit**

```bash
rm /private/tmp/claude-501/migrate_fonts.py
git add -A Atlas AtlasCore
git commit -m "refactor(fonts): migrate all hardcoded font sizes to atlasFont (+10%)"
```

---

### Task 6: Bump weight for secondary/muted text with implicit `.regular` weight

**Files:**
- Modify: all files under `Atlas/` where a `.atlasFont(...)` call with no explicit `weight:` is directly chained with `.foregroundStyle(AtlasTheme.Colors.textSecondary)` or `.foregroundStyle(AtlasTheme.Colors.textMuted)`.
- Create (scratchpad only, not committed): a one-off migration script.

**Interfaces:**
- Consumes: `.atlasFont(size:weight:design:)` call sites produced by Task 5.

This only touches call sites where the color is exactly `textSecondary`/`textMuted` (not a ternary like `selected ? .textPrimary : .textSecondary`) AND the font call has no explicit weight (meaning it was implicitly `.regular`). Call sites that already chose a weight deliberately (e.g. `.semibold`) are left untouched.

- [ ] **Step 1: Baseline count**

Run: `grep -rn "foregroundStyle(AtlasTheme.Colors.textSecondary)\|foregroundStyle(AtlasTheme.Colors.textMuted)" --include="*.swift" Atlas | grep -v build | wc -l`

Note this number (call it N) — it's the ceiling on how many sites Step 2 could touch (some will already have explicit weights and won't match).

- [ ] **Step 2: Write and run the weight-bump script**

Write to `/private/tmp/claude-501/bump_weight.py`:

```python
import re, pathlib

# Matches an atlasFont call with size (and optionally design) but NO weight,
# directly chained (only whitespace/newlines between) into a foregroundStyle
# call using exactly textSecondary or textMuted (never a ternary — a ternary
# has extra characters before the closing paren, so it won't match).
PATTERN = re.compile(
    r"\.atlasFont\(size:\s*([0-9.]+)(?:,\s*design:\s*(\.[A-Za-z]+))?\)"
    r"(\s*)\.foregroundStyle\(AtlasTheme\.Colors\.(textSecondary|textMuted)\)"
)

def replace(m):
    size, design, gap, color = m.group(1), m.group(2), m.group(3), m.group(4)
    parts = [f"size: {size}", "weight: .medium"]
    if design:
        parts.append(f"design: {design}")
    return f".atlasFont({', '.join(parts)}){gap}.foregroundStyle(AtlasTheme.Colors.{color})"

root = pathlib.Path("Atlas")
changed = 0
for path in root.rglob("*.swift"):
    if "build" in path.parts:
        continue
    text = path.read_text()
    new_text, n = PATTERN.subn(replace, text)
    if n:
        path.write_text(new_text)
        changed += n
        print(f"{path}: {n} replacements")

print(f"TOTAL: {changed}")
```

Run: `cd /Users/jonahpark/Atlas && python3 /private/tmp/claude-501/bump_weight.py`

Expected: some number > 0, ≤ N from Step 1. Note the printed total.

- [ ] **Step 3: Spot-check a few diffs**

Run: `git diff --stat Atlas | tail -20` to see which files changed, then `git diff Atlas/App/RootView.swift` (or another file from the list) to confirm the diff looks like: `.atlasFont(size: 14, design: .rounded)` → `.atlasFont(size: 14, weight: .medium, design: .rounded)` immediately above an unchanged `.foregroundStyle(AtlasTheme.Colors.textSecondary)` line.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Delete the scratch script and commit**

```bash
rm /private/tmp/claude-501/bump_weight.py
git add -A Atlas
git commit -m "style(text): bump secondary/muted text to medium weight where unset"
```

---

### Task 7: Final manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build one more time from a clean state**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' clean build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run the app and check the following pages**

- **Settings → General:** the new "Text size" control; switch through all four segments and confirm the whole window's text (not just Settings) rescales live.
- **Calendar (week/month view):** event titles, time labels, headers — bigger than before, still fits without obvious clipping/overlap.
- **Sidebar:** section labels, project/space rows — bigger, and the muted/secondary rows (e.g. unselected items) read darker/bolder than before, not washed out.
- **Notes editor:** heading/subheading/body text sizes.

- [ ] **Step 3: Report to the user**

Per this project's working agreement, do not claim the UI change "works" — report it as "migrated, builds clean, needs your visual check," and ask the user to confirm on the pages above (and flag anything that looks clipped, wrapped wrong, or overlapping so it can be fixed in a follow-up).
