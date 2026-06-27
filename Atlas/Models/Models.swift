import SwiftUI

/// A top-level life bucket (School / Personal / Side Project …).
struct Space: Identifiable {
    var id = UUID()
    var name: String
    var color: Color
    var projects: [Project]
}

/// A project inside a Space. In the School space, projects are Classes.
struct Project: Identifiable {
    var id = UUID()
    var name: String
    var code: String?          // e.g. "CS 201"
    var isClass: Bool
    var spaceName: String
    var spaceColor: Color
    var meetingInfo: String?   // e.g. "MWF · Tech Hall 204"
    var instructor: String?
    var canvasSynced: Bool = false
    var overview: String = ""
    var assignments: [TaskItem] = []
    var notes: [NoteRef] = []
    var pinned: [PinnedResource] = []
    var backlinks: [Backlink] = []
}

/// A calendar event — the single source of truth shared by the Dashboard
/// schedule and the Calendar screen. Backed by real `Date`s so the Calendar
/// can lay it out on a time grid and so drag-to-schedule has something concrete.
struct CalendarEvent: Identifiable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var start: Date
    var end: Date
    var color: Color
    var spaceName: String
    var notes: String? = nil
    var isAllDay: Bool = false
    var projectID: UUID? = nil
    /// True for events sourced externally (e.g. Apple Calendar). Read-only: never persisted, never edited.
    var isReadOnly: Bool = false

    /// "9 AM" / "6:30 PM" — start time formatted for compact rows.
    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.component(.minute, from: start) == 0 ? "h a" : "h:mm a"
        return f.string(from: start)
    }

    /// "1h 15m" / "1h" / "45m" — human duration.
    var durationLabel: String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

/// A task / to-do. `scheduledAt` is nil until it's dragged onto the calendar.
struct TaskItem: Identifiable {
    var id = UUID()
    var title: String
    var dueLabel: String
    var status: TaskStatus = .open
    var done: Bool = false
    var scheduledAt: Date? = nil
    var dueDate: Date? = nil
    var durationMin: Int? = nil
    var spaceColor: Color = AtlasTheme.Colors.accent
    var spaceName: String = ""
}

extension TaskItem {
    /// Short, human due label derived from a date. Deterministic given `now`.
    /// "" for nil; "Today"/"Tomorrow"; weekday ("Thu") within a week; else "MMM d".
    static func dueLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: date)).day ?? 0
        let f = DateFormatter()
        f.dateFormat = (days > 1 && days < 7) ? "EEE" : "MMM d"
        return f.string(from: date)
    }
}

enum TaskStatus {
    case open, dueSoon, upcoming, submitted
}

/// A long-term goal with progress.
struct Goal: Identifiable {
    var id = UUID()
    var title: String
    var progress: Double       // 0...1
    var label: String          // e.g. "2 / 3 this week"
}

/// A note reference attached to a project.
struct NoteRef: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var isExternal: Bool = false   // Google Doc, etc.
}

/// A full note with an editable body — the source of truth for the Notes editor
/// and ⌘K search. Attachable to a space/project; `[[mentions]]` create backlinks.
struct Note: Identifiable {
    var id = UUID()
    var title: String
    var body: String
    var spaceName: String? = nil
    var updatedAt: Date = Date()
    var isExternal: Bool = false   // links out to a Google Doc / Apple Note
}

/// A pinned external resource (paste-a-URL: repo, video, playlist).
struct PinnedResource: Identifiable {
    let id = UUID()
    var title: String
    var source: String
    var systemImage: String
}

/// A backlink — something elsewhere that references this item.
struct Backlink: Identifiable {
    let id = UUID()
    var title: String
    var meta: String
    var color: Color
}
