# WS-6 — Global Hotkey + Voice (plan)

**Date:** 2026-06-27 · **Branch:** feat/daily-driver-v1 · Spec §4 WS-6

## Goal
Make capture work system-wide (⌘⇧K even when Atlas is unfocused) and add click-to-talk
on-device dictation to the capture overlay. Keep the existing in-app ShortcutStore binding.

## Pieces

### 1. Global hotkey (Carbon)
- New `Atlas/Services/HotkeyService.swift`, adapted from `docs/carryover/global-pill-hotkey/HotkeyService.swift`.
  - Keep the Carbon `RegisterEventHotKey` core (works system-wide, no sandbox).
  - Add a **press-only** registration path (`register(onPress:)`) that does NOT install the
    global keyUp/flagsChanged release monitors — those require Input-Monitoring permission and
    we only need "open capture on press". Drop the push-to-talk release machinery for v2.
  - Inline a small `HotkeyDefaults` (keycode/modifiers + UserDefaults keys), default ⌘⇧K
    (keyCode 40 = K, mods cmd|shift) so the global combo matches the in-app shortcut.
- Wire in `AtlasApp` via a tiny `GlobalHotkeyInstaller` view (`.onAppear`) reading `@EnvironmentObject AppState`:
  on press → `NSApp.activate(ignoringOtherApps:)` then `state.presentCapture = true`.
- Leave `.atlasCaptureOverlay()` (ShortcutStore ⌘⇧K binding) untouched — both coexist; Carbon
  consumes the combo when focused, SwiftUI handles nothing extra; setting presentCapture is idempotent.

### 2. Voice — click-to-talk (NOT on open)
- New `Atlas/Services/SpeechCaptureService.swift`:
  - `@MainActor ObservableObject`, `SFSpeechRecognizer` + `AVAudioEngine`, on-device when supported.
  - `toggle(currentText:onTranscript:)` — first tap requests mic (`AVCaptureDevice.requestAccess(.audio)`)
    + speech auth, starts the engine, streams composed transcript via `onTranscript`; second tap stops.
  - Never auto-listens; only `toggle`/`start` begin recording.
  - **Pure, testable core** `SpeechCaptureCore` (Foundation-only, no Speech/AV import):
    - `resolveStartState(speechAuthorized:micAuthorized:recognizerAvailable:) -> SpeechCaptureState`
    - `compose(base:transcript:) -> String` (append live transcript onto already-typed text)
    - `nextStateOnToggle(from:resolvedStart:)`
- Mic button added to the **corner** of the capture bar in `CaptureOverlay.swift`; recording =
  danger-red pulse; transcript streams into the existing `text` field; tapping again stops; dismiss stops.

### 3. Permissions / entitlements
- `project.yml` Atlas target: add `INFOPLIST_KEY_NSMicrophoneUsageDescription` +
  `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`; add `CODE_SIGN_ENTITLEMENTS: Atlas/Atlas.entitlements`.
- New `Atlas/Atlas.entitlements`: `com.apple.security.device.audio-input = true` (mic under hardened
  runtime). Deliberately NO app-sandbox key (Carbon global hotkey needs sandbox OFF).

## Tests
- `AtlasTests/SpeechCaptureCoreTests.swift` — resolveStartState gating (denied/unavailable/listening),
  compose spacing rules, toggle transitions. Pure, no audio engine.

## Verify
`xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`

## needsUser
Granting mic + speech permission at runtime (first mic tap); the consent dialogs can't be clicked headlessly.
