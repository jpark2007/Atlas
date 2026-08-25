import Foundation
import SwiftUI

/// Pure synthesis of what a term puts on the calendar: recurring class meetings and
/// Key Date flags. Kept free of `AppState` and of any view so every rule (term bounds,
/// break skipping, weekday matching, wall-clock parsing) is unit-testable, and so Mac
/// and iOS synthesize byte-identical tiles.
///
/// Whichever door a schedule came through — school ICS, an existing Google/Apple
/// calendar, a screenshot scan, manual entry — it lands in `Project.meetingPattern`,
/// and this is the one place that turns a pattern into dated blocks.
public enum SchoolCalendar {

    // MARK: - Meetings

    /// One dated occurrence of a class meeting block.
    public struct Meeting: Equatable {
        public let classID: UUID
        public let className: String
        public let code: String?
        public let start: Date
        public let end: Date
        public let location: String?

        public init(classID: UUID, className: String, code: String?, start: Date, end: Date, location: String?) {
            self.classID = classID
            self.className = className
            self.code = code
            self.start = start
            self.end = end
            self.location = location
        }
    }

    /// The meetings of `classes` that fall on `day`, in time order.
    ///
    /// A meeting exists only INSIDE the term's dates and only on a day the term isn't
    /// on break — a lecture must not be drawn over Thanksgiving because the pattern
    /// says "Thursday". A pattern block whose clock times don't parse is skipped
    /// rather than guessed at.
    public static func meetings(
        on day: Date,
        classes: [Project],
        term: Term,
        calendar: Calendar = .current
    ) -> [Meeting] {
        guard term.contains(day), !isBreakDay(day, in: term, calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: day)
        var out: [Meeting] = []
        for klass in classes where klass.archivedAt == nil {
            for block in klass.meetingPattern where block.weekdays.contains(weekday) {
                guard let start = time(block.start, on: day, calendar: calendar),
                      let end = time(block.end, on: day, calendar: calendar),
                      end > start else { continue }
                out.append(Meeting(classID: klass.id, className: klass.name, code: klass.code,
                                   start: start, end: end, location: block.location))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// A local wall-clock "HH:mm" resolved against `day`. A meeting is 10:00 in the
    /// school's day, never a fixed instant, so this rebuilds it per-day (DST included).
    public static func time(_ hhmm: String, on day: Date, calendar: Calendar = .current) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    // MARK: - Key dates

    /// True when the term marks `day` as a holiday or a break — no classes meet.
    /// Only those two kinds stop meetings: an add/drop deadline is a flag, not a day off.
    public static func isBreakDay(_ day: Date, in term: Term, calendar: Calendar = .current) -> Bool {
        keyDates(on: day, in: term, calendar: calendar).contains {
            $0.kind == .holiday || $0.kind == .breakPeriod
        }
    }

    /// The term's Key Dates falling on `day` — what the calendar draws as flags.
    public static func keyDates(on day: Date, in term: Term, calendar: Calendar = .current) -> [TermKeyDate] {
        term.keyDates.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    // MARK: - Calendar tiles (shared by Mac and iOS)

    /// `meetings(on:)` rendered as solid, class-colored calendar blocks (Phase 2 language:
    /// a class meeting is an EVENT). Shared so both platforms synthesize the identical
    /// tiles — including their ids, so dedup and selection agree across devices.
    ///
    /// These go through cross-calendar dedup like any other event: when the same lecture
    /// also arrives from Google/Apple/school ICS, the titles and times match and this
    /// synthesized Atlas copy wins, carrying the imported copy's source as "also in …".
    public static func meetingEvents(
        on day: Date,
        classes: [Project],
        term: Term,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        guard !classes.isEmpty else { return [] }
        return meetings(on: day, classes: classes, term: term, calendar: calendar).map { meeting in
            let project = classes.first { $0.id == meeting.classID }
            let color = project?.colorToken.map { ColorToken.color(for: $0) }
                ?? project?.spaceColor
                ?? AtlasTheme.Colors.school
            return CalendarEvent(
                id: CalendarSync.stableUUID(from: "class-meeting-\(meeting.classID.uuidString)-\(meeting.start.timeIntervalSince1970)"),
                title: meeting.className,
                subtitle: meeting.location ?? meeting.code ?? "Class",
                start: meeting.start,
                end: meeting.end,
                color: color,
                spaceName: project?.spaceName ?? "School",
                isAllDay: false,
                projectID: meeting.classID,
                // Synthesized from the class's pattern — edited on the class, not the tile.
                isReadOnly: true,
                spaceID: project?.spaceID
            )
        }
    }

    /// The term's Key Dates on `day`, as all-day flags. Deliberately NOT deadline markers:
    /// "Spring break" is not something you owe anybody, so it must never land in the day's
    /// due count. `spaceName` is the caller's School space, so the space filter treats a
    /// flag like the rest of School.
    public static func keyDateFlagEvents(
        on day: Date,
        in term: Term,
        spaceName: String,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        keyDates(on: day, in: term, calendar: calendar).map { keyDate in
            CalendarEvent(
                id: CalendarSync.stableUUID(from: "key-date-\(term.id.uuidString)-\(keyDate.label)-\(TermDay.string(from: keyDate.date))"),
                title: keyDate.label,
                subtitle: term.name,
                start: calendar.startOfDay(for: keyDate.date),
                end: calendar.startOfDay(for: keyDate.date),
                color: AtlasTheme.Colors.textSecondary,
                spaceName: spaceName,
                isAllDay: true,
                isReadOnly: true
            )
        }
    }

    // MARK: - Term lifecycle

    /// The suggested next term after `term` — "Fall 2026" → "Spring 2027", and so on
    /// around the Fall → Spring → Summer cycle. Dates are deliberately NOT guessed:
    /// the new-semester flow asks for them.
    public static func nextTermName(after name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count == 2, let year = Int(parts[1]) else { return "" }
        switch parts[0].lowercased() {
        case "fall":   return "Spring \(year + 1)"
        case "spring": return "Summer \(year)"
        case "summer": return "Fall \(year)"
        case "winter": return "Spring \(year)"
        default:       return ""
        }
    }
}

/// "MWF · 10 AM–10:50 AM" from a stored meeting block — how a `MeetingBlock` reads to a
/// person. Shared rather than per-platform: the Mac class page and the iOS class hub must
/// describe the same pattern the same way, and the weekday mapping is worth one test, not
/// two copies. Weekday numbers follow Foundation's 1 = Sunday convention, the same one
/// `SchoolCalendar` matches against.
public enum MeetingPatternFormat {
    public static let weekdayInitials = ["", "Su", "M", "Tu", "W", "Th", "F", "Sa"]

    /// Weekday initials run together, then the time range — "MWF · 10 AM–10:50 AM".
    /// A block with no (or only out-of-range) weekdays degrades to the bare time.
    public static func describe(_ block: MeetingBlock) -> String {
        let days = block.weekdays.sorted()
            .compactMap { (1...7).contains($0) ? weekdayInitials[$0] : nil }
            .joined()
        let time = "\(display(block.start))–\(display(block.end))"
        return days.isEmpty ? time : "\(days) · \(time)"
    }

    /// "10:00" → "10 AM", "10:30" → "10:30 AM". Falls back to the stored string when it
    /// isn't parseable, so a malformed block still shows what it actually holds.
    public static func display(_ hhmm: String) -> String {
        guard let date = SchoolCalendar.time(hhmm, on: Date()) else { return hhmm }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }
}
