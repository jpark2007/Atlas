import XCTest
import SwiftUI
@testable import AtlasCore

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
private func makeEvent(
    title: String,
    start: Date,
    spaceName: String = "Work",
    source: EventSource = .atlas
) -> CalendarEvent {
    var e = CalendarEvent(
        title: title, subtitle: "",
        start: start, end: start.addingTimeInterval(3600),
        color: .blue, spaceName: spaceName
    )
    e.source = source
    return e
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

    /// An imported `.ics` exam, a Canvas feed item and a Google event are all just events:
    /// none of them is Atlas-native, and every one is a real commitment on the day.
    func testEventCounts_includeExternallySourcedEvents() {
        let events = [
            makeEvent(title: "Midterm exam", start: thursday, source: .atlas),                 // imported .ics one-off
            makeEvent(title: "Chem lab quiz", start: thursday, source: .canvas),               // Canvas feed
            makeEvent(title: "Advisor meeting", start: thursday, source: .google),             // Google
            makeEvent(title: "Registrar drop-in", start: thursday, source: .apple),            // Apple (in-memory pool)
            makeEvent(title: "Robotics club", start: thursday, source: .icsFeed(name: "Club")),// generic ICS feed
        ]

        let m = AtlasMetrics.compute(
            tasks: [], events: events, goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.eventsToday, 5, "Every source counts once — none is second-class")
    }

    /// Work-blocks and deadline markers are TASKS drawn on the grid. Counting them as
    /// events would report the same task twice.
    func testEventCounts_excludeWorkBlocksAndDeadlineMarkers() {
        var block = makeEvent(title: "Work: essay", start: thursday)
        block.isWorkBlock = true
        var marker = makeEvent(title: "Essay due", start: thursday)
        marker.isDeadline = true

        let m = AtlasMetrics.compute(
            tasks: [], events: [block, marker, makeEvent(title: "Standup", start: thursday)],
            goals: [], spaces: [], notes: [],
            calendar: cal, referenceDate: thursday
        )

        XCTAssertEqual(m.eventsToday, 1, "Only the real event counts")
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

// MARK: - School world

/// Metrics with a term and classes in play. Class meetings are never stored rows, so
/// these cover the synthesis Metrics has to do for itself.
///
/// `Term.contains` and `SchoolCalendar.time` resolve against `Calendar.current`, so this
/// suite uses the current calendar and picks a term wide enough that no time zone can
/// push the reference day outside it.
final class MetricsSchoolTests: XCTestCase {

    private let cal = Calendar.current

    /// June 25 2026, midday — a Thursday.
    private var midJune: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 25; c.hour = 12
        return cal.date(from: c)!
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = 12
        return cal.date(from: c)!
    }

    /// A term covering all of June — any week containing June 25 sits inside it.
    private var summer: Term {
        Term(name: "Summer 2026", startsOn: date(6, 1), endsOn: date(6, 30))
    }

    /// A class meeting 10:00–10:50 every single weekday, so the assertions don't depend
    /// on which day the locale starts its week on.
    private func dailyClass(_ name: String = "Bio 201") -> Project {
        var p = Project(name: name, code: "BIO 201", isClass: true,
                        spaceName: "School", spaceColor: .blue)
        p.meetingPattern = [MeetingBlock(weekdays: [1, 2, 3, 4, 5, 6, 7],
                                         start: "10:00", end: "10:50", location: "Tech 204")]
        return p
    }

    private func makeTask(_ title: String, done: Bool = false, spaceName: String) -> TaskItem {
        var t = TaskItem(title: title, dueLabel: "")
        t.done = done
        t.spaceName = spaceName
        return t
    }

    // MARK: Class meetings count as events

    func testClassMeetingsCountAsEvents() {
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertEqual(m.eventsToday, 1, "Today's lecture is an event on today")
        XCTAssertEqual(m.eventsThisWeek, 7, "One lecture per day across the week")
    }

    func testNoTermMeansNoSynthesizedMeetings() {
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: nil,
            calendar: cal, referenceDate: midJune
        )
        XCTAssertEqual(m.eventsToday, 0)
        XCTAssertEqual(m.eventsThisWeek, 0)
    }

    func testArchivedClassDoesNotMeet() {
        var archived = dailyClass()
        archived.archivedAt = date(6, 10)

        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            classes: [archived], term: summer,
            calendar: cal, referenceDate: midJune
        )
        XCTAssertEqual(m.eventsThisWeek, 0, "Last term's class is not on this week's calendar")
    }

    /// The same lecture arriving from Google as well as from the class pattern is ONE
    /// commitment — the count must not double.
    func testImportedCopyOfALectureIsNotCountedTwice() {
        let start = SchoolCalendar.time("10:00", on: midJune, calendar: cal)!
        var google = CalendarEvent(
            title: "Bio 201", subtitle: "",
            start: start, end: start.addingTimeInterval(50 * 60),
            color: .blue, spaceName: "School"
        )
        google.source = .google

        let m = AtlasMetrics.compute(
            tasks: [], events: [google], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertEqual(m.eventsToday, 1, "The Google copy collapses into the synthesized meeting")
    }

    /// An imported exam is a distinct event, not a duplicate of the lecture.
    func testImportedExamCountsAlongsideTheLecture() {
        let exam = CalendarEvent(
            title: "Bio 201 midterm exam", subtitle: "",
            start: SchoolCalendar.time("14:00", on: midJune, calendar: cal)!,
            end:   SchoolCalendar.time("16:00", on: midJune, calendar: cal)!,
            color: .blue, spaceName: "School"
        )

        let m = AtlasMetrics.compute(
            tasks: [], events: [exam], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertEqual(m.eventsToday, 2, "Lecture + exam")
    }

    // MARK: Completion + By space

    /// A class meeting is not something you complete: the completion rate is over tasks,
    /// and adding classes must not move it.
    func testClassMeetingsDoNotAffectCompletionRate() {
        let tasks = [
            makeTask("Read ch. 4", done: true, spaceName: "School"),
            makeTask("Problem set", spaceName: "School"),
        ]

        let m = AtlasMetrics.compute(
            tasks: tasks, events: [], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertEqual(m.totalTasks, 2, "Meetings are events, never tasks")
        XCTAssertEqual(m.completionRate, 0.5, accuracy: 0.001)
    }

    /// Classes live under the School section rather than under SPACES in the sidebar, but
    /// their coursework still belongs to the School space — one School row, counted once.
    func testCourseworkRollsUpUnderSchoolExactlyOnce() {
        let school = Space(id: UUID(), name: "School", color: .blue, projects: [dailyClass(), dailyClass("Chem 101")])
        let tasks = [
            makeTask("Bio reading", done: true, spaceName: "School"),
            makeTask("Bio lab report", spaceName: "School"),
            makeTask("Chem problem set", spaceName: "School"),
            makeTask("Groceries", spaceName: "Personal"),
        ]

        let m = AtlasMetrics.compute(
            tasks: tasks, events: [], goals: [], spaces: [school, Space(id: UUID(), name: "Personal", color: .green, projects: [])],
            notes: [], classes: school.projects, term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertEqual(m.perSpace.filter { $0.spaceName == "School" }.count, 1,
                       "Two classes must not become two School rows")
        let schoolLoad = m.perSpace.first { $0.spaceName == "School" }
        XCTAssertEqual(schoolLoad?.totalCount, 3)
        XCTAssertEqual(schoolLoad?.openCount, 2)
        XCTAssertEqual(m.perSpace.count, 2, "School + Personal")
    }

    /// A term with classes but no ordinary projects and no tasks: the calendar numbers are
    /// real, the task-derived ones are honestly zero, and nothing traps.
    func testTermWithClassesButNoTasks() {
        let m = AtlasMetrics.compute(
            tasks: [], events: [], goals: [], spaces: [], notes: [],
            classes: [dailyClass()], term: summer,
            calendar: cal, referenceDate: midJune
        )

        XCTAssertTrue(m.perSpace.isEmpty, "No tasks ⇒ no space load, not a crash")
        XCTAssertEqual(m.totalTasks, 0)
        XCTAssertEqual(m.completionRate, 0.0)
        XCTAssertEqual(m.eventsToday, 1, "The timetable is still real")
    }
}
