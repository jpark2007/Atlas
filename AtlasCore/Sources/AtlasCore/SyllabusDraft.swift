import Foundation

/// The editable middle step of the syllabus scan: what the model returned, turned into
/// rows a review list can toggle and correct before anything is written.
///
/// Phase 1's rule is draft → review → commit. This file is the DRAFT half and is
/// deliberately pure — no AppState, no network — so the mapping (and the date parsing
/// that decides what day an assignment is due in the user's zone) is testable on its own.

/// What an accepted row becomes when it commits: a task with a due date, or an event.
public enum SyllabusDraftKind: String, Equatable, CaseIterable {
    case task
    case event

    /// The response's free-text `kind`. Anything unrecognised becomes a task — a
    /// syllabus row Atlas can't classify is still work you owe.
    public init(scanKind: String) {
        self = SyllabusDraftKind(rawValue: scanKind.lowercased()) ?? .task
    }

    public var label: String { self == .task ? "Task" : "Event" }
}

/// One assignment / exam row in the review list, editable in place.
public struct SyllabusDraftItem: Identifiable, Equatable {
    public var id = UUID()
    public var kind: SyllabusDraftKind
    public var title: String
    /// The due (task) or start (event) instant, `nil` when the syllabus's reference
    /// couldn't be grounded — the row still shows, with a blank date to fill in.
    public var date: Date?
    public var notes: String?
    /// Accept-all is the default; unchecking is how you drop a row.
    public var include: Bool = true
    /// Set by `SyllabusDedupe` when this row already exists on the target class (a Canvas
    /// assignment or an event saying the same thing on the same day). Such a row starts
    /// UNCHECKED and wears an "already in …" badge naming `existingSource` — it is never
    /// silently dropped, so the student can still accept it if the scan found the better
    /// version.
    public var alreadyExists: Bool = false
    /// Where the matched existing item actually came from, set alongside `alreadyExists`
    /// so the badge names the real avenue instead of always saying "Canvas". `nil` when
    /// the row is not a duplicate.
    public var existingSource: SyllabusMatchSource? = nil
    /// True when the syllabus named a DAY and no clock time ("Quiz 3 — Sept 24"). Recorded
    /// at parse, never guessed later: an event committed from such a row is an ALL-DAY
    /// event, because inventing midnight for it is what made a quiz read "12 AM · 1h".
    public var isDateOnly: Bool = false
    /// True when the date came from a week or a date RANGE on a schedule document
    /// ("DBQ Module 5 — Sept 28–Oct 2" → due the 2nd) rather than a day the document
    /// printed. The row is shown with an "approximate" badge so the student can correct
    /// it before it commits; nothing about the commit itself changes.
    public var dateApproximate: Bool = false

    public init(id: UUID = UUID(), kind: SyllabusDraftKind, title: String,
                date: Date? = nil, notes: String? = nil, include: Bool = true,
                alreadyExists: Bool = false, existingSource: SyllabusMatchSource? = nil,
                isDateOnly: Bool = false, dateApproximate: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.notes = notes
        self.include = include
        self.alreadyExists = alreadyExists
        self.existingSource = existingSource
        self.isDateOnly = isDateOnly
        self.dateApproximate = dateApproximate
    }

    /// Whether this row commits as an all-day event: the syllabus gave a bare day AND the
    /// student hasn't since typed a clock time into the review sheet's date picker.
    public func commitsAllDay(calendar: Calendar = .current) -> Bool {
        guard isDateOnly, let date else { return false }
        return calendar.component(.hour, from: date) == 0
            && calendar.component(.minute, from: date) == 0
    }
}

/// Everything the scan found for one detected class, plus which real class it will be
/// filed under. The target starts as the class the scan was launched from, so the common
/// case (one syllabus, open on its own class page) needs no picking.
public struct SyllabusDraftGroup: Identifiable, Equatable {
    public var id = UUID()
    public var code: String?
    public var name: String?
    public var meetingPattern: [MeetingBlock]
    public var includeMeetingPattern: Bool
    /// Which meeting rows commit, index-parallel to `meetingPattern`. A syllabus lists
    /// every section of a course and the student attends one, so the review sheet needs
    /// to turn single rows off — the group-level flag can only say "all" or "none".
    /// Kept in step with `meetingPattern` by the initializer.
    public var meetingIncluded: [Bool]
    public var classInfo: ClassInfoCard?
    public var includeClassInfo: Bool
    public var items: [SyllabusDraftItem]
    /// The class this group commits onto. `nil` ⇒ nothing here can be written yet.
    public var targetClassID: UUID?

    public init(id: UUID = UUID(), code: String? = nil, name: String? = nil,
                meetingPattern: [MeetingBlock] = [], includeMeetingPattern: Bool = true,
                meetingIncluded: [Bool] = [],
                classInfo: ClassInfoCard? = nil, includeClassInfo: Bool = true,
                items: [SyllabusDraftItem] = [], targetClassID: UUID? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.meetingPattern = meetingPattern
        self.includeMeetingPattern = includeMeetingPattern
        // A caller that says nothing about individual rows means all of them.
        self.meetingIncluded = meetingIncluded.count == meetingPattern.count
            ? meetingIncluded
            : [Bool](repeating: true, count: meetingPattern.count)
        self.classInfo = classInfo
        self.includeClassInfo = includeClassInfo
        self.items = items
        self.targetClassID = targetClassID
    }

    /// "CS 201 · Data Structures" — what the scan thinks this is, shown next to the
    /// class picker so a mis-targeted group is obvious.
    public var detectedLabel: String {
        [code, name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    public var includedItems: [SyllabusDraftItem] {
        items.filter { $0.include && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The meeting rows that actually commit.
    public var includedMeetings: [MeetingBlock] {
        meetingPattern.enumerated()
            .filter { meetingIncluded.indices.contains($0.offset) ? meetingIncluded[$0.offset] : true }
            .map(\.element)
    }

    /// Whether committing this group would write anything at all.
    public var writesAnything: Bool {
        !includedItems.isEmpty
            || (includeMeetingPattern && !includedMeetings.isEmpty)
            || (includeClassInfo && classInfo != nil)
    }

    /// The section labels the scan printed, in the order they came back. More than one
    /// means the syllabus listed several sections of the same course and only the student
    /// knows which one they're in — the review sheet asks (handoff §C1/§C8).
    public var sectionChoices: [String] {
        var seen = Set<String>()
        return meetingPattern.compactMap { block -> String? in
            guard SyllabusDraftGroup.isSectioned(block),
                  let label = block.sectionLabel?.trimmingCharacters(in: .whitespaces),
                  !label.isEmpty, seen.insert(label).inserted else { return nil }
            return label
        }
    }

    /// Keep one section: that section's rows plus every row nobody has to choose between
    /// (the lecture everyone attends, an unlabelled block). `nil` keeps them all.
    public mutating func chooseSection(_ label: String?) {
        meetingIncluded = meetingPattern.map { block in
            guard let label else { return true }
            guard SyllabusDraftGroup.isSectioned(block), let own = block.sectionLabel else { return true }
            return own.trimmingCharacters(in: .whitespaces) == label
        }
    }

    /// A row the student picks between: one that names a section AND isn't the lecture
    /// every section shares.
    private static func isSectioned(_ block: MeetingBlock) -> Bool {
        (block.sectionLabel?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            && block.kind?.lowercased() != "lecture"
    }
}

/// The shaping the review sheet does before it draws — month buckets for the work step and
/// the split of a grade-weight line into its label and its percentage. Pure, and shared so
/// Mac and iOS group and read the same scan identically.
public enum SyllabusReview {

    /// One month's worth of work in the review list. `indices` point into the group's own
    /// `items` array, so the sheet can still bind to a row and edit it in place.
    public struct MonthBucket: Identifiable, Equatable {
        public let title: String
        public let indices: [Int]
        public var id: String { title }
    }

    /// Work items in the order a semester is lived: by month, undated last.
    public static func monthBuckets(_ items: [SyllabusDraftItem],
                                    calendar: Calendar = .current) -> [MonthBucket] {
        let dated = items.enumerated().filter { $0.element.date != nil }
            .sorted { ($0.element.date ?? .distantPast) < ($1.element.date ?? .distantPast) }

        var order: [String] = []
        var buckets: [String: [Int]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"

        for entry in dated {
            guard let date = entry.element.date else { continue }
            let stamp = formatter.string(from: date)
            let thisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            let title = thisYear ? String(stamp.split(separator: " ")[0]) : stamp
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(entry.offset)
        }

        var out = order.map { MonthBucket(title: $0, indices: buckets[$0] ?? []) }
        let undated = items.enumerated().filter { $0.element.date == nil }.map(\.offset)
        if !undated.isEmpty { out.append(MonthBucket(title: "No date yet", indices: undated)) }
        return out
    }

    /// "Exams 40%" → ("Exams", "40%"). A line with no percentage keeps its whole self as
    /// the label — the syllabus's words are never rewritten, only split for layout.
    public static func weightChip(_ line: String) -> (label: String, percent: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"[0-9]+(\.[0-9]+)?\s*%"#,
                                        options: [.regularExpression, .backwards]) else {
            return (trimmed, nil)
        }
        let percent = trimmed[range].replacingOccurrences(of: " ", with: "")
        let label = (trimmed[trimmed.startIndex..<range.lowerBound] + trimmed[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·,"))
        return (label.isEmpty ? trimmed : label, percent)
    }
}

/// A second scan of a class that already has a syllabus card or a schedule. A commit
/// REPLACES those sections wholesale, so the review sheet has to say what would go and
/// let the student keep it — this is the pure half of that: what to name, and where the
/// include flags start. Shared so Mac and iOS ask the same question with the same words.
public enum SyllabusRescan {

    /// "5 weights, 3 policies, office hours" — the class info a commit would overwrite.
    /// `nil` when the class has nothing saved: there is no choice to offer.
    public static func classInfoSummary(_ info: ClassInfoCard?) -> String? {
        guard let info, !SyllabusDraft.isEmpty(info) else { return nil }
        var parts: [String] = []
        if !info.gradeWeights.isEmpty {
            parts.append("\(info.gradeWeights.count) weight\(info.gradeWeights.count == 1 ? "" : "s")")
        }
        if !info.policies.isEmpty {
            parts.append("\(info.policies.count) polic\(info.policies.count == 1 ? "y" : "ies")")
        }
        if let hours = info.officeHours, !hours.isEmpty { parts.append("office hours") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "MWF · 10 AM–10:50 AM" — the schedule a commit would overwrite, two rows at most
    /// so the line stays one line. `nil` when the class has no schedule saved.
    public static func meetingSummary(_ blocks: [MeetingBlock]) -> String? {
        guard !blocks.isEmpty else { return nil }
        let shown = blocks.prefix(2).map { MeetingPatternFormat.describe($0) }.joined(separator: ", ")
        return blocks.count > 2 ? "\(shown) +\(blocks.count - 2) more" : shown
    }

    /// Where a group's section flags start against the class it's pointed at. This is a
    /// full re-decision, not a one-way ratchet: a section the class ALREADY has starts at
    /// "keep existing" (flag off) — a rescan must never silently destroy a card the
    /// student corrected by hand. A section the class does NOT have starts back at "commit
    /// it" (flag on, when the draft actually has one to offer) — retargeting a group onto
    /// a class with nothing saved must re-enable the write the previous target's existing
    /// card had suppressed, or the scan silently drops the pattern/info it found.
    public static func keepingExisting(_ group: SyllabusDraftGroup,
                                       info: ClassInfoCard?,
                                       meetings: [MeetingBlock],
                                       meetingSource: MeetingPatternSource? = nil) -> SyllabusDraftGroup {
        var out = group
        if group.classInfo != nil {
            out.includeClassInfo = classInfoSummary(info) == nil
        }
        if !group.meetingPattern.isEmpty {
            out.includeMeetingPattern = meetingSummary(meetings) == nil
                && allowsMeetingReplacement(existingSource: meetingSource, existingMeetings: meetings)
        }
        return out
    }

    /// Whether a scan is allowed to write its meeting pattern over the one the class
    /// already has (0050). A pattern the student imported from their school's schedule
    /// (`ics`) is the authoritative one — a syllabus scan may not replace it, and the
    /// sheet says so instead of offering the choice. Everything else stays the student's
    /// call. A class with no saved pattern is never locked, whatever its stale source says.
    public static func allowsMeetingReplacement(existingSource: MeetingPatternSource?,
                                                existingMeetings: [MeetingBlock]) -> Bool {
        guard !existingMeetings.isEmpty else { return true }
        return existingSource != .ics
    }
}

public enum SyllabusDraft {

    /// How long an extracted event runs when the syllabus only states a start.
    public static let defaultEventMinutes = 60

    /// Turn a scan response into review rows, all accepted by default.
    /// `defaultTarget` is the class the scan was launched from; every group starts
    /// pointed at it and can be retargeted per group.
    public static func groups(from response: SyllabusScanResponse,
                              defaultTarget: UUID?,
                              timeZone: TimeZone = .current) -> [SyllabusDraftGroup] {
        response.classes.map { klass in
            let pattern = klass.meetingPattern ?? []
            let info = klass.classInfo.flatMap { isEmpty($0) ? nil : $0 }
            return SyllabusDraftGroup(
                code: blankToNil(klass.code),
                name: blankToNil(klass.name),
                meetingPattern: pattern,
                includeMeetingPattern: !pattern.isEmpty,
                classInfo: info,
                includeClassInfo: info != nil,
                items: klass.items.compactMap { item(from: $0, timeZone: timeZone) },
                targetClassID: defaultTarget
            )
        }
    }

    /// One response item as a review row. A row with no title is dropped: there is
    /// nothing for the user to accept or correct.
    public static func item(from scanned: SyllabusScanItem,
                            timeZone: TimeZone = .current) -> SyllabusDraftItem? {
        let title = scanned.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let kind = SyllabusDraftKind(scanKind: scanned.kind)
        // A task is dated by `dueISO`, an event by `startISO` — but the model sometimes
        // fills only the other one, so fall back rather than losing the date.
        let iso = kind == .task ? (scanned.dueISO ?? scanned.startISO)
                                : (scanned.startISO ?? scanned.dueISO)
        return SyllabusDraftItem(kind: kind,
                                 title: title,
                                 date: date(from: iso, timeZone: timeZone),
                                 notes: blankToNil(scanned.notes),
                                 // The server says so outright when it can; the string's
                                 // own shape is the fallback for an older server.
                                 isDateOnly: scanned.dateOnly ?? isDateOnly(iso),
                                 dateApproximate: scanned.dateApproximate ?? false)
    }

    /// True when the scan's ISO string names a bare calendar day — "2026-09-24" — rather
    /// than an instant. The one place "the syllabus gave no time" is decided.
    public static func isDateOnly(_ iso: String?) -> Bool {
        guard let iso = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty else {
            return false
        }
        return iso.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// Parse an ISO string from the scan. Full timestamps are absolute; a bare
    /// `YYYY-MM-DD` is the user's LOCAL day (an assignment due "Sept 15" is due on the
    /// 15th where the student is), so it resolves to midnight in `timeZone`.
    public static func date(from iso: String?, timeZone: TimeZone = .current) -> Date? {
        guard let iso = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty else {
            return nil
        }
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        // "2026-09-15T23:59" — a wall clock with no zone, meant in the school's day.
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime,
                           .withDashSeparatorInDate]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: iso)
    }

    /// The end instant an extracted event commits with, when the syllabus stated a start.
    public static func eventEnd(for start: Date) -> Date {
        start.addingTimeInterval(TimeInterval(defaultEventMinutes * 60))
    }

    /// The instants an accepted event row commits with — the ONE place Mac and iOS agree
    /// on what a syllabus event is.
    ///
    /// A syllabus that says "Quiz 3 — Sept 24" states a DAY. Atlas used to invent local
    /// midnight and an hour of length for it, which is how a class page filled up with
    /// "12 AM · 1h". Such a row commits as a genuine all-day event instead, on the
    /// canonical UTC-midnight anchor every other all-day item uses (`AllDayDate`).
    /// A row that DID state a time keeps it, and still runs `defaultEventMinutes`.
    /// `nil` when the row has no date at all — there is no event to place.
    public static func eventInterval(
        for item: SyllabusDraftItem,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date, isAllDay: Bool)? {
        guard let date = item.date else { return nil }
        guard item.commitsAllDay(calendar: calendar) else {
            return (start: date, end: eventEnd(for: date), isAllDay: false)
        }
        let anchor = AllDayDate.anchor(forDayOf: date, in: calendar)
        return (start: anchor, end: anchor, isAllDay: true)
    }

    /// The due date an accepted TASK row commits with — the task-side twin of
    /// `eventInterval(for:)`, and the ONE place Mac and iOS agree on it.
    ///
    /// A syllabus that says "Problem Set 4 — Sept 24" states a DAY, not an instant. Such a
    /// row commits ALL-DAY, on the canonical UTC-midnight anchor every other all-day item
    /// uses (`AllDayDate`) — which is what `TaskItem.effectiveDueDate` unpacks back into
    /// "due by the end of Sept 24 where the student is". Storing the raw parsed instant
    /// instead is the day-off bug migration 0045 fixed for Canvas.
    /// A row that DID state a clock time keeps it, timed.
    public static func taskDue(
        for item: SyllabusDraftItem,
        calendar: Calendar = .current
    ) -> (dueDate: Date?, allDay: Bool) {
        guard let date = item.date else { return (nil, false) }
        guard item.commitsAllDay(calendar: calendar) else { return (date, false) }
        return (AllDayDate.anchor(forDayOf: date, in: calendar), true)
    }

    /// A card the model returned but filled with nothing is not a card.
    public static func isEmpty(_ info: ClassInfoCard) -> Bool {
        info.gradeWeights.isEmpty && info.policies.isEmpty && (info.officeHours?.isEmpty ?? true)
    }

    private static func blankToNil(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }
}
