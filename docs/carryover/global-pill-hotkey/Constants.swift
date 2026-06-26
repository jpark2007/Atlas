// CARRYOVER — from old Atlas prototype. Hotkey defaults + persistence keys for HotkeyService.
import Foundation
import Carbon

enum AppConstants {
    static let appName = "Atlas"
    static let defaultWindowWidth: CGFloat = 1100
    static let defaultWindowHeight: CGFloat = 720
    static let sidebarWidth: CGFloat = 230

    // Hotkey defaults + persistence keys
    static let defaultCaptureKeyCode: UInt32 = 49 // Space
    static let defaultCaptureModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let captureKeyCodeKey = "captureHotkeyKeyCode"
    static let captureModifiersKey = "captureHotkeyModifiersRaw"
}

// Required entitlement for global hotkeys (App Sandbox must be OFF):
//   com.apple.security.app-sandbox = false
// Registration happens in the App entry point's .onAppear:
//   HotkeyService.shared.register(onPress: { controller.show() },
//                                 onRelease: { /* stop recording */ })
