import XCTest
import SwiftUI
@testable import AtlasCore

/// Drew, 09-01: a class page's "EVENTS 18" flat dump merges INTO the term folds — "when u
/// see this week u see events and or tasks for this week… same for rest of september".
/// These pin the merge: one order, the same week window tasks already use, and an all-day
/// exam bucketing on its OWN day rather than the UTC anchor's local hour.
final class TermTimelineTests: XCTestCase {

    private let eastern: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday, Sep 23 2026, 9 AM Eastern.
    private var now: Date { eastern.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))! }

    private func allDayEvent(_ title: String, _ month: Int, _ day: Int) -> CalendarEvent {
        let anchor = utc.date(from: DateComponents(year: 2026, month: month, day: day))!
        return CalendarEvent(title: title, subtitle: "", start: anchor, end: anchor,
                             color: .red, spaceName: "School", isAllDay: true)
    }

    private func task(_ title: String, _ month: Int, _ day: Int) -> TaskItem {
        var t = TaskItem(title: title, dueLabel: "")
        t.dueDate = utc.date(from: DateComponents(year: 2026, month: month, day: day))!
        t.allDay = true
        return t
    }

    func testEventsAndTasksShareTheSameWeekFolds() {
        let entries = TermTimeline.entries(
            tasks: [task("Problem set 4", 9, 25), task("Reading", 10, 6)],
            events: [allDayEvent("Quiz 3", 9, 24), allDayEvent("Midterm Exam #1", 10, 14)],
            calendar: eastern)
        let horizons = TermTimeline.byWeekHorizon(entries: entries, now: now, calendar: eastern)

        XCTAssertEqual(horizons[.thisWeek]?.map(\.title), ["Quiz 3", "Problem set 4"])
        XCTAssertEqual(horizons[.thisWeek]?.map(\.kind), [.event, .task])
        // Nothing this week is overdue, and the rest of the term is left for the months.
        XCTAssertNil(horizons[.overdue])
    }

    func testTheRestOfTheTermFoldsByMonthWithBothKinds() {
        let entries = TermTimeline.entries(
            tasks: [task("Reading", 10, 6)],
            events: [allDayEvent("Midterm Exam #1", 10, 14), allDayEvent("Quiz 5", 11, 3)],
            calendar: eastern)
        let horizons = TermTimeline.byWeekHorizon(entries: entries, now: now, calendar: eastern)
        let months = TermTimeline.byMonth(entries: (horizons[.nextWeek] ?? []) + (horizons[.later] ?? []),
                                          calendar: eastern)

        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months[0].entries.map(\.title), ["Reading", "Midterm Exam #1"])
        XCTAssertEqual(months[1].entries.map(\.title), ["Quiz 5"])
    }

    /// An all-day event is anchored at UTC midnight; read with a local calendar it would
    /// fall on the 23rd and bucket a day early. `bucketDate` is what keeps it on the 24th.
    func testAnAllDayEventBucketsOnItsOwnDayInEastern() throws {
        let entry = TermTimeline.entries(tasks: [], events: [allDayEvent("Quiz 3", 9, 24)],
                                         calendar: eastern)[0]
        XCTAssertEqual(eastern.dateComponents([.month, .day], from: try XCTUnwrap(entry.date)),
                       DateComponents(month: 9, day: 24))
    }

    func testAnEventBeforeTodayIsOverdueLikeALateTask() {
        let entries = TermTimeline.entries(tasks: [], events: [allDayEvent("Quiz 1", 9, 10)],
                                           calendar: eastern)
        let horizons = TermTimeline.byWeekHorizon(entries: entries, now: now, calendar: eastern)
        XCTAssertEqual(horizons[.overdue]?.map(\.title), ["Quiz 1"])
    }

    func testDoneTasksNeverReachTheTimeline() {
        var finished = task("Problem set 3", 9, 25)
        finished.done = true
        let entries = TermTimeline.entries(tasks: [finished], events: [], calendar: eastern)
        XCTAssertTrue(entries.isEmpty)
    }
}
