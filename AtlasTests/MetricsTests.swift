import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

// MARK: - Helpers

/// Build TaskItem cleanly without fighting the memberwise init ordering.
private func makeTask(title: String, done: Bool = false, scheduledAt: Date? = nil, spaceName: String = "Work") -> TaskItem {
    var t = TaskItem(title: title, dueLabel: "")
    t.done = done
    t.scheduledAt = scheduledAt
    t.spaceName = spaceName
    return t
}

/// Build CalendarEvent from minimal fields.
private func makeEvent(title: String, start: Date, spaceName: String = "Work") -> CalendarEvent {
    CalendarEvent(
        title: title, subtitle: "",
        start: start, end: start.addingTimeInterval(3600),
        color: .blue, spaceName: spaceName
    )
}

/// Build Space from name and color.
private func makeSpace(_ name: String, _ color: Color = .blue) -> Space {
    Space(id: UUID(), name: name, color: color, projects: [])
}

/// Build Goal.
private func makeGoal(progress: Double) -> Goal {
    Goal(id: UUID(), title: "Goal", progress: progress, label: "")
}

// MARK: - Deterministic calendar + dates

/// ISO-style Gregorian calendar fixed to UTC so week boundaries are consistent.
private func testCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2          // Monday — consistent across all locales
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

/// June 25, 2026 12:00 UTC — a known Thursday, safely mid-week in any Monday-first system.
private func fixedThursday(cal: Calendar) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 6; c.day = 25
    c.hour = 12; c.minute = 0; c.second = 0
    return cal.date(from: c)!
}

// MARK: - Tests

final class MetricsTests: XCTestCase {

    private let cal = testCalendar()
    private var thursday: Date = Date()   // set in setUp so we can access cal

    override func setUp() {
        super.setUp()
        thursday = fixedThursday(cal: cal)
    }

    // MARK: Task counts

    func testTaskCounts_openDoneScheduled() {
        let tasks = [
            makeTask(title: "T1", done: true),
            makeTask(title: "T2", done: true),
            makeTask(title: "T3", scheduledAt: thursday),   // open + scheduled
            makeTask(title: "T4"),
            makeTask(title: "T5"),
        ]

        let m = AtlasMetrics.compute(
            tasks: tasks, events: [], goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.totalTasks,    5)
        XCTAssertEqual(m.openTasks,     3,  "Tasks 3-5 are not done")
        XCTAssertEqual(m.doneTasks,     2,  "Tasks 1-2 are done")
        XCTAssertEqual(m.scheduledTasks, 1, "Only T3 has scheduledAt set")
    }

    // MARK: Event counts

    func testEventCounts_todayAndThisWeek() {
        // Thursday June 25 = today (eventsToday)
        let todayEvent = makeEvent(title: "Today", start: thursday)

        // Friday June 26 = still this week in Mon-first calendar
        let friday = cal.date(byAdding: .day, value: 1, to: thursday)!
        let thisWeekEvent = makeEvent(title: "Friday", start: friday)

        // 8 days later = next week
        let nextWeek = cal.date(byAdding: .day, value: 8, to: thursday)!
        let nextWeekEvent = makeEvent(title: "Next week", start: nextWeek)

        let m = AtlasMetrics.compute(
            tasks: [], events: [todayEvent, thisWeekEvent, nextWeekEvent],
            goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.eventsToday,    1, "Only June 25 event is today")
        XCTAssertEqual(m.eventsThisWeek, 2, "June 25+26 are in this week; July 3 is not")
    }

    // MARK: Goal average

    func testGoalAvgProgress() {
        let goals = [makeGoal(progress: 0.5), makeGoal(progress: 1.0)]

        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: goals, spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.goalAvgProgress, 0.75, accuracy: 0.001)
    }

    func testGoalAvgProgress_noGoals() {
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )
        XCTAssertEqual(m.goalAvgProgress, 0.0)
    }

    // MARK: Completion rate

    func testCompletionRate() {
        let tasks = [
            makeTask(title: "A", done: true),
            makeTask(title: "B", done: true),
            makeTask(title: "C"),
            makeTask(title: "D"),
            makeTask(title: "E"),
        ]

        let m = AtlasMetrics.compute(
            tasks: tasks, events: [], goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.completionRate, 0.4, accuracy: 0.001, "2 done / 5 total = 40 %")
    }

    func testCompletionRate_noTasks() {
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )
        XCTAssertEqual(m.completionRate, 0.0, accuracy: 0.001, "Guard against divide-by-zero")
    }

    // MARK: Per-space load

    func testPerSpaceLoad() {
        let spaceWork     = makeSpace("Work", .blue)
        let spacePersonal = makeSpace("Personal", .green)

        let tasks = [
            makeTask(title: "A", done: true,  spaceName: "Work"),
            makeTask(title: "B",               spaceName: "Work"),
            makeTask(title: "C", scheduledAt: thursday, spaceName: "Personal"),
        ]

        let m = AtlasMetrics.compute(
            tasks: tasks, events: [], goals: [], spaces: [spaceWork, spacePersonal], notes: [],
            calendar: cal, referenceDate: thursday
        )

        let work     = m.perSpace.first { $0.spaceName == "Work" }
        let personal = m.perSpace.first { $0.spaceName == "Personal" }

        XCTAssertNotNil(work)
        XCTAssertEqual(work?.totalCount, 2)
        XCTAssertEqual(work?.openCount,  1, "A is done; B is open")

        XCTAssertNotNil(personal)
        XCTAssertEqual(personal?.totalCount, 1)
        XCTAssertEqual(personal?.openCount,  1, "C is not done")
    }

    // MARK: Note count

    func testNoteCount() {
        let notes = [Note(title: "N1", body: ""), Note(title: "N2", body: ""), Note(title: "N3", body: "")]
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: notes,
            calendar: cal, referenceDate: thursday
        )
        XCTAssertEqual(m.noteCount, 3)
    }

    // MARK: Full scenario (mirrors task-8 brief)

    func testFullScenario() {
        // 5 tasks: 2 done, 1 scheduled-but-open, 2 plain open
        let tasks = [
            makeTask(title: "T1", done: true,  spaceName: "Alpha"),
            makeTask(title: "T2", done: true,  spaceName: "Alpha"),
            makeTask(title: "T3", scheduledAt: thursday, spaceName: "Beta"),   // open
            makeTask(title: "T4",               spaceName: "Alpha"),
            makeTask(title: "T5",               spaceName: "Beta"),
        ]

        // 3 events: 1 today, 1 this week, 1 next week
        let friday   = cal.date(byAdding: .day, value: 1, to: thursday)!
        let nextWeek = cal.date(byAdding: .day, value: 8, to: thursday)!
        let events = [
            makeEvent(title: "E1", start: thursday,  spaceName: "Alpha"),
            makeEvent(title: "E2", start: friday,    spaceName: "Beta"),
            makeEvent(title: "E3", start: nextWeek,  spaceName: "Alpha"),
        ]

        let goals = [makeGoal(progress: 0.5), makeGoal(progress: 1.0)]

        let alpha = makeSpace("Alpha", .blue)
        let beta  = makeSpace("Beta",  .red)

        let m = AtlasMetrics.compute(
            tasks: tasks, events: events, goals: goals,
            spaces: [alpha, beta], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.openTasks,       3,    "T3, T4, T5 are not done")
        XCTAssertEqual(m.doneTasks,       2,    "T1, T2 are done")
        XCTAssertEqual(m.scheduledTasks,  1,    "Only T3 has scheduledAt")
        XCTAssertEqual(m.eventsToday,     1,    "Only E1 is today")
        XCTAssertEqual(m.eventsThisWeek,  2,    "E1 + E2 in week; E3 next week")
        XCTAssertEqual(m.goalAvgProgress, 0.75, accuracy: 0.001)
        XCTAssertEqual(m.completionRate,  0.4,  accuracy: 0.001)

        // Alpha: T1(done), T2(done), T4(open) → total=3, open=1
        let alphaLoad = m.perSpace.first { $0.spaceName == "Alpha" }
        XCTAssertEqual(alphaLoad?.totalCount, 3)
        XCTAssertEqual(alphaLoad?.openCount,  1)

        // Beta: T3(open+scheduled), T5(open) → total=2, open=2
        let betaLoad = m.perSpace.first { $0.spaceName == "Beta" }
        XCTAssertEqual(betaLoad?.totalCount, 2)
        XCTAssertEqual(betaLoad?.openCount,  2)
    }
}
