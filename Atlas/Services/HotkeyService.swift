import Foundation
import AtlasCore
import Carbon
import AppKit

// MARK: - Hotkey defaults
//
// Global capture combo. Defaults to ⌘⇧K so the system-wide hotkey matches the
// in-app ShortcutStore binding for Quick Capture. Persisted in UserDefaults so a
// future Settings rebind can override it.

enum HotkeyDefaults {
    static let defaultCaptureKeyCode: UInt32 = UInt32(kVK_ANSI_K) // 40 = "K"
    static let defaultCaptureModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let captureKeyCodeKey = "captureHotkeyKeyCode"
    static let captureModifiersKey = "captureHotkeyModifiersRaw"
}

// MARK: - HotkeyService
//
// System-wide hotkey via Carbon `RegisterEventHotKey` — fires even when Atlas is
// unfocused. Adapted from the carryover prototype; the push-to-talk release
// machinery was dropped because v2 only needs "open capture on press", and the
// global keyUp monitors it required would have needed Input-Monitoring
// permission. Requires App Sandbox to be OFF (it is — no sandbox entitlement).

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var onPress: (() -> Void)?
    private var isRegistered = false

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0

    private static let hotKeyID: EventHotKeyID = {
        var id = EventHotKeyID()
        id.signature = OSType(0x41544C53) // "ATLS"
        id.id = 1
        return id
    }()

    /// Press-only registration: `onPress` fires each time the global combo is
    /// pressed. Idempotent — calling twice keeps a single handler. Reads the
    /// stored shortcut (or the ⌘⇧K default) and arms it.
    func register(onPress: @escaping () -> Void) {
        self.onPress = onPress
        guard !isRegistered else { return }
        isRegistered = true

        // Install the process-wide Carbon event handler exactly once.
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { service.handleHotKeyPressed() }
            }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, selfPtr, &eventHandler)

        let defaults = UserDefaults.standard
        let storedKeyCode = defaults.object(forKey: HotkeyDefaults.captureKeyCodeKey) as? Int
        let storedModifiers = defaults.object(forKey: HotkeyDefaults.captureModifiersKey) as? Int
        let keyCode = UInt32(storedKeyCode ?? Int(HotkeyDefaults.defaultCaptureKeyCode))
        let modifiers = UInt32(storedModifiers ?? Int(HotkeyDefaults.defaultCaptureModifiers))
        applyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func handleHotKeyPressed() {
        onPress?()
    }

    /// Swap the current hotkey for a new combo without re-installing the handler.
    /// Returns the `RegisterEventHotKey` status so callers can detect a failed
    /// registration (e.g. the combo is already owned system-wide).
    @discardableResult
    func update(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        let status = applyShortcut(keyCode: keyCode, modifiers: modifiers)
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: HotkeyDefaults.captureKeyCodeKey)
        defaults.set(Int(modifiers), forKey: HotkeyDefaults.captureModifiersKey)
        return status
    }

    @discardableResult
    private func applyShortcut(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        hotKeyRef = newRef
        currentKeyCode = keyCode
        currentModifiers = modifiers
        return status
    }

    // MARK: - Display helpers (for a future Settings rebind UI)

    static func currentDisplayString() -> String {
        let defaults = UserDefaults.standard
        let keyCode = UInt32((defaults.object(forKey: HotkeyDefaults.captureKeyCodeKey) as? Int) ?? Int(HotkeyDefaults.defaultCaptureKeyCode))
        let modifiers = UInt32((defaults.object(forKey: HotkeyDefaults.captureModifiersKey) as? Int) ?? Int(HotkeyDefaults.defaultCaptureModifiers))
        return displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += keyName(for: keyCode)
        return out
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:  return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab:    return "Tab"
        case kVK_Escape: return "Esc"
        default:
            if let char = asciiCharFor(keyCode) { return String(char).uppercased() }
            return "Key\(keyCode)"
        }
    }

    private static func asciiCharFor(_ keyCode: UInt32) -> Character? {
        let map: [Int: Character] = [
            kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
            kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
            kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
            kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
            kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
            kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
            kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9"
        ]
        return map[Int(keyCode)]
    }
}
