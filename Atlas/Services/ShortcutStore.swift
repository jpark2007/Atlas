import SwiftUI

// MARK: - ShortcutAction

/// The in-app actions that have user-rebindable keyboard shortcuts.
/// (Global system-wide Carbon hotkey is explicitly deferred — out of v1 scope.)
enum ShortcutAction: String, CaseIterable, Identifiable {
    case capture
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Quick Capture"
        case .search:  return "Command Palette"
        }
    }

    var defaultKey: Character { "k" }

    var defaultModifiers: EventModifiers {
        switch self {
        case .capture: return [.command, .shift]
        case .search:  return [.command]
        }
    }
}

// MARK: - ShortcutBinding

/// A (key, modifiers) pair the user has assigned to a ShortcutAction.
struct ShortcutBinding: Equatable {
    var key: Character
    var modifiers: EventModifiers

    /// SwiftUI-usable form; supply directly to `.keyboardShortcut(...)`.
    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }

    /// Human-readable glyph string, e.g. "⌘⇧K". Order: ⌃⌥⇧⌘ + key (matches macOS HIG).
    var displayString: String {
        var s = ""
        if modifiers.contains(.control)  { s += "⌃" }
        if modifiers.contains(.option)   { s += "⌥" }
        if modifiers.contains(.shift)    { s += "⇧" }
        if modifiers.contains(.command)  { s += "⌘" }
        s += String(key).uppercased()
        return s
    }
}

// MARK: - ShortcutStore

/// Observable store for user-editable in-app keyboard shortcuts.
///
/// Persists to UserDefaults using:
///   - `shortcut.<action>.key`  — single-character string
///   - `shortcut.<action>.mods` — EventModifiers.rawValue (Int)
///
/// Inject app-wide as an `@StateObject` + `.environmentObject(shortcuts)`.
final class ShortcutStore: ObservableObject {

    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding]

    private let defaults: UserDefaults

    // MARK: init

    /// Designated init. Pass a custom `UserDefaults` suite in tests to avoid
    /// polluting `.standard` and to get reliable isolation between test cases.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var initial: [ShortcutAction: ShortcutBinding] = [:]
        for action in ShortcutAction.allCases {
            initial[action] = Self.load(action: action, from: defaults)
        }
        self.bindings = initial
    }

    // MARK: Public API

    func binding(for action: ShortcutAction) -> ShortcutBinding {
        bindings[action] ?? defaultBinding(for: action)
    }

    /// Saves `binding` for `action` to UserDefaults and publishes the change.
    func set(_ binding: ShortcutBinding, for action: ShortcutAction) {
        bindings[action] = binding
        save(binding: binding, for: action)
    }

    /// Resets `action` to its hard-coded default and persists the reset.
    func reset(_ action: ShortcutAction) {
        set(defaultBinding(for: action), for: action)
    }

    /// Returns the OTHER action that already uses `binding`, or `nil` if none.
    /// Pass `excluding` as the action you are currently editing so it isn't
    /// treated as its own conflict.
    func conflict(_ binding: ShortcutBinding, excluding: ShortcutAction) -> ShortcutAction? {
        for action in ShortcutAction.allCases {
            guard action != excluding else { continue }
            let existing = self.binding(for: action)
            if existing.key == binding.key && existing.modifiers == binding.modifiers {
                return action
            }
        }
        return nil
    }

    // MARK: Private helpers

    private func defaultBinding(for action: ShortcutAction) -> ShortcutBinding {
        ShortcutBinding(key: action.defaultKey, modifiers: action.defaultModifiers)
    }

    private func save(binding: ShortcutBinding, for action: ShortcutAction) {
        defaults.set(String(binding.key), forKey: "shortcut.\(action.rawValue).key")
        defaults.set(binding.modifiers.rawValue, forKey: "shortcut.\(action.rawValue).mods")
    }

    private static func load(action: ShortcutAction, from defaults: UserDefaults) -> ShortcutBinding {
        let keyStr = defaults.string(forKey: "shortcut.\(action.rawValue).key")
        // Use object(forKey:) so we can tell 0 apart from "not set" (0 is a valid rawValue).
        let modsObj = defaults.object(forKey: "shortcut.\(action.rawValue).mods") as? Int

        if let firstChar = keyStr?.first, let rawMods = modsObj {
            return ShortcutBinding(
                key: firstChar,
                modifiers: EventModifiers(rawValue: rawMods)
            )
        }
        // Fall back to defaults.
        return ShortcutBinding(key: action.defaultKey, modifiers: action.defaultModifiers)
    }
}
