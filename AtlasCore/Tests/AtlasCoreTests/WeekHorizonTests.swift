import XCTest
@testable import AtlasCore

/// The week horizon shared by the calendar rail (variant 1A) and the class page
/// (variant 2C): one definition of "this week", and one partition of open work into
/// Overdue / This week / Next week / Later / No date.
///
/// Every assertion runs in EDT with an all-day task somewhere in it, because the whole
/// point of `effectiveDueDate` is that a Canvas date-only due (UTC midnight) must bucket
/// on ITS OWN day, not the evening before.
final class WeekHorizonTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1   // Sunday — deterministic regardless of the test machine's locale
        return c
    }

    /// Tue Sep 1 2026, 10 AM local. Its week (Sun-first) is Aug 30 – Sep 5.
    private var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
    }

    private func day(_ month: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }

    private func task(_ title: String, due: Date?, allDay: Bool = false, done: Bool = false) -> TaskItem {
        var t = TaskItem(title: title, dueLabel: "", dueDate: due)
        t.allDay = allDay
        t.done = done
        return t
    }

    /// A Canvas date-only due, stored the way Canvas sends it: UTC midnight of that day.
    private func allDayTask(_ title: String, month: Int, day d: Int) -> TaskItem {
        let utcMidnight = AllDayDate.utc.date(from: DateComponents(year: 2026, month: month, day: d))!
        return task(title, due: utcMidnight, allDay: true)
    }

    // MARK: - weekInterval / weekStart

    func test_weekInterval_containsNowAndIsSevenDays() {
        let week = TimeModel.weekInterval(containing: now, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: week.start).day, 30)
        XCTAssertEqual(cal.dateComponents([.month], from: week.start).month, 8)
        XCTAssertEqual(week.duration, 7 * 24 * 60 * 60, accuracy: 3600)  // DST-tolerant
        XCTAssertEqual(TimeModel.weekStart(for: now, calendar: cal), week.start)
    }

    func test_followingWeekStartsWhereThisOneEnds() {
        let this = TimeModel.weekInterval(containing: now, calendar: cal)
        let next = TimeModel.weekInterval(offset: 1, from: now, calendar: cal)
        XCTAssertEqual(next.start, this.end)
    }

    // MARK: - membership, at the boundaries

    func test_lastInstantOfTheWeekIsInIt_firstInstantOfTheNextIsNot() {
        let week = TimeModel.weekInterval(containing: now, calendar: cal)
        XCTAssertTrue(TimeModel.isInCurrentWeek(week.start, now: now, calendar: cal))
        XCTAssertTrue(TimeModel.isInCurrentWeek(week.end.addingTimeInterval(-1), now: now, calendar: cal))
        // The end instant belongs to the FOLLOWING week — not both.
        XCTAssertFalse(TimeModel.isInCurrentWeek(week.end, now: now, calendar: cal))
        XCTAssertTrue(TimeModel.isInFollowingWeek(week.end, now: now, calendar: cal))
        XCTAssertFalse(TimeModel.isInFollowingWeek(week.end.addingTimeInterval(-1), now: now, calendar: cal))
    }

    // MARK: - horizon

    func test_horizon_bucketsRelativeToTheWeek() {
        XCTAssertEqual(TimeModel.horizon(of: day(8, 28), now: now, calendar: cal), .overdue)
        XCTAssertEqual(TimeModel.horizon(of: day(9, 1, hour: 17), now: now, calendar: cal), .thisWeek)
        XCTAssertEqual(TimeModel.horizon(of: day(9, 4), now: now, calendar: cal), .thisWeek)
        XCTAssertEqual(TimeModel.horizon(of: day(9, 8), now: now, calendar: cal), .nextWeek)
        XCTAssertEqual(TimeModel.horizon(of: day(10, 6), now: now, calendar: cal), .later)
        XCTAssertEqual(TimeModel.horizon(of: nil, now: now, calendar: cal), .noDate)
    }

    /// Earlier THIS week but already past is overdue, not "this week" — the 1A rail pins
    /// it above the window, so it must not sit quietly among Friday's work.
    func test_earlierThisWeekButPast_isOverdue() {
        let week = TimeModel.weekInterval(containing: now, calendar: cal)
        for pastDay in [day(8, 30), day(8, 31)] {          // Sun + Mon: inside the window…
            XCTAssertTrue(week.containsHalfOpen(pastDay))
            XCTAssertEqual(TimeModel.horizon(of: pastDay, now: now, calendar: cal), .overdue)  // …but behind
        }
    }

    /// Due today at 9 AM with `now` 10 AM: still TODAY's work, never "overdue" — the
    /// horizon is day-granular, like `lateItems`.
    func test_earlierToday_isStillThisWeek() {
        XCTAssertEqual(TimeModel.horizon(of: day(9, 1, hour: 9), now: now, calendar: cal), .thisWeek)
    }

    // MARK: - partition

    func test_byWeekHorizon_partitionsOpenWorkAndSortsByDue() {
        let tasks = [
            task("Midterm 1", due: day(10, 6)),
            task("Quiz 3", due: day(9, 4)),
            task("Lecture 0 Prerequisites", due: day(8, 28)),
            task("Someday", due: nil),
            allDayTask("161 Course and Grading Policies Checklist", month: 9, day: 8),
            task("Lecture 4 The Chain Rule", due: day(9, 2)),
        ]
        let g = TaskGrouping.byWeekHorizon(tasks: tasks, now: now, calendar: cal)

        XCTAssertEqual(g[.overdue]?.map(\.title), ["Lecture 0 Prerequisites"])
        XCTAssertEqual(g[.thisWeek]?.map(\.title), ["Lecture 4 The Chain Rule", "Quiz 3"])
        XCTAssertEqual(g[.nextWeek]?.map(\.title), ["161 Course and Grading Policies Checklist"])
        XCTAssertEqual(g[.later]?.map(\.title), ["Midterm 1"])
        XCTAssertEqual(g[.noDate]?.map(\.title), ["Someday"])
    }

    /// The bug this whole horizon is built on: a date-only due read as a raw instant lands
    /// in the previous day's bucket. Sep 6 (UTC midnight) is 8 PM Sep 5 EDT — the last day
    /// of THIS week — but it is next week's work.
    func test_allDayDue_bucketsOnItsOwnDay_notTheEveningBefore() {
        let checklist = allDayTask("Weekly wrapper", month: 9, day: 6)
        XCTAssertEqual(TaskGrouping.horizon(for: checklist, now: now, calendar: cal), .nextWeek)
        // Proof the raw instant would have said otherwise.
        XCTAssertEqual(TimeModel.horizon(of: checklist.dueDate, now: now, calendar: cal), .thisWeek)
    }

    func test_doneTasksAreExcluded() {
        let tasks = [task("Finished", due: day(9, 2), done: true), task("Open", due: day(9, 2))]
        let g = TaskGrouping.byWeekHorizon(tasks: tasks, now: now, calendar: cal)
        XCTAssertEqual(g[.thisWeek]?.map(\.title), ["Open"])
    }

    // MARK: - months (variant 2C's rest-of-term sections)

    func test_byMonth_groupsAscendingAndUsesTheEffectiveDay() {
        let tasks = [
            task("Synthesis 1", due: day(12, 2)),
            task("Midterm 1", due: day(10, 6)),
            task("Lecture 13", due: day(9, 21)),
            allDayTask("Final Exam", month: 12, day: 15),
            task("No date", due: nil),
        ]
        let months = TaskGrouping.byMonth(tasks: tasks, calendar: cal)
        XCTAssertEqual(months.count, 3)
        XCTAssertEqual(months.map { cal.component(.month, from: $0.month) }, [9, 10, 12])
        XCTAssertEqual(months[2].tasks.map(\.title), ["Synthesis 1", "Final Exam"])
        // A month section starts at its first instant, so it can title itself.
        XCTAssertEqual(cal.component(.day, from: months[0].month), 1)
    }

    /// An all-day December 1 due (UTC midnight = Nov 30, 7 PM EST) must sit in DECEMBER.
    func test_byMonth_allDayOnTheFirst_doesNotFallIntoThePreviousMonth() {
        let months = TaskGrouping.byMonth(tasks: [allDayTask("Synthesis 3", month: 12, day: 1)], calendar: cal)
        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(cal.component(.month, from: months[0].month), 12)
    }
}
