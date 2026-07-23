import Foundation
import AtlasCore

// MARK: - Capture history model
//
// One quick-capture (one paste → one AI round-trip → one merged array of items)
// is recorded as a single `CaptureHistoryEntry`. Each created task/event/note is
// stored with a SNAPSHOT of its user-meaningful fields at creation, so Undo can
// tell whether the item is still exactly as Atlas made it (eligible) or has been
// edited/moved/completed/deleted since (not eligible).
//
// Persisted per signed-in user as a small Codable JSON file in Application
// Support — client-side only, never on the server (captures make Atlas-native
// items, so there's nothing extra to sync).

/// A single created item's snapshot, taken the moment capture made it.
struct CaptureHistoryItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case task, event, note }

    let id: UUID          // the created domain object's id
    let kind: Kind
    let title: String
    let start: Date?      // events
    let end: Date?        // events
    let dueDate: Date?    // tasks
    let spaceName: String
    let projectName: String
    let done: Bool?       // tasks

    init(task: TaskItem) {
        id = task.id
        kind = .task
        title = task.title
        start = nil
        end = nil
        dueDate = task.dueDate
        spaceName = task.spaceName
        projectName = task.projectName
        done = task.done
    }

    init(event: CalendarEvent) {
        id = event.id
        kind = .event
        title = event.title
        start = event.start
        end = event.end
        dueDate = nil
        spaceName = event.spaceName
        projectName = ""
        done = nil
    }

    init(note: Note) {
        id = note.id
        kind = .note
        title = note.title
        start = nil
        end = nil
        dueDate = nil
        spaceName = note.spaceName ?? ""
        projectName = ""
        done = nil
    }
}

/// One recorded quick-capture: its text snippet, when it ran, and the items it
/// created. `undoneAt` is stamped once the capture has been undone (its items
/// deleted) — the entry stays in the list, marked, rather than vanishing.
struct CaptureHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let snippet: String
    var items: [CaptureHistoryItem]
    var undoneAt: Date?

    init(id: UUID = UUID(), date: Date = Date(), snippet: String,
         items: [CaptureHistoryItem], undoneAt: Date? = nil) {
        self.id = id
        self.date = date
        self.snippet = snippet
        self.items = items
        self.undoneAt = undoneAt
    }
}

/// Paired result of applying one `CaptureResult`: the user-facing outcome (for the
/// confirmation copy) plus the history snapshot of the item that was created.
struct AppliedCapture {
    let outcome: CaptureOutcome
    let item: CaptureHistoryItem
}

// MARK: - On-disk store (per user, Application Support)

enum CaptureHistoryStore {
    static let cap = 50

    private static let coder: (encoder: JSONEncoder, decoder: JSONDecoder) = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }()

    private static func fileURL(userID: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Atlas/CaptureHistory", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // A user id is a UUID string — already filesystem-safe.
        return dir.appendingPathComponent("\(userID).json")
    }

    static func load(userID: String) -> [CaptureHistoryEntry] {
        guard let url = fileURL(userID: userID),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? coder.decoder.decode([CaptureHistoryEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [CaptureHistoryEntry], userID: String) {
        guard let url = fileURL(userID: userID) else { return }
        let capped = Array(entries.prefix(cap))
        guard let data = try? coder.encoder.encode(capped) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - AppState: record / eligibility / undo

extension AppState {
    /// Records a completed capture as one history entry (newest first, capped at 50)
    /// and persists it for the current user. No-op on an empty item set.
    func recordCapture(rawText: String, items: [CaptureHistoryItem]) {
        guard !items.isEmpty else { return }
        let snippet = String(rawText.prefix(140))
        captureHistory.insert(CaptureHistoryEntry(snippet: snippet, items: items), at: 0)
        if captureHistory.count > CaptureHistoryStore.cap {
            captureHistory = Array(captureHistory.prefix(CaptureHistoryStore.cap))
        }
        persistCaptureHistory()
    }

    /// Loads a user's history from disk (or clears it when signed out / switched).
    func loadCaptureHistory(userID: String?) {
        captureHistory = userID.map { CaptureHistoryStore.load(userID: $0) } ?? []
    }

    private func persistCaptureHistory() {
        guard let userID = loadedUserID else { return }
        CaptureHistoryStore.save(captureHistory, userID: userID)
    }

    /// Undo is offered only when the entry hasn't already been undone AND every item
    /// it created still exists and still matches its capture-time snapshot.
    func captureUndoEligible(_ entry: CaptureHistoryEntry) -> Bool {
        entry.undoneAt == nil && entry.items.allSatisfy { itemMatchesCurrent($0) }
    }

    /// Deletes every still-matching item in the entry through the app's normal
    /// (server-synced) delete paths, then marks the entry undone. Re-checks
    /// eligibility first so a stale button press can't delete edited items.
    func undoCapture(_ entry: CaptureHistoryEntry) {
        guard let idx = captureHistory.firstIndex(where: { $0.id == entry.id }),
              captureUndoEligible(captureHistory[idx]) else { return }
        for item in captureHistory[idx].items {
            switch item.kind {
            case .task:  deleteTask(id: item.id)
            case .event: deleteEvent(id: item.id)
            case .note:  deleteNote(id: item.id)
            }
        }
        captureHistory[idx].undoneAt = Date()
        persistCaptureHistory()
    }

    /// True when the live domain object for `item` still matches its snapshot.
    /// A missing id (edited-away, deleted) fails the match — undo stays disabled.
    private func itemMatchesCurrent(_ item: CaptureHistoryItem) -> Bool {
        switch item.kind {
        case .task:
            guard let t = tasks.first(where: { $0.id == item.id }) else { return false }
            return t.title == item.title
                && t.spaceName == item.spaceName
                && t.projectName == item.projectName
                && t.done == (item.done ?? false)
                && datesMatch(t.dueDate, item.dueDate)
        case .event:
            guard let e = events.first(where: { $0.id == item.id }) else { return false }
            return e.title == item.title
                && e.spaceName == item.spaceName
                && datesMatch(e.start, item.start)
                && datesMatch(e.end, item.end)
        case .note:
            guard let n = notes.first(where: { $0.id == item.id }) else { return false }
            return n.title == item.title
                && (n.spaceName ?? "") == item.spaceName
        }
    }

    /// Dates match within a second — absorbs sub-second drift from the JSON
    /// round-trip so an untouched item still reads as unchanged.
    private func datesMatch(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x.timeIntervalSince(y)) < 1
        default: return false
        }
    }
}
