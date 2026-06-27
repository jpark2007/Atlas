import Foundation

/// Pure date math for the month calendar grid. Given any day in a month, returns
/// the 42 dates (6 weeks × 7 days) that fill a fixed-height month grid, starting
/// at the `firstWeekday` on/before the 1st of that month.
///
/// Kept free of SwiftUI / `AppState` so the boundary math is unit-testable with an
/// injected `Calendar` (no hidden `Date()` / locale dependency).
enum MonthGrid {

    /// Number of cells in the grid: a fixed 6-week (6×7) layout so the month view
    /// never changes height as you page between months.
    static let cellCount = 42

    /// The 42 consecutive days that fill the month grid containing `date`.
    ///
    /// The first cell is the `firstWeekday` (e.g. Sunday) on or before the 1st of
    /// the month, so the 1st always lands in the first row. Cells then run
    /// consecutively for `cellCount` days, spilling into the trailing month.
    static func cells(for date: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start

        // Days to back up from the 1st to reach the week's firstWeekday.
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) else { return [] }
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// True when `date` falls in the same month (and year) as `reference`.
    static func isInMonth(_ date: Date, of reference: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: reference, toGranularity: .month)
    }
}
