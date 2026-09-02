import XCTest
@testable import AtlasCore

/// Handoff §D: Canvas exports assignment due dates date-only, so they land at UTC
/// midnight. Read as an instant west of Greenwich they fire ~28h early and bucket a day
/// off. `TaskItem.effectiveDueDate` is the one reading everything compares against: an
/// all-day task is due at the END of its UTC calendar day, in the reader's own zone.
final class AllDayTaskDueTests: XCTestCase {

    /// EDT — the zone the bug was observed in (UTC-4), where UTC midnight is 8 PM the
    /// previous evening. Every assertion below is meaningless in UTC itself.
    private let eastern: TimeZone = TimeZone(identifier: "America/New_York")!
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = eastern
        return c
    }

    /// "Due Sep 9", as Canvas stores it: 2026-09-09T00:00:00Z.
    private var sep9UTCMidnight: Date {
        AllDayDate.utc.date(from: DateComponents(year: 2026, month: 9, day: 9))!
    }

    private func allDayTask(due: Date) -> TaskItem {
        var t = TaskItem(title: "Problem Set 3", dueLabel: "", dueDate: due)
        t.allDay = true
        return t
    }

    // MARK: - effectiveDueDate

    func test_allDay_dueAtEndOfItsUTCCalendarDayLocally() {
        let due = effectiveDue(allDayTask(due: sep9UTCMidnight))
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 9)
        XCTAssertEqual(c.day, 9)
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 59)
        XCTAssertEqual(c.second, 59)
    }

    func test_timedTask_isUnchanged() {
        let due = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 17))!
        let task = TaskItem(title: "Essay", dueLabel: "", dueDate: due)
        XCTAssertFalse(task.allDay)
        XCTAssertEqual(task.effectiveDueDate(calendar: cal), due)
    }

    func test_noDueDate_staysNil() {
        XCTAssertNil(TaskItem(title: "Someday", dueLabel: "").effectiveDueDate(calendar: cal))
    }

    // MARK: - The bug: late a day early

    func test_notLateOnTheEveningBeforeItIsDue() {
        // 8:30 PM Sep 8 in EDT — half an hour PAST the raw UTC-midnight instant.
        let sep8Evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 20, minute: 30))!
        XCTAssertFalse(allDayTask(due: sep9UTCMidnight).isOverdue(now: sep8Evening, calendar: cal))
    }

    func test_stillNotLateAtLunchtimeOnTheDayItIsDue() {
        let sep9Noon = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        XCTAssertFalse(allDayTask(due: sep9UTCMidnight).isOverdue(now: sep9Noon, calendar: cal))
    }

    func test_lateOnceTheDayIsOver() {
        let sep10Morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9))!
        XCTAssertTrue(allDayTask(due: sep9UTCMidnight).isOverdue(now: sep10Morning, calendar: cal))
    }

    // MARK: - Bucketing lands on the right day

    func test_bucketsAsTodayOnTheDayItIsDue() {
        let sep9Morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))!
        XCTAssertEqual(TaskGrouping.bucket(for: effectiveDue(allDayTask(due: sep9UTCMidnight)),
                                           now: sep9Morning, calendar: cal),
                       .today)
    }

    func test_doesNotBucketAsTodayTheEveningBefore() {
        let sep8Evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 20, minute: 30))!
        XCTAssertEqual(TaskGrouping.bucket(for: effectiveDue(allDayTask(due: sep9UTCMidnight)),
                                           now: sep8Evening, calendar: cal),
                       .thisWeek)
    }

    // MARK: - Rendering is date-only

    func test_labelShowsNoClockTime() {
        // Compared against the same day's local-midnight label: an all-day due must read
        // exactly like a date-only due, never "Sep 8 8 PM".
        let localSep9 = cal.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
        XCTAssertEqual(TaskItem.dueLabel(for: sep9UTCMidnight, allDay: true, now: now, calendar: cal),
                       TaskItem.dueLabel(for: localSep9, now: now, calendar: cal))
    }

    private func effectiveDue(_ t: TaskItem) -> Date {
        t.effectiveDueDate(calendar: cal)!
    }
}
