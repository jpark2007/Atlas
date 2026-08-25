import Foundation

/// Pure synthesis of what a term puts on the calendar: recurring class meetings and
/// Key Date flags. Kept free of SwiftUI and `AppState` so every rule (term bounds,
/// break skipping, weekday matching, wall-clock parsing) is unit-testable.
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
