import SwiftUI

/// A top-level life bucket (School / Personal / Side Project …).
public struct Space: Identifiable {
    public var id = UUID()
    public var name: String
    public var color: Color
    public var projects: [Project]

    public init(id: UUID = UUID(), name: String, color: Color, projects: [Project]) {
        self.id = id
        self.name = name
        self.color = color
        self.projects = projects
    }
}

/// A project inside a Space. In the School space, projects are Classes.
public struct Project: Identifiable {
    public var id = UUID()
    public var name: String
    public var code: String?          // e.g. "CS 201"
    public var isClass: Bool
    public var spaceName: String
    public var spaceColor: Color
    public var meetingInfo: String?   // e.g. "MWF · Tech Hall 204"
    public var instructor: String?
    public var canvasSynced: Bool = false
    public var overview: String = ""
    public var assignments: [TaskItem] = []
    public var notes: [NoteRef] = []
    public var pinned: [PinnedResource] = []
    public var backlinks: [Backlink] = []
    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil

    public init(id: UUID = UUID(), name: String, code: String? = nil, isClass: Bool, spaceName: String, spaceColor: Color, meetingInfo: String? = nil, instructor: String? = nil, canvasSynced: Bool = false, overview: String = "", assignments: [TaskItem] = [], notes: [NoteRef] = [], pinned: [PinnedResource] = [], backlinks: [Backlink] = [], spaceID: UUID? = nil) {
        self.id = id
        self.name = name
        self.code = code
        self.isClass = isClass
        self.spaceName = spaceName
        self.spaceColor = spaceColor
        self.meetingInfo = meetingInfo
        self.instructor = instructor
        self.canvasSynced = canvasSynced
        self.overview = overview
        self.assignments = assignments
        self.notes = notes
        self.pinned = pinned
        self.backlinks = backlinks
        self.spaceID = spaceID
    }
}

/// A calendar event — the single source of truth shared by the Dashboard
/// schedule and the Calendar screen. Backed by real `Date`s so the Calendar
/// can lay it out on a time grid and so drag-to-schedule has something concrete.

/// Where a `CalendarEvent` originated. Drives the source label and edit affordances —
/// attribution is set ONCE at ingest, never guessed from other fields.
public enum EventSource {
    case atlas      // app-owned, writable
    case apple      // Apple Calendar (EventKit)
    case google     // Google Calendar
    case canvas     // Canvas LMS (ICS feed) — server-owned, read-only in Atlas

    /// Human label for the source (e.g. the read-only menu row).
    public var displayName: String {
        switch self {
        case .atlas:  return "Atlas"
        case .apple:  return "Apple Calendar"
        case .google: return "Google Calendar"
        case .canvas: return "Canvas"
        }
    }
}

public struct CalendarEvent: Identifiable {
    public var id: UUID = UUID()
    public var title: String
    public var subtitle: String
    public var start: Date
    public var end: Date
    public var color: Color
    public var spaceName: String
    public var notes: String? = nil
    public var isAllDay: Bool = false
    public var projectID: UUID? = nil
    /// Optional link to a Note — lets a calendar item be "tagged" to a note from the detail
    /// view. Durable only for Atlas events + work-blocks (external events aren't persisted).
    public var noteID: UUID? = nil
    /// True for events sourced externally (e.g. Apple Calendar). Read-only: never persisted, never edited.
    public var isReadOnly: Bool = false
    /// Where this event came from. Stamped at ingest (`.apple`/`.google`) or `.atlas`
    /// for app-owned events — drives the correct source label. Never inferred.
    public var source: EventSource = .atlas

    /// The backing Google Calendar event id, set after a successful write-back (or at
    /// ingest for Google-origin events) so later edits/deletes target the same Google
    /// event. Persisted via migration 0003 (`events.google_event_id`), so edits after a
    /// relaunch patch the same event instead of duplicating it.
    public var googleEventId: String? = nil

    /// True for an expanded instance of a recurring Google event. Recurring instances stay
    /// read-only in Atlas until series editing lands (Phase 3); one-off events edit two-way.
    public var isRecurring: Bool = false

    /// True when this tile is a work-block synthesized from a scheduled task (drag-to-
    /// schedule) rather than a first-class event — drives the provisional "planned work"
    /// styling (translucent, dashed, with a checkbox) so it reads as a plan, not a commitment.
    public var isWorkBlock: Bool = false

    /// True when this is a deadline marker synthesized from a task's `dueDate` — rendered as
    /// a flag-pill in the deadline strip (never as a time block), red when overdue. Atlas-only;
    /// deadlines are never pushed to Google.
    public var isDeadline: Bool = false

    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil

    /// "9 AM" / "6:30 PM" — start time formatted for compact rows.
    public var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.component(.minute, from: start) == 0 ? "h a" : "h:mm a"
        return f.string(from: start)
    }

    /// True when `start` carries a specific clock time (not midnight) — lets a deadline pill
    /// show "5:00 PM" instead of a bare all-day "due today".
    public var hasSpecificTime: Bool {
        let cal = Calendar.current
        return cal.component(.hour, from: start) != 0 || cal.component(.minute, from: start) != 0
    }

    /// "1h 15m" / "1h" / "45m" — human duration.
    public var durationLabel: String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    public init(id: UUID = UUID(), title: String, subtitle: String, start: Date, end: Date, color: Color, spaceName: String, notes: String? = nil, isAllDay: Bool = false, projectID: UUID? = nil, noteID: UUID? = nil, isReadOnly: Bool = false, source: EventSource = .atlas, googleEventId: String? = nil, isRecurring: Bool = false, isWorkBlock: Bool = false, isDeadline: Bool = false, spaceID: UUID? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.start = start
        self.end = end
        self.color = color
        self.spaceName = spaceName
        self.notes = notes
        self.isAllDay = isAllDay
        self.projectID = projectID
        self.noteID = noteID
        self.isReadOnly = isReadOnly
        self.source = source
        self.googleEventId = googleEventId
        self.isRecurring = isRecurring
        self.isWorkBlock = isWorkBlock
        self.isDeadline = isDeadline
        self.spaceID = spaceID
    }
}

/// A task / to-do. `scheduledAt` is nil until it's dragged onto the calendar.
public struct TaskItem: Identifiable {
    public var id = UUID()
    public var title: String
    public var dueLabel: String
    public var status: TaskStatus = .open
    public var done: Bool = false
    /// When the task was checked off; nil while open (and for tasks completed
    /// before this column existed — those render undated and sort oldest in
    /// completed lists).
    public var completedAt: Date? = nil
    public var scheduledAt: Date? = nil
    public var dueDate: Date? = nil
    public var durationMin: Int? = nil
    /// Optional link to a Note, set from the detail view's "tag to a note".
    public var noteID: UUID? = nil
    /// Google event id backing this task's scheduled work-block, set after it mirrors to
    /// Google so a reschedule patches the same event. In-memory this build (no TaskRow
    /// column yet) — a relaunch re-creates rather than patches.
    public var workBlockGoogleEventId: String? = nil
    public var spaceColor: Color = AtlasTheme.Colors.accent
    public var spaceName: String = ""
    public var projectName: String = ""
    public var notes: String = ""
    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil
    /// Who this shared task is assigned to, if anyone. Nil = unclaimed, up for
    /// grabs. Meaningless for non-shared (personal) tasks.
    public var assigneeID: UUID? = nil
    /// Who created this task — set once at creation, never changed.
    public var createdByID: UUID? = nil
    /// The Canvas assignment id backing this task, stamped at ingest for tasks that
    /// came from a Canvas ICS feed (migration 0012 `tasks.canvas_uid`). Non-nil ⇒ a
    /// Canvas assignment: its title + due date are Canvas-owned (sync overwrites them
    /// each tick), though the task stays locally completable/schedulable. Round-trips
    /// through `TaskRow` so a client edit never nulls the column. `nil` for Atlas-native.
    public var canvasUID: String? = nil

    public init(id: UUID = UUID(), title: String, dueLabel: String, status: TaskStatus = .open, done: Bool = false, completedAt: Date? = nil, scheduledAt: Date? = nil, dueDate: Date? = nil, durationMin: Int? = nil, noteID: UUID? = nil, workBlockGoogleEventId: String? = nil, spaceColor: Color = AtlasTheme.Colors.accent, spaceName: String = "", projectName: String = "", notes: String = "", spaceID: UUID? = nil, assigneeID: UUID? = nil, createdByID: UUID? = nil, canvasUID: String? = nil) {
        self.id = id
        self.title = title
        self.dueLabel = dueLabel
        self.status = status
        self.done = done
        self.completedAt = completedAt
        self.scheduledAt = scheduledAt
        self.dueDate = dueDate
        self.durationMin = durationMin
        self.noteID = noteID
        self.workBlockGoogleEventId = workBlockGoogleEventId
        self.spaceColor = spaceColor
        self.spaceName = spaceName
        self.projectName = projectName
        self.notes = notes
        self.spaceID = spaceID
        self.assigneeID = assigneeID
        self.createdByID = createdByID
        self.canvasUID = canvasUID
    }
}

extension TaskItem {
    /// True when this task has no assignee yet — the "up for grabs" state
    /// the Ledger UI renders as a hollow circle.
    public var isClaimable: Bool { assigneeID == nil }

    /// Claim an unassigned task. No-op if someone already claimed it first —
    /// callers must not silently steal another member's claimed task.
    public mutating func claim(by userId: UUID) {
        guard isClaimable else { return }
        assigneeID = userId
    }
}

extension TaskItem {
    /// Short, human due label derived from a date. Deterministic given `now`.
    /// "" for nil; "Today"/"Tomorrow"; weekday ("Thu") within a week; else "MMM d".
    /// A non-midnight time is appended ("Today 5:30 PM") — local midnight means
    /// the deadline is date-only, so no time is shown.
    public static func dueLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        let day: String
        if cal.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
                cal.isDate(date, inSameDayAs: tomorrow) { day = "Tomorrow" }
        else {
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: date)).day ?? 0
            let f = DateFormatter()
            f.dateFormat = (days > 1 && days < 7) ? "EEE" : "MMM d"
            day = f.string(from: date)
        }
        let c = cal.dateComponents([.hour, .minute], from: date)
        guard c.hour != 0 || c.minute != 0 else { return day }
        let t = DateFormatter()
        t.dateFormat = c.minute == 0 ? "h a" : "h:mm a"
        return "\(day) \(t.string(from: date))"
    }

    /// True only when the task has never been given a calendar slot. Once scheduled it
    /// stays on the grid (and out of the tray) until explicitly marked done — an elapsed
    /// slot does NOT make a task "unscheduled" again; it stays put, rendered as passed.
    public var isEffectivelyUnscheduled: Bool {
        scheduledAt == nil
    }

    /// True when this task has a due date that has already passed and it isn't done — the
    /// "overdue" signal that turns its deadline pill (and tray chip) red.
    public func isOverdue(now: Date) -> Bool {
        dueDate != nil && dueDate! < now && !done
    }

    /// True when an overdue task's scheduled slot has ALSO elapsed — meaning the planned
    /// work time came and went without it being done. Such a block leaves the grid and
    /// returns to the tray to be re-planned. Gating on the slot having elapsed is what lets
    /// a user re-drag an overdue task to a FUTURE slot and have it stay on the grid (the new
    /// slot hasn't elapsed yet), instead of instantly bouncing back to the tray.
    public func needsReplan(now: Date) -> Bool {
        guard isOverdue(now: now), let at = scheduledAt else { return false }
        let slotEnd = at.addingTimeInterval(Double(durationMin ?? 60) * 60)
        return slotEnd < now
    }
}

public enum TaskStatus {
    case open, dueSoon, upcoming, submitted
}

/// A long-term goal with progress.
public struct Goal: Identifiable {
    public var id = UUID()
    public var title: String
    public var progress: Double       // 0...1
    public var label: String          // e.g. "2 / 3 this week"
}

/// A note reference attached to a project.
public struct NoteRef: Identifiable {
    public let id = UUID()
    public var title: String
    public var subtitle: String
    public var isExternal: Bool = false   // Google Doc, etc.
}

/// A full note with an editable body — the source of truth for the Notes editor
/// and ⌘K search. Attachable to a space/project; `[[mentions]]` create backlinks.
public struct Note: Identifiable {
    /// How `body` is encoded. Legacy native notes are literal text (`plain`);
    /// anything the rich editor saves is Markdown (`md`, the same transport form
    /// linked Doc-notes use) so headings/bold/lists persist. A plain body
    /// converts the first time it's edited — no bulk rewrite.
    public enum BodyFormat: String {
        case plain, md
    }

    public var id = UUID()
    public var title: String
    public var body: String
    public var bodyFormat: BodyFormat = .plain
    public var spaceName: String? = nil
    /// The project this note belongs to (WS-10 native linking). Drives the per-
    /// project Notes list and, later, the per-project Google Drive folder that
    /// holds this note's backing Doc. `nil` for loose / space-level notes.
    public var projectID: UUID? = nil
    public var updatedAt: Date = Date()
    public var isExternal: Bool = false   // links out to a Google Doc / Apple Note

    /// The backing Google Doc id, once this note is linked (WS-10). `nil` until
    /// the note is paired with a Doc. The Doc is the styling master; Atlas edits
    /// the constrained subset (see `RichDoc`).
    public var googleDocId: String? = nil
    /// When the note last reconciled with its Google Doc — drives last-write
    /// reconciliation (`NoteSync.reconcile`) so neither side is silently lost.
    public var docSyncedAt: Date? = nil
    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil

    public init(id: UUID = UUID(), title: String, body: String, bodyFormat: BodyFormat = .plain, spaceName: String? = nil, projectID: UUID? = nil, updatedAt: Date = Date(), isExternal: Bool = false, googleDocId: String? = nil, docSyncedAt: Date? = nil, spaceID: UUID? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.bodyFormat = bodyFormat
        self.spaceName = spaceName
        self.projectID = projectID
        self.updatedAt = updatedAt
        self.isExternal = isExternal
        self.googleDocId = googleDocId
        self.docSyncedAt = docSyncedAt
        self.spaceID = spaceID
    }
}

extension Note {
    /// The one rule for "is `body` Markdown-encoded": stamped `.md` by the rich
    /// editor, or backed by a Google Doc (a Doc-note's body is always the
    /// Markdown transport form, even where a legacy row still says `plain`).
    /// Editor parsing and previews both use this — they must never disagree.
    public var isMarkdownBody: Bool {
        bodyFormat == .md || googleDocId != nil
    }

    /// Body as displayable plain text — parses Markdown-encoded bodies so
    /// previews never leak `#`/`**` syntax; legacy plain bodies pass through.
    /// Parsing is bounded: previews show a line or two, so a huge imported Doc
    /// shouldn't be fully parsed on every list row render.
    public var previewText: String {
        isMarkdownBody ? RichDoc.fromMarkdown(String(body.prefix(600))).plainText : body
    }

    /// The FULL body as plain text (unbounded — unlike `previewText`), with
    /// Markdown escapes/marks resolved. `[[mention]]` scanning uses this: in the
    /// stored Markdown an inline mark or escape can split a mention token
    /// (`[[The**sis]]**`), which would silently drop graph backlinks.
    public var plainTextBody: String {
        isMarkdownBody ? RichDoc.fromMarkdown(body).plainText : body
    }
}

/// A pinned external resource (paste-a-URL: repo, video, playlist).
public struct PinnedResource: Identifiable {
    public let id = UUID()
    public var title: String
    public var source: String
    public var systemImage: String
}

/// A backlink — something elsewhere that references this item.
public struct Backlink: Identifiable {
    public let id = UUID()
    public var title: String
    public var meta: String
    public var color: Color
}
