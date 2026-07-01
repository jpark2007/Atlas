import Foundation

/// A raw capture dump held on-device because the AI (server-side) was unreachable
/// when it was entered. Drained the next time Capture appears / the app foregrounds
/// with a working connection.
struct QueuedCapture: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
}

/// UserDefaults-backed FIFO of pending capture dumps. Observable so the Capture
/// screen can show a calm "saved offline" line while items wait.
@MainActor
final class PendingCaptureQueue: ObservableObject {
    @Published private(set) var items: [QueuedCapture] = []

    private let key = "atlas.capture.pending"

    init() { load() }

    func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(QueuedCapture(text: trimmed))
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([QueuedCapture].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
