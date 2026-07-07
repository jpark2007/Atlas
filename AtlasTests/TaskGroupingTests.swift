import XCTest
@testable import AtlasCore
@testable import Atlas

// MARK: - Helpers

/// Build a TaskItem with an optional structured due date.
private func makeTask(_ title: String, due: Date? = nil) -> TaskItem {
    var t = TaskItem(title: title, dueLabel: "")
    t.dueDate = due
    return t
}

/// ISO-style Gregorian calendar fixed to UTC, Monday-first — stable week
/// boundaries across all locales (mirrors MetricsTests).
private func testCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

final class TaskGroupingTests: XCTestCase {

    private let cal = testCalendar()
    private var now = Date()

    /// Thursday June 25, 2026 12:00 UTC — mid-week in a Monday-first calendar.
    override func setUp() {
        super.setUp()
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 25; c.hour = 12
        now = cal.date(from: c)!
    }

    private func day(_ offsetDays: Int, hour: Int = 9) -> Date {
        let base = cal.date(byAdding: .day, value: offsetDays, to: cal.startOfDay(for: now))!
        return cal.date(byAdding: .hour, value: hour, to: base)!
    }

    // MARK: bucket classification

    func testBucketClassification() {
        XCTAssertEqual(TaskGrouping.bucket(for: nil,        now: now, calendar: cal), .noDate)
        XCTAssertEqual(TaskGrouping.bucket(for: day(-1),    now: now, calendar: cal), .overdue)
        XCTAssertEqual(TaskGrouping.bucket(for: day(0, hour: 23), now: now, calendar: cal), .today,
                       "Any time on the current calendar day is Today")
        XCTAssertEqual(TaskGrouping.bucket(for: day(0, hour: 1),  now: now, calendar: cal), .today,
                       "Earlier today (still same day) counts as Today, not Overdue")
        // Friday June 26 is still this week (Mon-first week of Jun 22–28).
        XCTAssertEqual(TaskGrouping.bucket(for: day(1),     now: now, calendar: cal), .thisWeek)
        // 8 days out is beyond this week.
        XCTAssertEqual(TaskGrouping.bucket(for: day(8),     now: now, calendar: cal), .later)
    }

    // MARK: grouping output

    func testByDueBucket_orderAndMembership() {
        let tasks = [
            makeTask("later",   due: day(8)),
            makeTask("overdue", due: day(-2)),
            makeTask("undated"),
            makeTask("today",   due: day(0)),
            makeTask("week",    due: day(1)),
        ]

        let groups = TaskGrouping.byDueBucket(tasks: tasks, now: now, calendar: cal)

        XCTAssertEqual(groups.map(\.title),
                       ["Overdue", "Today", "This week", "Later", "No date"],
                       "Buckets render in fixed order")
        XCTAssertEqual(groups.first(where: { $0.title == "Overdue" })?.tasks.map(\.title), ["overdue"])
        XCTAssertEqual(groups.first(where: { $0.title == "Today" })?.tasks.map(\.title),   ["today"])
        XCTAssertEqual(groups.first(where: { $0.title == "This week" })?.tasks.map(\.title), ["week"])
        XCTAssertEqual(groups.first(where: { $0.title == "Later" })?.tasks.map(\.title),   ["later"])
        XCTAssertEqual(groups.first(where: { $0.title == "No date" })?.tasks.map(\.title), ["undated"])
    }

    func testByDueBucket_omitsEmptyBuckets() {
        let tasks = [makeTask("a"), makeTask("b")]   // all undated
        let groups = TaskGrouping.byDueBucket(tasks: tasks, now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.title), ["No date"], "Only non-empty buckets appear")
        XCTAssertEqual(groups[0].tasks.map(\.title), ["a", "b"])
    }

    func testByDueBucket_sortsWithinBucketByDateThenTitle() {
        // Two overdue tasks on different days + same-day tie broken by title.
        let tasks = [
            makeTask("zeta",  due: day(-1)),
            makeTask("alpha", due: day(-1)),
            makeTask("older", due: day(-3)),
        ]
        let groups = TaskGrouping.byDueBucket(tasks: tasks, now: now, calendar: cal)
        XCTAssertEqual(groups.first(where: { $0.title == "Overdue" })?.tasks.map(\.title),
                       ["older", "alpha", "zeta"],
                       "Earlier date first; same date sorted by title")
    }

    func testByDueBucket_empty() {
        XCTAssertTrue(TaskGrouping.byDueBucket(tasks: [], now: now, calendar: cal).isEmpty)
    }
}
