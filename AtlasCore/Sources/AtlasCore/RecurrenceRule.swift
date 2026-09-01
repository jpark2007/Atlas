import Foundation

/// A repeating-event pattern — "every Mon/Wed/Fri until Dec 12", "every other
/// Tuesday", "daily for 10 days".
///
/// **Atlas materializes recurrence.** A rule is not stored as a live RRULE the
/// grid re-expands on every render; it is expanded ONCE into real `CalendarEvent`
/// rows that share a `seriesID`, and each row carries the rule's text so the UI can
/// say "Every Mon, Wed & Fri". That keeps every existing surface — the day/week/
/// month grids, agenda, availability publish, Google/Apple write-back, search —
/// working unchanged, and lets a single session be moved or cancelled the way a
/// class actually gets moved or cancelled.
///
/// The trade-off is a bounded series: expansion needs an end. `until` or `count`
/// supplies one; without either, `defaultHorizonDays` caps it at a year, and
/// `maxOccurrences` is a hard backstop so no rule can ever explode the store.
///
/// Serialized as an RFC 5545 RRULE fragment (`FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR;
/// UNTIL=20261212`) so the stored text stays portable if real RRULE sync lands later.
public struct RecurrenceRule: Equatable, Hashable, Codable, Sendable {

    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
    }

    public var frequency: Frequency

    /// Repeat every `interval` days/weeks/months. Clamped to >= 1.
    public var interval: Int

    /// Which weekdays a WEEKLY rule fires on, as `Calendar` weekday numbers
    /// (1 = Sunday … 7 = Saturday). Empty ⇒ use the start date's own weekday.
    ///
    /// When non-empty this set — not the start date — decides which days are
    /// sessions. "MWF from Sept 2" where Sept 2 is a Tuesday means the first class
    /// is Wednesday the 3rd; the start date is the range's opening bound and the
    /// source of the time-of-day, never an implicit extra occurrence. (This is the
    /// one deliberate divergence from RFC 5545, where DTSTART always occurs.)
    public var weekdays: Set<Int>

    /// Last day of the series, INCLUSIVE — any occurrence starting on that local
    /// calendar day is kept. Nil ⇒ bounded by `count` or the default horizon.
    public var until: Date?

    /// Total number of occurrences, INCLUDING the first. Nil ⇒ bounded by `until`
    /// or the default horizon. When both are set, whichever ends the series first wins.
    public var count: Int?

    /// Horizon for an unbounded rule ("every Monday", no end). A year of a weekly
    /// class is ~52 rows — enough to be useful, small enough to stay cheap.
    public static let defaultHorizonDays = 365

    /// Hard backstop on expansion, regardless of `until`/`count`/horizon. Daily for
    /// a year is 365, so this only ever bites a pathological rule.
    public static let maxOccurrences = 400

    public init(frequency: Frequency,
                interval: Int = 1,
                weekdays: Set<Int> = [],
                until: Date? = nil,
                count: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.until = until
        self.count = count.map { max(1, $0) }
    }

    // MARK: - Expansion

    /// Every start instant this rule produces, in ascending order, anchored at
    /// `start`'s wall-clock time of day.
    ///
    /// Time-of-day is re-applied per day rather than added as an offset, so a
    /// 10:00 AM class stays 10:00 AM across a DST transition instead of drifting
    /// to 9 or 11. Returns `[start]` for a rule that produces nothing (a `until`
    /// before the start), so a capture never silently vanishes.
    public func occurrences(startingAt start: Date,
                            calendar: Calendar = .current) -> [Date] {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: start)
        let firstDay = calendar.startOfDay(for: start)

        // Inclusive end: the last day is fully in range, so bound with the START of
        // the following day and compare strictly. Nil `until` falls back to the horizon.
        let horizonEnd = calendar.date(byAdding: .day,
                                       value: Self.defaultHorizonDays,
                                       to: firstDay) ?? firstDay
        let limit: Date = until.map {
            let dayStart = calendar.startOfDay(for: $0)
            return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } ?? horizonEnd

        var days: [Date] = []
        switch frequency {
        case .daily:
            days = dailyDays(from: firstDay, before: limit, calendar: calendar)
        case .weekly:
            days = weeklyDays(from: firstDay, before: limit, calendar: calendar, startWeekdayOf: start)
        case .monthly:
            days = monthlyDays(from: firstDay, before: limit, calendar: calendar)
        }

        var result = days.compactMap {
            calendar.date(bySettingHour: comps.hour ?? 0,
                          minute: comps.minute ?? 0,
                          second: comps.second ?? 0,
                          of: $0)
        }
        if let count { result = Array(result.prefix(count)) }
        result = Array(result.prefix(Self.maxOccurrences))
        return result.isEmpty ? [start] : result
    }

    private func dailyDays(from first: Date, before limit: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = first
        while day < limit && days.count < Self.maxOccurrences {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: interval, to: day) else { break }
            day = next
        }
        return days
    }

    private func weeklyDays(from first: Date, before limit: Date,
                            calendar: Calendar, startWeekdayOf start: Date) -> [Date] {
        // An empty weekday set means "same weekday as the start" — the natural
        // reading of a bare "repeat weekly" on an event the user already dated.
        let targets = weekdays.isEmpty
            ? [calendar.component(.weekday, from: start)]
            : weekdays.sorted()

        // Anchor on the calendar week containing the start so `interval` counts
        // whole weeks, and every weekday in a given week belongs to the same step.
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else {
            return []
        }
        var days: [Date] = []
        var week = weekStart
        while week < limit && days.count < Self.maxOccurrences {
            for target in targets {
                guard let day = calendar.date(bySetting: .weekday, value: target, of: week)
                        ?? nextWeekday(target, onOrAfter: week, calendar: calendar) else { continue }
                let normalized = calendar.startOfDay(for: day)
                // `bySetting:` can land in the following week for some locales —
                // keep only days that really belong to this step's week.
                guard normalized >= week,
                      normalized < calendar.date(byAdding: .day, value: 7, to: week) ?? limit,
                      normalized >= first, normalized < limit else { continue }
                days.append(normalized)
            }
            guard let next = calendar.date(byAdding: .weekOfYear, value: interval, to: week) else { break }
            week = next
        }
        return days.sorted()
    }

    /// Fallback for `date(bySetting:)` when it can't resolve a weekday inside the
    /// week: walk forward day by day (at most 6 steps).
    private func nextWeekday(_ weekday: Int, onOrAfter day: Date, calendar: Calendar) -> Date? {
        for offset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return nil
    }

    private func monthlyDays(from first: Date, before limit: Date, calendar: Calendar) -> [Date] {
        // Same day-of-month each step. A month too short for that day (no Feb 30th)
        // is SKIPPED rather than clamped to the 28th — a clamp would silently invent
        // a session on a date the user never picked.
        let targetDay = calendar.component(.day, from: first)
        var days: [Date] = []
        var step = 0
        while days.count < Self.maxOccurrences {
            guard let monthAnchor = calendar.date(byAdding: .month, value: step * interval, to: first) else { break }
            let monthStart = calendar.startOfDay(for: monthAnchor)
            if monthStart >= limit { break }
            if calendar.component(.day, from: monthStart) == targetDay {
                days.append(monthStart)
            }
            step += 1
            // `byAdding: .month` clamps a short month (Jan 31 → Feb 28), so the loop
            // still advances one month per step even when a step is skipped.
            if step > Self.maxOccurrences { break }
        }
        return days
    }

    // MARK: - RRULE text

    /// Weekday codes in `Calendar` order (index 0 unused — weekdays are 1-based).
    static let weekdayCodes = ["", "SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// RFC 5545 RRULE fragment. `UNTIL` is written as a bare local calendar date
    /// (`20261212`) — the series' inclusive last DAY, which is what the user said
    /// ("until Dec 12"); a UTC instant would shift that day across the date line.
    public var rruleText: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if !weekdays.isEmpty {
            let codes = weekdays.sorted().map { Self.weekdayCodes[$0] }
            parts.append("BYDAY=\(codes.joined(separator: ","))")
        }
        if let until { parts.append("UNTIL=\(Self.untilFormatter.string(from: until))") }
        if let count { parts.append("COUNT=\(count)") }
        return parts.joined(separator: ";")
    }

    /// Parse an `rruleText` back into a rule. Nil for anything without a FREQ we
    /// support, so an unreadable stored string degrades to "no repeat" rather than
    /// throwing at load. Tolerates a full `UNTIL=20261212T235959Z` instant too.
    public init?(rruleText text: String) {
        var pairs: [String: String] = [:]
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            pairs[kv[0].uppercased()] = String(kv[1])
        }
        guard let freqRaw = pairs["FREQ"], let freq = Frequency(rawValue: freqRaw.uppercased()) else {
            return nil
        }
        let days = (pairs["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { Self.weekdayCodes.firstIndex(of: $0.uppercased().trimmingCharacters(in: .whitespaces)) }
        let until = pairs["UNTIL"].flatMap { raw -> Date? in
            Self.untilFormatter.date(from: String(raw.prefix(8)))
        }
        self.init(frequency: freq,
                  interval: Int(pairs["INTERVAL"] ?? "") ?? 1,
                  weekdays: Set(days),
                  until: until,
                  count: Int(pairs["COUNT"] ?? ""))
    }

    // MARK: - Display

    private static let shortWeekdayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let untilLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "Every Mon, Wed & Fri until Dec 12" — the one-line series label shown on a
    /// tile's detail page and under the editor's repeat picker.
    public var summary: String {
        var base: String
        switch frequency {
        case .daily:
            base = interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            let names = weekdays.sorted().map { Self.shortWeekdayNames[$0] }
            let cadence = interval == 1 ? "Every" : "Every \(interval) weeks on"
            if names.isEmpty {
                base = interval == 1 ? "Every week" : "Every \(interval) weeks"
            } else if Set(weekdays) == Set(2...6) && interval == 1 {
                base = "Every weekday"
            } else {
                base = "\(cadence) \(Self.list(names))"
            }
        case .monthly:
            base = interval == 1 ? "Every month" : "Every \(interval) months"
        }
        if let until {
            base += " until \(Self.untilLabelFormatter.string(from: until))"
        } else if let count {
            base += ", \(count) times"
        }
        return base
    }

    /// "Mon", "Mon & Wed", "Mon, Wed & Fri".
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
        }
    }
}

// MARK: - From a capture

extension RecurrenceRule {

    /// Build a rule from the model's loose wire form, or nil when it describes
    /// nothing usable (unknown frequency, or a weekly rule with no weekdays AND
    /// no start weekday to fall back on — the caller supplies that separately).
    ///
    /// This is the ONLY validation seam between the LLM and the store: everything
    /// the model can get wrong (a bogus `freq`, junk in `byDay`, a negative
    /// interval, an unparseable `untilISO`) is normalized or dropped here, so a
    /// confused parse degrades to a single event rather than a corrupt series.
    public init?(capture: CaptureRecurrence) {
        guard let frequency = Frequency(rawValue: capture.freq.uppercased()) else { return nil }
        let days = (capture.byDay ?? []).compactMap {
            RecurrenceRule.weekdayCodes.firstIndex(of: $0.uppercased().trimmingCharacters(in: .whitespaces))
        }
        self.init(frequency: frequency,
                  interval: capture.interval ?? 1,
                  weekdays: Set(days),
                  until: CaptureDateParser.date(from: capture.untilISO),
                  count: capture.count)
    }
}

// MARK: - Edit / delete scope

/// Which occurrences of a repeating series an edit or delete applies to — the
/// three choices every calendar offers when you touch one session of a series.
///
/// `thisAndFollowing` is the one that matters for a class: "the 9am section moves
/// to 10am after spring break" changes the rest of the term without rewriting the
/// sessions already behind you.
public enum SeriesScope: String, CaseIterable, Sendable {
    case thisEvent
    case thisAndFollowing
    case allEvents

    /// Button copy, matching the wording users already know from Google/Apple Calendar.
    public var label: String {
        switch self {
        case .thisEvent:        return "This event"
        case .thisAndFollowing: return "This and following"
        case .allEvents:        return "All events"
        }
    }
}
