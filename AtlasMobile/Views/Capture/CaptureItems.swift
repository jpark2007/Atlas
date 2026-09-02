import SwiftUI
import AtlasCore

/// A date-parsed version of a `CaptureResult` — the shape `commit` turns into a
/// real task/event. (Capture commits immediately now; this is the value that
/// travels from the parse to the commit, not something the user edits.)
struct DraftItem: Identifiable {
    let id = UUID()
    var kind: String            // "task" | "event" | "note" | "update"
    var title: String
    var spaceName: String
    var projectName: String?
    var due: Date?
    var start: Date?
    var end: Date?
    var durationMin: Int?
    var isAllDay: Bool
    var notes: String?
    var targetId: String?       // "update" only — the existing item this refers to
    var lowConfidence: Bool
    /// The repeat pattern for a recurring event, nil for a one-off. Committing expands
    /// it into one real event per session (see `CaptureView.commit`).
    var recurrence: RecurrenceRule?

    init(_ r: CaptureResult) {
        kind = r.kind
        title = r.title
        spaceName = r.spaceName
        projectName = r.projectName
        due = CaptureDateParser.date(from: r.dueISO)
        start = CaptureDateParser.date(from: r.startISO)
        end = CaptureDateParser.date(from: r.endISO)
        durationMin = r.durationMin
        isAllDay = r.isAllDay ?? false
        notes = r.notes
        targetId = r.targetId
        lowConfidence = r.isLowConfidence
        recurrence = r.recurrence.flatMap(RecurrenceRule.init(capture:))
    }
}

/// One item capture has ALREADY committed, as shown on the result sheet. The
/// chips fix it in place; Undo removes it (or, for an item capture merely
/// attached to, restores what it changed).
struct CommittedItem: Identifiable, Equatable {
    enum Kind: String { case task, event }

    /// What an UPDATED task looked like before this capture touched it.
    struct PriorState: Equatable {
        let due: Date?
        let notes: String
    }

    let id: UUID
    var kind: Kind
    var title: String
    var spaceName: String
    var projectName: String
    /// Due date for a task, start for an event.
    var date: Date?
    var lowConfidence: Bool
    /// True when the model called this a note. iOS keeps notes as tickable tasks,
    /// so the sheet says so rather than letting it look like a misfile.
    var wasNote: Bool = false
    /// Non-nil when this capture UPDATED a task the user already had, so Undo
    /// restores those values instead of deleting something they already owned.
    var prior: PriorState?

    var isUpdate: Bool { prior != nil }
}

/// What the Type chip can turn a committed item into. "Deadline" is a task that
/// carries a due date — the same way the rest of Atlas draws deadlines.
enum CaptureItemType: String, CaseIterable, Identifiable {
    case task, deadline, event
    var id: String { rawValue }

    var label: String {
        switch self {
        case .task:     return "Task"
        case .deadline: return "Deadline"
        case .event:    return "Event"
        }
    }

    static func of(_ item: CommittedItem) -> CaptureItemType {
        switch item.kind {
        case .event: return .event
        case .task:  return item.date == nil ? .task : .deadline
        }
    }
}

