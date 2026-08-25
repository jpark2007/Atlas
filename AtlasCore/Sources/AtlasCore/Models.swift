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

// MARK: - School framework (Term → Class)

/// Day-precision codec for the School framework's `date` columns (`terms.starts_on`,
/// `terms.ends_on`, key-date days). Postgres `date` values travel as 'YYYY-MM-DD',
/// which the app's iso8601 JSON codec can't read — so these columns are carried as
/// strings on the wire and bridged here. Dates land at LOCAL midnight, matching how
/// the rest of the app reasons about "today".
public enum TermDay {
    public static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func date(from string: String) -> Date? { formatter.date(from: string) }
    public static func string(from date: Date) -> String { formatter.string(from: date) }
}

/// What a Key Date flags, so the calendar can render it correctly. Unknown values
/// decode as `.other` — a flag added by a later client must never fail a decode.
public enum TermKeyDateKind: String, Codable, Equatable {
    case classesBegin = "classes_begin"
    case classesEnd   = "classes_end"
    case addDrop      = "add_drop"
    case holiday
    case breakPeriod  = "break"     // `break` is a Swift keyword
    case finals
    case deadline
    case other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TermKeyDateKind(rawValue: raw) ?? .other
    }
}

/// One entry in a term's Key Dates (classes begin, add/drop deadline, a holiday,
/// spring break…). Stored inside `terms.key_dates` jsonb as `{label, date, kind?}`;
/// `date` is encoded day-precision, independent of the ambient JSON date strategy.
public struct TermKeyDate: Codable, Equatable {
    public var label: String
    public var date: Date
    public var kind: TermKeyDateKind?

    public init(label: String, date: Date, kind: TermKeyDateKind? = nil) {
        self.label = label
        self.date = date
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey { case label, date, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        let day = try c.decode(String.self, forKey: .date)
        guard let parsed = TermDay.date(from: day) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c,
                debugDescription: "Key date is not YYYY-MM-DD: \(day)")
        }
        date = parsed
        kind = try c.decodeIfPresent(TermKeyDateKind.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(TermDay.string(from: date), forKey: .date)
        try c.encodeIfPresent(kind, forKey: .kind)
    }
}

/// A school term ("Fall 2026") — the first-class object classes hang off. The app
/// filters School by the active term; ending a term soft-archives its classes
/// (nothing is ever wiped). Dates are optional: a migrated account has classes
/// before it has term dates, and the UI asks for them once.
public struct Term: Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var startsOn: Date?
    public var endsOn: Date?
    /// Registrar dates rendered as flags on the calendar (see `TermKeyDate`).
    public var keyDates: [TermKeyDate] = []

    public init(id: UUID = UUID(), name: String, startsOn: Date? = nil, endsOn: Date? = nil,
                keyDates: [TermKeyDate] = []) {
        self.id = id
        self.name = name
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.keyDates = keyDates
    }

    /// True when `day` falls inside this term. A term missing either date contains
    /// nothing — an undated term is "not yet dated", not "always current".
    public func contains(_ day: Date) -> Bool {
        guard let startsOn, let endsOn else { return false }
        let d = Calendar.current.startOfDay(for: day)
        return d >= Calendar.current.startOfDay(for: startsOn)
            && d <= Calendar.current.startOfDay(for: endsOn)
    }
}

/// Picking the term the app should be showing. Pure, so it's testable without a DB.
public enum TermSelection {
    /// The term to treat as active: the one containing `date`, else the most recent
    /// term that has already begun, else the next upcoming one, else any term at all.
    /// Undated terms only ever win when nothing else does.
    public static func active(in terms: [Term], on date: Date = Date()) -> Term? {
        guard !terms.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: date)

        if let containing = terms.first(where: { $0.contains(today) }) { return containing }

        // Most recent begun term — ranked by when it ended (or started, if undated end).
        let begun = terms.filter { ($0.startsOn ?? .distantFuture) <= today }
        if let mostRecent = begun.max(by: { rank($0) < rank($1) }) { return mostRecent }

        // Nothing has begun: the soonest upcoming term.
        let upcoming = terms.compactMap { t -> (Term, Date)? in
            guard let s = t.startsOn, s > today else { return nil }
            return (t, s)
        }
        if let next = upcoming.min(by: { $0.1 < $1.1 })?.0 { return next }

        return terms.first  // wholly undated
    }

    private static func rank(_ t: Term) -> Date { t.endsOn ?? t.startsOn ?? .distantPast }
}

/// One structured meeting block of a class ("MWF 10:00–10:50, Tech Hall 204").
/// Stored in `projects.meeting_pattern` jsonb as an array of these. Whatever door
/// the schedule came through (school ICS, an existing calendar, a screenshot scan,
/// manual entry) lands here, and the calendar draws these.
///
/// Rotation timetables (A/B days) are deliberately NOT built — the shape merely
/// leaves room: a block is an open JSON object, so a later `rotation_day` key is
/// additive and older clients ignore it.
public struct MeetingBlock: Codable, Equatable {
    /// 1 = Sunday … 7 = Saturday (Foundation's `Calendar` weekday numbering), so a
    /// block covers "MWF" without three near-duplicate entries.
    public var weekdays: [Int]
    /// Local wall-clock "HH:mm" — a meeting is 10:00 in the school's day, not an instant.
    public var start: String
    public var end: String
    public var location: String?
    /// The first day this block actually meets, when the schedule said so — an `.ics`
    /// import carries the earliest DTSTART among the occurrences it folded. `nil` for a
    /// pattern with no start of its own (typed by hand, or scanned from a syllabus):
    /// that one is bounded only by the term, which is the behavior it has always had.
    public var firstDate: Date?
    /// The last day this block meets: the latest occurrence a spelled-out file listed,
    /// or the weekly rule's UNTIL when it named one. `nil` ⇒ bounded by the term's end.
    public var lastDate: Date?

    public init(weekdays: [Int], start: String, end: String, location: String? = nil,
                firstDate: Date? = nil, lastDate: Date? = nil) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
        self.location = location
        self.firstDate = firstDate
        self.lastDate = lastDate
    }

    enum CodingKeys: String, CodingKey { case weekdays, start, end, location, firstDate, lastDate }

    /// Both dates decode `IfPresent`, so a class created before this shape existed reads
    /// back with no dates and stays term-bounded — no migration, nothing to backfill.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekdays  = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        start     = try c.decode(String.self, forKey: .start)
        end       = try c.decode(String.self, forKey: .end)
        location  = try c.decodeIfPresent(String.self, forKey: .location)
        firstDate = try c.decodeIfPresent(Date.self, forKey: .firstDate)
        lastDate  = try c.decodeIfPresent(Date.self, forKey: .lastDate)
    }
}

/// The "Class info" card a syllabus scan produces — static display strings shown on
/// the class page. Explicitly NOT grades tracking: these are the syllabus's own words
/// (weight bullets, policy notes, office hours), never computed.
public struct ClassInfoCard: Codable, Equatable {
    public var gradeWeights: [String]
    public var policies: [String]
    public var officeHours: String?

    public init(gradeWeights: [String] = [], policies: [String] = [], officeHours: String? = nil) {
        self.gradeWeights = gradeWeights
        self.policies = policies
        self.officeHours = officeHours
    }

    enum CodingKeys: String, CodingKey {
        case gradeWeights = "grade_weights"
        case policies
        case officeHours  = "office_hours"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gradeWeights = try c.decodeIfPresent([String].self, forKey: .gradeWeights) ?? []
        policies     = try c.decodeIfPresent([String].self, forKey: .policies) ?? []
        officeHours  = try c.decodeIfPresent(String.self,   forKey: .officeHours)
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
    /// This project's own color token (school/personal/side/accent) — the same
    /// token set spaces use. `nil` means "inherit the parent space's color"
    /// (the default). Only DAY-GRID event/work blocks wear it; month dots,
    /// chips, sidebar and routing keep the space color. Persisted via 0031.
    public var colorToken: String? = nil
    /// The Canvas course this class is explicitly linked to (migration 0032). When set,
    /// canvas-sync files that course's future items under this project, and the client
    /// remaps already-imported items here at link time. `nil` = not linked; routing then
    /// falls back to the auto code/name match. The label matches `TaskItem.canvasCourse`.
    public var canvasCourse: String? = nil
    public var assignments: [TaskItem] = []
    public var notes: [NoteRef] = []
    public var pinned: [PinnedResource] = []
    public var backlinks: [Backlink] = []
    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil
    /// The `Term` this class belongs to (migration 0042). A class belongs to exactly one
    /// term; `nil` on a class means "not dated yet" (an existing class awaiting the
    /// one-time term prompt). Always `nil` for non-class projects.
    public var termID: UUID? = nil
    /// Soft archive (0042). Set when a term ends: the class drops out of the active
    /// view but its tasks and notes stay queryable — never wiped. `nil` = active.
    public var archivedAt: Date? = nil
    /// Structured meeting blocks (0042). Empty ⇒ the class has no known schedule yet;
    /// free-text `meetingInfo` survives only as an optional note.
    public var meetingPattern: [MeetingBlock] = []
    /// The syllabus-scan "Class info" card (0042); `nil` until a syllabus is scanned.
    public var classInfo: ClassInfoCard? = nil

    public init(id: UUID = UUID(), name: String, code: String? = nil, isClass: Bool, spaceName: String, spaceColor: Color, meetingInfo: String? = nil, instructor: String? = nil, canvasSynced: Bool = false, overview: String = "", colorToken: String? = nil, canvasCourse: String? = nil, assignments: [TaskItem] = [], notes: [NoteRef] = [], pinned: [PinnedResource] = [], backlinks: [Backlink] = [], spaceID: UUID? = nil, termID: UUID? = nil, archivedAt: Date? = nil, meetingPattern: [MeetingBlock] = [], classInfo: ClassInfoCard? = nil) {
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
        self.colorToken = colorToken
        self.canvasCourse = canvasCourse
        self.assignments = assignments
        self.notes = notes
        self.pinned = pinned
        self.backlinks = backlinks
        self.spaceID = spaceID
        self.termID = termID
        self.archivedAt = archivedAt
        self.meetingPattern = meetingPattern
        self.classInfo = classInfo
    }
}

/// A calendar event — the single source of truth shared by the Dashboard
/// schedule and the Calendar screen. Backed by real `Date`s so the Calendar
/// can lay it out on a time grid and so drag-to-schedule has something concrete.

/// Where a `CalendarEvent` originated. Drives the source label and edit affordances —
/// attribution is set ONCE at ingest, never guessed from other fields.
public enum EventSource: Equatable {
    case atlas               // app-owned, writable
    case apple               // Apple Calendar (EventKit)
    case google              // Google Calendar
    case canvas              // Canvas LMS (ICS feed) — server-owned, read-only in Atlas
    case icsFeed(name: String) // a generic subscribed ICS calendar feed — server-owned, read-only
                               // in Atlas. `name` is the feed's display name (never "Canvas" — a
                               // Schoology feed must label as itself, rule 5).

    /// Human label for the source (e.g. the read-only menu row).
    public var displayName: String {
        switch self {
        case .atlas:  return "Atlas"
        case .apple:  return "Apple Calendar"
        case .google: return "Google Calendar"
        case .canvas: return "Canvas"
        case .icsFeed(let name): return name
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

    /// The backing Apple Calendar `eventIdentifier`, set after this event is mirrored to
    /// Apple Calendar (Track C write-back) so later edits/deletes target the same EKEvent.
    /// Persisted via migration 0026 (`events.apple_event_id`). Best-effort continuity only:
    /// EventKit identifiers are per-device and the Mac is the sole EventKit device, so this
    /// mirror id is meaningful only there. `nil` until the event is written to Apple.
    public var appleEventId: String? = nil

    /// True for an expanded instance of a recurring Google event. Recurring instances stay
    /// read-only in Atlas until series editing lands (Phase 3); one-off events edit two-way.
    public var isRecurring: Bool = false

    /// True when this tile is a work-block synthesized from a scheduled task (drag-to-
    /// schedule) rather than a first-class event — drives the provisional "planned work"
    /// styling (translucent, dashed, with a checkbox) so it reads as a plan, not a commitment.
    public var isWorkBlock: Bool = false

    /// True when this is a deadline marker synthesized from a task's `dueDate` — rendered as
    /// a hairline due-marker on the grid (never as a time block). Atlas-only; deadlines are
    /// never pushed to Google.
    public var isDeadline: Bool = false

    /// The task a synthesized marker/work-session belongs to. Set on deadline markers (whose
    /// own `id` is a stable hash, not the task's) so the deadline↔work-session link can find
    /// the task's planned time. `nil` for real events.
    public var deadlineTaskID: UUID? = nil

    /// True when this tile is *history*: a work session whose task is already checked off, or
    /// a faded marker at a late item's ORIGINAL due date after it was rescheduled. History
    /// renders faded and is never interactive — proof of what happened, not a plan.
    public var isHistory: Bool = false

    /// The parent space's id — authoritative once set; the name remains for display.
    public var spaceID: UUID? = nil

    /// Which Google account (connection) this event routes OUT to, resolved from its
    /// space at write time (multi-account, migration 0028). Nil ⇒ the event's space is
    /// linked to no Google account, so it stays in Atlas. The server's per-connection
    /// push reads this to know which account to mirror to. Round-tripped via `EventRow`.
    public var googleConnectionId: UUID? = nil

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

    /// True when this read-only tile should render in the neutral external-grey used
    /// for Apple/Google calendar items that carry no Atlas identity of their own.
    /// Canvas items are read-only too, but they belong to a real Atlas space (and,
    /// when mapped to a class, a project), so they keep their space/project color —
    /// a Canvas tile must never masquerade as a neutral external event (rule 5).
    ///
    /// A `projectID` is the same kind of Atlas identity: a class meeting synthesized from
    /// a class's pattern, an imported exam tied to its class, or any tile the user filed
    /// under a project wears THAT project's color (see `AppState.gridColored`), read-only
    /// or not. Neutral grey is only for a read-only tile that belongs to nothing in Atlas.
    public var rendersNeutral: Bool { isReadOnly && source != .canvas && projectID == nil }

    /// The Canvas course label this item came from (migration 0032) — the SUMMARY's
    /// trailing "[…]" bracket parsed at ingest, `nil` for non-Canvas events. Read-only
    /// on the client (Canvas events are never upserted back); drives the class-link
    /// picker and the retroactive course→class remap.
    public var canvasCourse: String? = nil

    /// The sources of the duplicate copies hidden behind this event by
    /// `CalendarSync.collapsingDuplicates` — empty for every event that wasn't a dedup
    /// winner. Display-time only (never persisted); drives the detail view's "also in …"
    /// note. Each entry is the loser's own ingest-stamped source, never a guessed label.
    public var duplicateSources: [EventSource] = []

    public init(id: UUID = UUID(), title: String, subtitle: String, start: Date, end: Date, color: Color, spaceName: String, notes: String? = nil, isAllDay: Bool = false, projectID: UUID? = nil, noteID: UUID? = nil, isReadOnly: Bool = false, source: EventSource = .atlas, googleEventId: String? = nil, appleEventId: String? = nil, isRecurring: Bool = false, isWorkBlock: Bool = false, isDeadline: Bool = false, deadlineTaskID: UUID? = nil, isHistory: Bool = false, spaceID: UUID? = nil, googleConnectionId: UUID? = nil) {
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
        self.appleEventId = appleEventId
        self.isRecurring = isRecurring
        self.isWorkBlock = isWorkBlock
        self.isDeadline = isDeadline
        self.deadlineTaskID = deadlineTaskID
        self.isHistory = isHistory
        self.spaceID = spaceID
        self.googleConnectionId = googleConnectionId
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
    /// Optional user estimate of how much TOTAL time this task needs, in minutes (migration
    /// 0041 `tasks.estimate_min`). Distinct from `durationMin`, which is the length of the
    /// one planned work session. Drives the due marker's "2.5 of 4h planned" fill; with no
    /// estimate the marker falls back to "N sessions planned".
    public var estimateMin: Int? = nil
    /// The due date this task carried BEFORE it was rescheduled off the Late bar (migration
    /// 0041 `tasks.original_due_date`). Set once, on the first late-reschedule, and never
    /// overwritten — the original date keeps a faded marker in the past so nothing about
    /// the miss silently vanishes. `nil` for tasks that were never rescheduled while late.
    public var originalDueDate: Date? = nil
    /// Optional link to a Note, set from the detail view's "tag to a note".
    public var noteID: UUID? = nil
    /// Google event id backing this task's scheduled work-block, set after it mirrors to
    /// Google so a reschedule patches the same event. In-memory this build (no TaskRow
    /// column yet) — a relaunch re-creates rather than patches.
    public var workBlockGoogleEventId: String? = nil
    /// Apple Calendar `eventIdentifier` backing this task's scheduled work-block, set after
    /// it mirrors to Apple (Track C) so a reschedule patches the same EKEvent. Persisted via
    /// migration 0026 (`tasks.apple_event_id`). Best-effort continuity only: EventKit ids are
    /// per-device and the Mac is the sole EventKit device. `nil` until the block is mirrored.
    public var appleEventId: String? = nil
    public var spaceColor: Color = AtlasTheme.Colors.accent
    public var spaceName: String = ""
    /// The project (a CLASS, in School) this task is filed under — the AUTHORITATIVE
    /// link, persisted as `tasks.project_id`. `projectName` below is the denormalized
    /// display copy, re-derived from this id on every snapshot load; before this id
    /// existed the name lived only in memory and every save silently dropped the class.
    public var projectID: UUID? = nil
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
    /// The Canvas course label this assignment came from (migration 0032) — the
    /// SUMMARY's trailing "[…]" bracket parsed at ingest, `nil` for non-Canvas tasks.
    /// Drives the class-link picker and the course→class remap. Round-trips through
    /// `TaskRow` so a client edit never nulls it.
    public var canvasCourse: String? = nil
    /// The `calendar_feeds` row this task was ingested from (multi-ICS feeds), or nil for
    /// Atlas-native tasks. Round-trips through `TaskRow` so a client edit never nulls it.
    public var feedID: UUID? = nil
    /// The feed's type — "canvas" or "ics" (multi-ICS feeds), or nil for Atlas-native
    /// tasks. Lets the UI label the source correctly: `canvasUID` alone no longer implies
    /// Canvas (it now doubles as the generic ICS UID), so an "ics" task must NOT read as
    /// "Canvas" (rule 5). Round-trips through `TaskRow`.
    public var feedType: String? = nil

    public init(id: UUID = UUID(), title: String, dueLabel: String, status: TaskStatus = .open, done: Bool = false, completedAt: Date? = nil, scheduledAt: Date? = nil, dueDate: Date? = nil, durationMin: Int? = nil, noteID: UUID? = nil, workBlockGoogleEventId: String? = nil, appleEventId: String? = nil, spaceColor: Color = AtlasTheme.Colors.accent, spaceName: String = "", projectName: String = "", notes: String = "", spaceID: UUID? = nil, assigneeID: UUID? = nil, createdByID: UUID? = nil, canvasUID: String? = nil) {
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
        self.appleEventId = appleEventId
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
