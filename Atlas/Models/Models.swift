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

/// Where a `CalendarEvent` originated. Drives the source label and edit affordances —
/// attribution is set ONCE at ingest, never guessed from other fields.
enum EventSource {
    case atlas      // app-owned, writable
    case apple      // Apple Calendar (EventKit)
    case google     // Google Calendar

    /// Human label for the source (e.g. the read-only menu row).
    var displayName: String {
        switch self {
        case .atlas:  return "Atlas"
        case .apple:  return "Apple Calendar"
        case .google: return "Google Calendar"
        }
    }
}

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
    /// Optional link to a Note — lets a calendar item be "tagged" to a note from the detail
    /// view. Durable only for Atlas events + work-blocks (external events aren't persisted).
    var noteID: UUID? = nil
    /// True for events sourced externally (e.g. Apple Calendar). Read-only: never persisted, never edited.
    var isReadOnly: Bool = false
    /// Where this event came from. Stamped at ingest (`.apple`/`.google`) or `.atlas`
    /// for app-owned events — drives the correct source label. Never inferred.
    var source: EventSource = .atlas

    /// The backing Google Calendar event id, set after a successful write-back (or at
    /// ingest for Google-origin events) so later edits/deletes target the same Google
    /// event. Persisted via migration 0003 (`events.google_event_id`), so edits after a
    /// relaunch patch the same event instead of duplicating it.
    var googleEventId: String? = nil

    /// True for an expanded instance of a recurring Google event. Recurring instances stay
    /// read-only in Atlas until series editing lands (Phase 3); one-off events edit two-way.
    var isRecurring: Bool = false

    /// True when this tile is a work-block synthesized from a scheduled task (drag-to-
    /// schedule) rather than a first-class event — drives the provisional "planned work"
    /// styling (translucent, dashed, with a checkbox) so it reads as a plan, not a commitment.
    var isWorkBlock: Bool = false

    /// True when this is a deadline marker synthesized from a task's `dueDate` — rendered as
    /// a flag-pill in the deadline strip (never as a time block), red when overdue. Atlas-only;
    /// deadlines are never pushed to Google.
    var isDeadline: Bool = false

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
    /// Free-text description, editable from the detail view (a task — and its work-block
    /// visualization — is what carries a description).
    var notes: String? = nil
    /// Optional link to a Note, set from the detail view's "tag to a note".
    var noteID: UUID? = nil
    /// Google event id backing this task's scheduled work-block, set after it mirrors to
    /// Google so a reschedule patches the same event. In-memory this build (no TaskRow
    /// column yet) — a relaunch re-creates rather than patches.
    var workBlockGoogleEventId: String? = nil
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

    /// Non-destructive "resurface" rule for the unscheduled tray.
    ///
    /// True when the task has no slot (`scheduledAt == nil`), OR when its slot
    /// has fully elapsed (`scheduledAt + durationMin·60 < now`) and it's still
    /// open (`!done`). A completed task never resurfaces; a future slot stays
    /// scheduled. The schedule is never mutated — the task simply re-appears in
    /// the tray (and drops off the grid) once its window passes.
    func isEffectivelyUnscheduled(now: Date = Date()) -> Bool {
        guard let at = scheduledAt else { return true }
        if done { return false }
        let end = at.addingTimeInterval(TimeInterval((durationMin ?? 60) * 60))
        return end < now
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
    /// The project this note belongs to (WS-10 native linking). Drives the per-
    /// project Notes list and, later, the per-project Google Drive folder that
    /// holds this note's backing Doc. `nil` for loose / space-level notes.
    var projectID: UUID? = nil
    var updatedAt: Date = Date()
    var isExternal: Bool = false   // links out to a Google Doc / Apple Note

    /// The backing Google Doc id, once this note is linked (WS-10). `nil` until
    /// the note is paired with a Doc. The Doc is the styling master; Atlas edits
    /// the constrained subset (see `RichDoc`).
    var googleDocId: String? = nil
    /// When the note last reconciled with its Google Doc — drives last-write
    /// reconciliation (`NoteSync.reconcile`) so neither side is silently lost.
    var docSyncedAt: Date? = nil
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
