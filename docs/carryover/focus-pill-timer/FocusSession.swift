// CARRYOVER — from old Atlas prototype. SwiftData model for focus-session history.
// Depends on old `AtlasProject` model.
import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID = UUID()
    var project: AtlasProject?
    var startedAt: Date = Date()
    var endedAt: Date?
    var notes: String?
    var intention: String?
    /// Total seconds spent on break during this session. Subtracted from
    /// wall-clock duration to produce the "real" focus duration.
    var totalBreakSeconds: Int = 0

    /// Wall-clock seconds minus break seconds, clamped at zero.
    var focusSeconds: Int {
        let end = endedAt ?? Date()
        let wall = Int(end.timeIntervalSince(startedAt))
        return Swift.max(0, wall - totalBreakSeconds)
    }

    var durationMinutes: Int { focusSeconds / 60 }
    var breakMinutes: Int { totalBreakSeconds / 60 }

    init(project: AtlasProject? = nil) {
        self.id = UUID()
        self.project = project
        self.startedAt = Date()
        self.endedAt = nil
        self.notes = nil
        self.intention = nil
        self.totalBreakSeconds = 0
    }
}
