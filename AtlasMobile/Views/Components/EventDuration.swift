import Foundation

/// Shared duration ladder + labels for the mobile event pickers (`ManualAddSheet`,
/// `ItemDetailSheet`). The ladder used to stop at 120 min, which silently truncated
/// any longer event — a 3-hour Google/ICS event opened with no matching entry, and
/// picking anything rewrote `end` to ≤2h. It now runs to a full day, and
/// `options(including:)` keeps an off-ladder length (say 275 min) selectable.
enum EventDuration {

    /// Coarsening steps: quarter-hours through 2h, half-hours to 4h, then hours.
    static let ladder: [Int] = [15, 30, 45, 60, 90, 120, 150, 180, 210, 240,
                                300, 360, 420, 480, 540, 600, 660, 720, 1440]

    /// The ladder with `current` folded in (in order) when it isn't already a rung,
    /// so an event's real length is always a selectable, checkmarked option.
    static func options(including current: Int) -> [Int] {
        ladder.contains(current) ? ladder : (ladder + [current]).sorted()
    }

    /// Splits an event's length into the duration the menu shows and the day its end lands
    /// on, so a multi-day event survives a round-trip through the pickers: whole 24-hour
    /// blocks become the end-day offset, the remainder stays on the clock. A 3-day
    /// conference reads "9am, 8 hr, ends Wednesday" instead of "56 hr".
    static func split(start: Date, end: Date, calendar: Calendar) -> (minutes: Int, endDay: Date) {
        let raw = max(15, Int(end.timeIntervalSince(start) / 60))
        var days = raw / 1440
        var minutes = raw - days * 1440
        if minutes == 0 && days > 0 { days -= 1; minutes = 1440 }   // an exact 24h block is "All day"
        return (minutes, calendar.date(byAdding: .day, value: days, to: start) ?? start)
    }

    /// The instant an event ends: `start` + `minutes`, carried onto `endDay` when that is a
    /// later calendar day. The day step goes through the calendar so DST can't nudge the
    /// clock time. Inverse of `split`.
    static func end(start: Date, minutes: Int, endDay: Date, calendar: Calendar) -> Date {
        let base = start.addingTimeInterval(Double(minutes) * 60)
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: endDay)).day ?? 0
        guard days > 0 else { return base }
        return calendar.date(byAdding: .day, value: days, to: base) ?? base
    }

    /// "45 min" · "1 hr" · "1 hr 30 min" · "All day" (exactly 24h).
    static func label(_ minutes: Int) -> String {
        if minutes == 1440 { return "All day" }
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _):  return "\(m) min"
        case (_, 0):  return "\(h) hr"
        default:      return "\(h) hr \(m) min"
        }
    }
}
