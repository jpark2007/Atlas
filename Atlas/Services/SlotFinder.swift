import Foundation

/// Pure gap-finding logic for auto-scheduling. Given a set of busy intervals on
/// a day, finds the first free slot of a requested length within the visible
/// hours, snapped to a minute boundary, never starting before `now`.
///
/// Kept free of `AppState` so it can be unit-tested with synthetic intervals.
enum SlotFinder {
    /// First free slot of `durationMin` minutes on `day`, within
    /// `[startHour, endHour)`, snapped up to `snapMinutes`, never before `now`,
    /// avoiding every interval in `busy`. Returns nil if no gap fits.
    static func firstFreeSlot(
        durationMin: Int,
        on day: Date,
        busy: [DateInterval],
        now: Date,
        startHour: Int = CalendarLayout.startHour,
        endHour: Int = CalendarLayout.endHour,
        snapMinutes: Int = 15,
        calendar: Calendar = .current
    ) -> Date? {
        guard durationMin > 0, snapMinutes > 0 else { return nil }
        guard let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let dayEnd   = calendar.date(bySettingHour: endHour,   minute: 0, second: 0, of: day),
              dayEnd > dayStart else { return nil }

        let duration = TimeInterval(durationMin * 60)

        // Earliest candidate: not before the day window, not in the past.
        var cursor = snapUp(max(dayStart, now), toMinutes: snapMinutes, calendar: calendar)

        // Only intervals that intersect the working window matter; sort by start.
        let sortedBusy = busy
            .filter { $0.end > dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }

        while cursor.addingTimeInterval(duration) <= dayEnd {
            let candidateEnd = cursor.addingTimeInterval(duration)
            if let conflict = sortedBusy.first(where: { $0.start < candidateEnd && $0.end > cursor }) {
                // Jump past the conflict and re-evaluate (chained overlaps resolve by re-looping).
                cursor = snapUp(conflict.end, toMinutes: snapMinutes, calendar: calendar)
            } else {
                return cursor
            }
        }
        return nil
    }

    /// Rounds `date` up to the next `step`-minute clock boundary. A date already
    /// exactly on a boundary (zero seconds) is returned unchanged.
    static func snapUp(_ date: Date, toMinutes step: Int, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        let remainder = minute % step
        if remainder == 0 && second == 0 { return calendar.date(from: comps) ?? date }
        comps.second = 0
        let truncated = calendar.date(from: comps) ?? date     // floor to the minute
        let add = (remainder == 0) ? step : (step - remainder) // seconds>0 on a boundary → next boundary
        return calendar.date(byAdding: .minute, value: add, to: truncated) ?? date
    }
}
