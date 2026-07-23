import SwiftUI
import Carbon
import AtlasCore

/// Single sync point between the in-app capture shortcut (ShortcutStore, SwiftUI
/// Character + EventModifiers) and the system-wide Carbon hotkey (HotkeyService,
/// keycode + Carbon mask). ShortcutStore's `.capture` binding is the source of
/// truth; the Carbon hotkey is always derived from it, so the two can never drift.
enum CaptureShortcutSync {

    /// Reverse of HotkeyService.asciiCharFor — SwiftUI Character → Carbon virtual keycode.
    static func carbonKeyCode(for char: Character) -> UInt32? {
        let map: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            " ": kVK_Space
        ]
        let lower = Character(String(char).lowercased())
        return map[lower].map { UInt32($0) }
    }

    /// SwiftUI EventModifiers → Carbon modifier mask.
    /// `EventModifiers` is qualified as `SwiftUI.EventModifiers` throughout because
    /// `import Carbon` also declares an `EventModifiers` typealias (a `UInt16`).
    static func carbonModifiers(from mods: SwiftUI.EventModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if mods.contains(.command) { mask |= UInt32(cmdKey) }
        if mods.contains(.shift)   { mask |= UInt32(shiftKey) }
        if mods.contains(.option)  { mask |= UInt32(optionKey) }
        if mods.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// Persist a new capture binding to BOTH representations atomically and register
    /// the Carbon hotkey. Returns the registration OSStatus (`noErr` == success).
    /// If the character has no Carbon keycode, the in-app binding is still saved and
    /// `eventInternalErr` is returned so the caller can prompt for another combo.
    @discardableResult
    @MainActor
    static func apply(_ binding: ShortcutBinding, to shortcuts: ShortcutStore) -> OSStatus {
        shortcuts.set(binding, for: .capture)
        guard let keyCode = carbonKeyCode(for: binding.key) else {
            return OSStatus(eventInternalErr)
        }
        let mask = carbonModifiers(from: binding.modifiers)
        return HotkeyService.shared.update(keyCode: keyCode, modifiers: mask)
    }

    /// At launch, derive the Carbon hotkey from the in-app `.capture` binding so the
    /// two never drift from previously-stored divergent values. Call AFTER
    /// HotkeyService.shared.register(...).
    @MainActor
    static func reconcileOnLaunch(_ shortcuts: ShortcutStore) {
        let binding = shortcuts.binding(for: .capture)
        guard let keyCode = carbonKeyCode(for: binding.key) else { return }
        HotkeyService.shared.update(keyCode: keyCode, modifiers: carbonModifiers(from: binding.modifiers))
    }

    /// Soft warning for combos commonly claimed by macOS or other apps. A non-nil
    /// result means "warn the user this may not reach Atlas" — callers should still
    /// APPLY the binding (these are warnings, not blocks). Returns nil for combos with
    /// no known claim. Not exhaustive — there is no API to enumerate other apps' custom
    /// binds (e.g. Raycast); Carbon registration failure in `apply` covers those.
    static func claimWarning(_ binding: ShortcutBinding) -> String? {
        let k = Character(String(binding.key).lowercased())
        let m = binding.modifiers
        let combo = binding.displayString

        // Named macOS system owners → call them out specifically.
        var owner: String?
        if m == [.command] && k == " " { owner = "Spotlight" }
        else if m == [.command] && k == "q" { owner = "Quit" }
        else if m == [.command] && k == "w" { owner = "Close window" }
        else if m == [.command] && k == "h" { owner = "Hide" }
        else if m == [.command] && k == "m" { owner = "Minimize" }
        else if m == [.command] && k == "," { owner = "Settings" }
        else if m == [.command] && k == "\t" { owner = "App switcher" }
        else if m == [.command, .shift] && (k == "3" || k == "4" || k == "5") { owner = "Screenshot" }

        if let owner {
            return "\(combo) is used by macOS for \(owner) — it may not reach Atlas. You can keep it or pick another."
        }

        // Broad heuristic: bare ⌘ + a single letter or digit (⌘0–⌘9, ⌘A–⌘Z) is
        // commonly claimed by apps (tab switching, menu items).
        if m == [.command], k.isLetter || k.isNumber {
            return "\(combo) is often used by other apps or macOS — it may not reach Atlas. You can keep it or pick another."
        }
        return nil
    }
}
