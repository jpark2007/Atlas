import SwiftUI

/// A top-level life bucket (School / Personal / Side Project …).
struct Space: Identifiable {
    let id = UUID()
    var name: String
    var color: Color
    var projects: [Project]
}

/// A project inside a Space. In the School space, projects are Classes.
struct Project: Identifiable {
    let id = UUID()
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

/// A schedule block shown on the dashboard / calendar.
struct ScheduleEntry: Identifiable {
    let id = UUID()
    var time: String
    var title: String
    var subtitle: String
    var duration: String
    var color: Color
}

/// A task / to-do.
struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
    var dueLabel: String
    var status: TaskStatus = .open
    var done: Bool = false
}

enum TaskStatus {
    case open, dueSoon, upcoming, submitted
}

/// A long-term goal with progress.
struct Goal: Identifiable {
    let id = UUID()
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
