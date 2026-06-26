// CARRYOVER — from old Atlas prototype. macOS-only. Restyle/adapt before use.
// Global system-wide hotkey via Carbon + push-to-talk release detection via NSEvent monitors.
import Foundation
import Carbon
import AppKit

final class HotkeyService {
    static let shared = HotkeyService()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private var isPressed: Bool = false
    private var releaseGlobalMonitor: Any?
    private var releaseLocalMonitor: Any?

    private static let hotKeyID: EventHotKeyID = {
        var id = EventHotKeyID()
        id.signature = OSType(0x41544C53) // "ATLS"
        id.id = 1
        return id
    }()

    /// Press/release variant. onPress fires when the user presses the hotkey;
    /// onRelease fires when any part of the combo is released (the key itself
    /// or any of the required modifiers). Enables push-to-talk behavior.
    func register(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease

        // Install the process-wide Carbon event handler exactly once.
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                service.handleHotKeyPressed()
            }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, selfPtr, &eventHandler)

        // Read stored shortcut (or defaults) and register.
        let defaults = UserDefaults.standard
        let storedKeyCode = defaults.object(forKey: AppConstants.captureKeyCodeKey) as? Int
        let storedModifiers = defaults.object(forKey: AppConstants.captureModifiersKey) as? Int
        let keyCode = UInt32(storedKeyCode ?? Int(AppConstants.defaultCaptureKeyCode))
        let modifiers = UInt32(storedModifiers ?? Int(AppConstants.defaultCaptureModifiers))
        applyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Press / release handling

    private func handleHotKeyPressed() {
        // Carbon fires kEventHotKeyPressed on each press even while held;
        // we only arm the release monitor once per actual press.
        guard !isPressed else { return }
        isPressed = true
        onPress?()
        installReleaseMonitors()
    }

    private func installReleaseMonitors() {
        removeReleaseMonitors()
        let keyCode = currentKeyCode
        let required = currentModifiers

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isPressed else { return }
            let released: Bool
            if event.type == .keyUp {
                released = UInt32(event.keyCode) == keyCode
            } else if event.type == .flagsChanged {
                let current = Self.carbonModifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
                released = (current & required) != required
            } else {
                released = false
            }
            if released {
                Task { @MainActor in self.fireRelease() }
            }
        }

        releaseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { event in
            handler(event)
        }
        releaseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { event in
            handler(event)
            return event
        }
    }

    private func removeReleaseMonitors() {
        if let monitor = releaseGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            releaseGlobalMonitor = nil
        }
        if let monitor = releaseLocalMonitor {
            NSEvent.removeMonitor(monitor)
            releaseLocalMonitor = nil
        }
    }

    private func fireRelease() {
        guard isPressed else { return }
        isPressed = false
        removeReleaseMonitors()
        onRelease?()
    }

    /// Swap the current hotkey for a new combo without re-installing the handler.
    func update(keyCode: UInt32, modifiers: UInt32) {
        applyShortcut(keyCode: keyCode, modifiers: modifiers)
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: AppConstants.captureKeyCodeKey)
        defaults.set(Int(modifiers), forKey: AppConstants.captureModifiersKey)
    }

    private func applyShortcut(keyCode: UInt32, modifiers: UInt32) {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        var newRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        hotKeyRef = newRef
        currentKeyCode = keyCode
        currentModifiers = modifiers
        // If the user rebinds while the previous combo is "pressed", clean up.
        if isPressed {
            fireRelease()
        }
    }

    // MARK: - Display

    static func currentDisplayString() -> String {
        let defaults = UserDefaults.standard
        let keyCode = UInt32((defaults.object(forKey: AppConstants.captureKeyCodeKey) as? Int) ?? Int(AppConstants.defaultCaptureKeyCode))
        let modifiers = UInt32((defaults.object(forKey: AppConstants.captureModifiersKey) as? Int) ?? Int(AppConstants.defaultCaptureModifiers))
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
        case kVK_Space:        return "Space"
        case kVK_Return:       return "Return"
        case kVK_Tab:          return "Tab"
        case kVK_Escape:       return "Esc"
        case kVK_Delete:       return "Delete"
        case kVK_ForwardDelete: return "Fwd Delete"
        case kVK_LeftArrow:    return "←"
        case kVK_RightArrow:   return "→"
        case kVK_UpArrow:      return "↑"
        case kVK_DownArrow:    return "↓"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let char = Self.asciiCharFor(keyCode) {
                return String(char).uppercased()
            }
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
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "="
        ]
        return map[Int(keyCode)]
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= UInt32(cmdKey) }
        if flags.contains(.shift)    { m |= UInt32(shiftKey) }
        if flags.contains(.option)   { m |= UInt32(optionKey) }
        if flags.contains(.control)  { m |= UInt32(controlKey) }
        return m
    }
}
