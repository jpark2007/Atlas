import XCTest
@testable import Atlas

/// Month-grid date math. Uses an injected Gregorian calendar with an explicit
/// `firstWeekday` and UTC timezone so cell boundaries are deterministic across
/// locales. Every assertion compares Dates derived from the same calendar — no
/// hardcoded clock strings.
final class MonthGridTests: XCTestCase {

    /// Sunday-first Gregorian/UTC (matches the macOS US default the view uses).
    private func sundayFirst() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1            // Sunday
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Monday-first variant to prove the alignment honors `firstWeekday`.
    private func mondayFirst() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2            // Monday
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return calendar.date(from: c)!
    }

    // MARK: shape

    func testAlwaysFortyTwoCells() {
        let cal = sundayFirst()
        // A few structurally different months (leading weekday, 28/30/31 days, leap Feb).
        for (y, m) in [(2026, 6), (2026, 2), (2024, 2), (2026, 3), (2026, 11)] {
            let cells = MonthGrid.cells(for: date(y, m, 15, calendar: cal), calendar: cal)
            XCTAssertEqual(cells.count, MonthGrid.cellCount, "\(y)-\(m) should yield 42 cells")
        }
    }

    // MARK: first-cell alignment

    func testFirstCellIsFirstWeekday() {
        let cal = sundayFirst()
        let cells = MonthGrid.cells(for: date(2026, 6, 15, calendar: cal), calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: cells[0]), cal.firstWeekday,
                       "First cell must be the calendar's firstWeekday (Sunday)")
    }

    func testFirstCellHonorsMondayFirst() {
        let cal = mondayFirst()
        let cells = MonthGrid.cells(for: date(2026, 6, 15, calendar: cal), calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: cells[0]), cal.firstWeekday,
                       "First cell must be Monday when firstWeekday == Monday")
    }

    func testFirstCellOnOrBeforeFirstOfMonthWithinAWeek() {
        let cal = sundayFirst()
        let firstOfMonth = cal.startOfDay(for: date(2026, 6, 1, calendar: cal))
        let cells = MonthGrid.cells(for: date(2026, 6, 15, calendar: cal), calendar: cal)
        let firstCell = cal.startOfDay(for: cells[0])
        XCTAssertLessThanOrEqual(firstCell, firstOfMonth)
        let leadDays = cal.dateComponents([.day], from: firstCell, to: firstOfMonth).day ?? -1
        XCTAssertTrue((0...6).contains(leadDays), "Leading days must be 0...6, got \(leadDays)")
    }

    // MARK: month membership / boundaries

    func testAllDaysOfMonthArePresentAndInMonth() {
        let cal = sundayFirst()
        let ref = date(2026, 6, 15, calendar: cal)
        let cells = MonthGrid.cells(for: ref, calendar: cal)
        let inMonthDays = cells
            .filter { MonthGrid.isInMonth($0, of: ref, calendar: cal) }
            .map { cal.component(.day, from: $0) }
            .sorted()
        // June has 30 days, all of which should appear exactly once.
        XCTAssertEqual(inMonthDays, Array(1...30))
    }

    func testLastCellIsFirstPlusFortyOne() {
        let cal = sundayFirst()
        let cells = MonthGrid.cells(for: date(2026, 6, 15, calendar: cal), calendar: cal)
        let expectedLast = cal.date(byAdding: .day, value: MonthGrid.cellCount - 1, to: cells[0])!
        XCTAssertEqual(cal.startOfDay(for: cells.last!), cal.startOfDay(for: expectedLast))
    }

    func testCellsAreConsecutiveDays() {
        let cal = sundayFirst()
        let cells = MonthGrid.cells(for: date(2026, 2, 10, calendar: cal), calendar: cal)
        for i in 1..<cells.count {
            let gap = cal.dateComponents([.day],
                                         from: cal.startOfDay(for: cells[i - 1]),
                                         to: cal.startOfDay(for: cells[i])).day
            XCTAssertEqual(gap, 1, "Cells must be consecutive calendar days")
        }
    }

    // MARK: isInMonth

    func testIsInMonthAcrossYearBoundary() {
        let cal = sundayFirst()
        let dec = date(2025, 12, 31, calendar: cal)
        let jan = date(2026, 1, 1, calendar: cal)
        XCTAssertTrue(MonthGrid.isInMonth(dec, of: date(2025, 12, 5, calendar: cal), calendar: cal))
        XCTAssertFalse(MonthGrid.isInMonth(jan, of: date(2025, 12, 5, calendar: cal), calendar: cal),
                       "Same day number, different month/year — not in month")
    }
}
