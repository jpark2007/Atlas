import Foundation
import Combine

// MARK: - Draft buffer
//
// "If I typed it, Atlas saved it." The capture field's in-progress text lives in
// SwiftUI `@State`, which dies with the view — on Mac every summon rebuilds the
// panel (CapturePanelController.hide() nils it), on iOS an app kill takes it.
// So the buffer is mirrored to UserDefaults on each keystroke and restored when
// the capture surface next appears. It is cleared only once the text is safely
// committed or queued — never on the optimistic field clear at submit, so a
// crash mid-submit still restores what was typed.

/// UserDefaults-backed single-string draft buffer for the capture field.
public enum CaptureDraftStore {
    /// Storage key (account-deletion cleanup should remove this).
    public static let key = "atlas.capture.draft"

    public static func load(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: key) ?? ""
    }

    /// Persists `text`; whitespace-only text clears the buffer instead.
    public static func save(_ text: String, to defaults: UserDefaults = .standard) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clear(from: defaults)
        } else {
            defaults.set(text, forKey: key)
        }
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Pending queue

/// A raw capture dump held on-device because the AI (server-side) was unreachable
/// or erroring when it was entered. Drained the next time the capture surface
/// appears with a working connection.
public struct QueuedCapture: Codable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
}

/// UserDefaults-backed FIFO of pending capture dumps, shared by Mac and iOS.
/// Observable so a capture surface can show a calm "saved offline" line while
/// items wait.
@MainActor
public final class PendingCaptureQueue: ObservableObject {
    @Published public private(set) var items: [QueuedCapture] = []

    /// Storage key (account-deletion cleanup should remove this).
    public static let key = "atlas.capture.pending"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(QueuedCapture(text: trimmed))
        save()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([QueuedCapture].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Failure classification

extension URLError {
    /// True for the "no usable network" family — the signal to hold a dump for
    /// later instead of surfacing an error.
    public var isConnectivity: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
