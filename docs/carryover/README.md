# Carryover code (from the old Atlas prototype)

This folder holds the **two features we deliberately lifted** from the previous Atlas Swift project
(`~/Documents/Personal project/Atlas`) before deleting it. Everything else from that prototype was
**intentionally left behind** — do not treat it as a reference for the rest of Atlas.

> Status: **reference code, not yet integrated.** These files are verbatim from the old app and
> will be restyled to Atlas's "liquid glass" look and adapted for the iOS + macOS shared codebase.

## What's here

### `global-pill-hotkey/`
A system-wide macOS hotkey (default **⌘⇧Space**) that summons a floating "pill" command panel.
- `HotkeyService.swift` — Carbon global hotkey registration + push-to-talk release detection.
- `CapturePanelController.swift` — the floating `NSPanel` (borderless, floating, all-Spaces) host.
- `CapturePanelView.swift` — the SwiftUI pill UI (idle/recording/processing/results states).
- `Constants.swift` — hotkey defaults + UserDefaults persistence keys.

### `focus-pill-timer/`
A focus-session (Pomodoro-style) timer with a pill button + macOS menu-bar display.
- `FocusViewModel.swift` — timer/break logic (`@Observable`, Foundation.Timer).
- `FocusSession.swift` — SwiftData model for session history.
- `FocusView.swift` — the timer UI (144pt serif display, `Capsule()` pill button, Space=break).
- `MenuBarService.swift` — macOS menu-bar live timer (AppKit `NSStatusItem`).
- `FocusReflectionSheet.swift` — post-session notes sheet.

## Known dependencies these files expect (need re-creating / restyling)

These reference things from the old app that we are **not** carrying as-is — recreate or replace:
- `DS` design system (`DS.Colors`, `DS.Typography`, `DS.Spacing`, `DS.Radius`) → replace with Atlas's new design system.
- `CaptureViewModel`, `AtlasProject`, `Bucket`, `Client`, `FocusBentoPicker`, `FocusHistoryView`,
  `FocusBackgroundPaths`, `FocusStartSheet`, `FocusBucketListSheet` → old-app types/views; rebuild against the new data model ([../specs/02-data-model.md](../specs/02-data-model.md)).

## Platform notes
- **macOS-only:** Carbon hotkeys (`RegisterEventHotKey`), `NSPanel`, `NSStatusBar`/menu bar, `NSScreen`.
  Wrap in `#if os(macOS)`.
- **iOS:** no global hotkey — trigger the pill via a widget / Siri Shortcut / share sheet instead.
- **Entitlement:** the global hotkey needs **App Sandbox = OFF** (affects Mac App Store distribution).
- Min deployment in old app: macOS 14.0, Swift 5.9. Timer logic + most SwiftUI is cross-platform.
