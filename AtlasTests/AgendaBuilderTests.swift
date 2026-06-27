import XCTest
@testable import Atlas

/// Ordering / membership rules for the agenda (List) view. Injected Gregorian/UTC
/// calendar; all Dates derived from it (no hardcoded clock strings). Assertions
/// compare titles in the order the builder emits them.
final class AgendaBuilderTests: XCTestCase {

    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let c = Calendar(identifier: .gregorian)

    /// Build a date at a fixed offset/time from a stable anchor (2026-06-25 00:00 UTC).
    private func at(_ calendar: Calendar, dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        let anchor = calendar.date(from: comps)!
        let base = calendar.date(byAdding: .day, value: dayOffset, to: anchor)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    private func event(_ title: String, start: Date, durationMin: Int = 60, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            title: title,
            subtitle: "",
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationMin * 60)),
            color: .blue,
            spaceName: "School",
            isAllDay: allDay
        )
    }

    private func task(_ title: String, scheduledAt: Date? = nil, due: Date? = nil, done: Bool = false) -> TaskItem {
        var t = TaskItem(title: title, dueLabel: "")
        t.scheduledAt = scheduledAt
        t.dueDate = due
        t.done = done
        return t
    }

    // MARK: day ordering

    func testSectionsAreDayAscending() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let events = [
            event("d2", start: at(cal, dayOffset: 2, hour: 9)),
            event("d0", start: at(cal, dayOffset: 0, hour: 9)),
            event("d1", start: at(cal, dayOffset: 1, hour: 9)),
        ]
        let sections = AgendaBuilder.build(events: events, tasks: [], from: from, calendar: cal)
        XCTAssertEqual(sections.map { cal.startOfDay(for: $0.day) },
                       [0, 1, 2].map { cal.startOfDay(for: at(cal, dayOffset: $0, hour: 0)) })
        XCTAssertEqual(sections.flatMap { $0.items.map(\.title) }, ["d0", "d1", "d2"])
    }

    // MARK: intra-day ordering

    func testWithinDayAllDayFirstThenByTimeThenTitle() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let events = [
            event("noon",     start: at(cal, dayOffset: 0, hour: 12)),
            event("allday",   start: at(cal, dayOffset: 0, hour: 0), allDay: true),
            event("morning",  start: at(cal, dayOffset: 0, hour: 9)),
            event("zeta9",    start: at(cal, dayOffset: 0, hour: 9)),  // same time as morning → title tiebreak
        ]
        let sections = AgendaBuilder.build(events: events, tasks: [], from: from, calendar: cal)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.map(\.title), ["allday", "morning", "zeta9", "noon"])
    }

    // MARK: merge of events + tasks

    func testMergesEventsAndScheduledTasksByTime() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let events = [event("event10", start: at(cal, dayOffset: 0, hour: 10))]
        let tasks = [
            task("task8",  scheduledAt: at(cal, dayOffset: 0, hour: 8)),
            task("task14", scheduledAt: at(cal, dayOffset: 0, hour: 14)),
        ]
        let sections = AgendaBuilder.build(events: events, tasks: tasks, from: from, calendar: cal)
        XCTAssertEqual(sections.flatMap { $0.items.map(\.title) }, ["task8", "event10", "task14"])
        // The scheduled tasks are tagged as such.
        let kinds = Dictionary(uniqueKeysWithValues:
            sections.flatMap { $0.items }.map { ($0.title, $0.kind) })
        XCTAssertEqual(kinds["task8"], .task)
        XCTAssertEqual(kinds["event10"], .event)
    }

    func testDueOnlyTaskIsAllDayAndSortsFirst() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let events = [event("morning", start: at(cal, dayOffset: 0, hour: 9))]
        let tasks  = [task("dueonly", due: at(cal, dayOffset: 0, hour: 17))]  // due 5pm but no slot
        let sections = AgendaBuilder.build(events: events, tasks: tasks, from: from, calendar: cal)
        // Due-only task is treated as all-day → renders before the 9am event.
        XCTAssertEqual(sections[0].items.map(\.title), ["dueonly", "morning"])
        XCTAssertTrue(sections[0].items.first { $0.title == "dueonly" }!.allDay)
    }

    // MARK: exclusions

    func testExcludesDoneTasks() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let tasks = [
            task("open", scheduledAt: at(cal, dayOffset: 0, hour: 9)),
            task("done", scheduledAt: at(cal, dayOffset: 0, hour: 10), done: true),
        ]
        let sections = AgendaBuilder.build(events: [], tasks: tasks, from: from, calendar: cal)
        XCTAssertEqual(sections.flatMap { $0.items.map(\.title) }, ["open"])
    }

    func testExcludesPastEventsBeforeFromDay() {
        let cal = cal()
        let from = at(cal, dayOffset: 0, hour: 0)
        let events = [
            event("yesterday", start: at(cal, dayOffset: -1, hour: 9)),
            event("today",     start: at(cal, dayOffset: 0, hour: 9)),
        ]
        let sections = AgendaBuilder.build(events: events, tasks: [], from: from, calendar: cal)
        XCTAssertEqual(sections.flatMap { $0.items.map(\.title) }, ["today"])
    }

    func testEmptyInputs() {
        XCTAssertTrue(AgendaBuilder.build(events: [], tasks: [], from: Date(), calendar: cal()).isEmpty)
    }
}
