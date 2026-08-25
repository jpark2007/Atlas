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

    public init(id: UUID = UUID(), kind: SyllabusDraftKind, title: String,
                date: Date? = nil, notes: String? = nil, include: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.notes = notes
        self.include = include
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
    public var classInfo: ClassInfoCard?
    public var includeClassInfo: Bool
    public var items: [SyllabusDraftItem]
    /// The class this group commits onto. `nil` ⇒ nothing here can be written yet.
    public var targetClassID: UUID?

    public init(id: UUID = UUID(), code: String? = nil, name: String? = nil,
                meetingPattern: [MeetingBlock] = [], includeMeetingPattern: Bool = true,
                classInfo: ClassInfoCard? = nil, includeClassInfo: Bool = true,
                items: [SyllabusDraftItem] = [], targetClassID: UUID? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.meetingPattern = meetingPattern
        self.includeMeetingPattern = includeMeetingPattern
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

    /// Whether committing this group would write anything at all.
    public var writesAnything: Bool {
        !includedItems.isEmpty
            || (includeMeetingPattern && !meetingPattern.isEmpty)
            || (includeClassInfo && classInfo != nil)
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
                                 notes: blankToNil(scanned.notes))
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

    /// The end instant an extracted event commits with.
    public static func eventEnd(for start: Date) -> Date {
        start.addingTimeInterval(TimeInterval(defaultEventMinutes * 60))
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
