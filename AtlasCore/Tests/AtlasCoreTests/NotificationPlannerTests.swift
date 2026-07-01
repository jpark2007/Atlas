import XCTest
import SwiftUI
@testable import AtlasCore

final class NotificationPlannerTests: XCTestCase {

    let cal = Calendar.current

    // Fixed reference clock: 2026-07-01 06:00 local.
    private var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 6, minute: 0))!
    }

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Fixtures

    private let schoolID = UUID()
    private let personalID = UUID()

    private func makeSnapshot(
        events: [CalendarEvent] = [],
        tasks: [TaskItem] = []
    ) -> AtlasSnapshot {
        let school = Space(id: schoolID, name: "School", color: .blue, projects: [])
        let personal = Space(id: personalID, name: "Personal", color: .green, projects: [])
        return AtlasSnapshot(spaces: [school, personal], projects: [],
                             tasks: tasks, events: events, notes: [], goals: [])
    }

    private func event(_ title: String, space: String, start: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: title, subtitle: "", start: start, end: start.addingTimeInterval(3600),
                      color: .blue, spaceName: space, isAllDay: allDay)
    }

    private func task(_ title: String, space: String, due: Date?, scheduledAt: Date? = nil, done: Bool = false) -> TaskItem {
        TaskItem(title: title, dueLabel: "", done: done, scheduledAt: scheduledAt,
                 dueDate: due, spaceName: space)
    }

    private func defaultPrefs(enabled: Bool = true,
                              events: Bool = true, tasksDue: Bool = true,
                              digest: Bool = true, overdue: Bool = true,
                              leadMinutes: Int = 15,
                              digestHour: Int = 8, digestMinute: Int = 0,
                              spaceIds: [UUID]? = nil) -> NotificationPlanner.Prefs {
        NotificationPlanner.Prefs(enabled: enabled, events: events, tasksDue: tasksDue,
                                  digest: digest, overdue: overdue, leadMinutes: leadMinutes,
                                  digestHour: digestHour, digestMinute: digestMinute, spaceIds: spaceIds)
    }

    // MARK: - Master switch

    func test_masterOff_returnsEmpty() {
        let snap = makeSnapshot(events: [event("Standup", space: "School", start: at(7, 1, 9, 30))])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(enabled: false),
                                              now: now, horizonDays: 7)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Event reminders

    func test_eventReminder_firesAtStartMinusLead() {
        let ev = event("Standup", space: "School", start: at(7, 1, 9, 30))
        let snap = makeSnapshot(events: [ev])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(leadMinutes: 15),
                                              now: now, horizonDays: 7)
        let n = result.first { $0.id == "event-\(ev.id.uuidString)" }
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.fireDate, at(7, 1, 9, 15))
    }

    func test_eventsToggleOff_excludesEventReminders() {
        let ev = event("Standup", space: "School", start: at(7, 1, 9, 30))
        let snap = makeSnapshot(events: [ev])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(events: false),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id.hasPrefix("event-") })
    }

    func test_pastEvent_excluded() {
        // Fires at 04:45, before now (06:00).
        let ev = event("Early", space: "School", start: at(7, 1, 5, 0))
        let snap = makeSnapshot(events: [ev])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id == "event-\(ev.id.uuidString)" })
    }

    func test_eventBeyondHorizon_excluded() {
        let ev = event("FarOff", space: "School", start: at(7, 20, 9, 0))
        let snap = makeSnapshot(events: [ev])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id == "event-\(ev.id.uuidString)" })
    }

    // MARK: - Task reminders

    func test_timedTaskReminder_firesAtScheduledMinusLead() {
        let t = task("Gym", space: "Personal", due: at(7, 1, 0, 0), scheduledAt: at(7, 1, 17, 0))
        let snap = makeSnapshot(tasks: [t])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(leadMinutes: 30),
                                              now: now, horizonDays: 7)
        let n = result.first { $0.id == "task-\(t.id.uuidString)" }
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.fireDate, at(7, 1, 16, 30))
    }

    func test_dueOnlyTaskReminder_firesMorningOfDueDay() {
        // Due today at midnight, no time → reminder at 09:00 on the due day.
        let t = task("Essay", space: "School", due: at(7, 2, 0, 0))
        let snap = makeSnapshot(tasks: [t])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        let n = result.first { $0.id == "task-\(t.id.uuidString)" }
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.fireDate, at(7, 2, 9, 0))
    }

    func test_doneTask_excluded() {
        let t = task("Done", space: "School", due: at(7, 2, 0, 0), done: true)
        let snap = makeSnapshot(tasks: [t])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id == "task-\(t.id.uuidString)" })
    }

    // MARK: - Space filter

    func test_spaceFilter_limitsToChosenSpaces() {
        let standup = event("Standup", space: "School", start: at(7, 1, 9, 30))
        let gym = task("Gym", space: "Personal", due: at(7, 1, 0, 0), scheduledAt: at(7, 1, 17, 0))
        let snap = makeSnapshot(events: [standup], tasks: [gym])
        let result = NotificationPlanner.plan(snapshot: snap,
                                              prefs: defaultPrefs(spaceIds: [personalID]),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id == "event-\(standup.id.uuidString)" })
        XCTAssertTrue(result.contains { $0.id == "task-\(gym.id.uuidString)" })
    }

    // MARK: - Digest

    func test_digest_firesAtPrefTime_withCounts() {
        let standup = event("Standup", space: "School", start: at(7, 1, 9, 30))
        let essay = task("Essay", space: "School", due: at(7, 1, 0, 0))
        let gym = task("Gym", space: "Personal", due: at(7, 1, 0, 0), scheduledAt: at(7, 1, 17, 0))
        let snap = makeSnapshot(events: [standup], tasks: [essay, gym])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(digestHour: 8),
                                              now: now, horizonDays: 1)
        let digest = result.first { $0.id.hasPrefix("digest-") }
        XCTAssertNotNil(digest)
        XCTAssertEqual(digest?.fireDate, at(7, 1, 8, 0))
        // 1 event + 2 tasks that day.
        XCTAssertEqual(digest?.body, "1 event · 2 tasks")
    }

    func test_digestOff_excludesDigest() {
        let standup = event("Standup", space: "School", start: at(7, 1, 9, 30))
        let snap = makeSnapshot(events: [standup])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(digest: false),
                                              now: now, horizonDays: 1)
        XCTAssertFalse(result.contains { $0.id.hasPrefix("digest-") })
    }

    // MARK: - Overdue

    func test_overdueNudge_whenTaskPastDue() {
        let late = task("Late", space: "School", due: at(6, 30, 0, 0))
        let snap = makeSnapshot(tasks: [late])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        XCTAssertTrue(result.contains { $0.id.hasPrefix("overdue-") })
    }

    func test_overdueOff_excludesNudge() {
        let late = task("Late", space: "School", due: at(6, 30, 0, 0))
        let snap = makeSnapshot(tasks: [late])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(overdue: false),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.contains { $0.id.hasPrefix("overdue-") })
    }

    // MARK: - Ordering, cap, determinism

    func test_output_sortedByFireDateAndCappedAt60() {
        var events: [CalendarEvent] = []
        for i in 0..<100 {
            events.append(event("E\(i)", space: "School", start: now.addingTimeInterval(Double(i + 1) * 3600)))
        }
        let snap = makeSnapshot(events: events)
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(digest: false, overdue: false),
                                              now: now, horizonDays: 30)
        XCTAssertLessThanOrEqual(result.count, 60)
        XCTAssertEqual(result, result.sorted { $0.fireDate < $1.fireDate })
    }

    func test_allFireDatesAreInFuture() {
        let snap = makeSnapshot(
            events: [event("Standup", space: "School", start: at(7, 1, 9, 30))],
            tasks: [task("Essay", space: "School", due: at(7, 2, 0, 0)),
                    task("Late", space: "School", due: at(6, 30, 0, 0))])
        let result = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(),
                                              now: now, horizonDays: 7)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.fireDate > now })
    }

    func test_deterministic_sameInputSameOutput() {
        let snap = makeSnapshot(
            events: [event("Standup", space: "School", start: at(7, 1, 9, 30))],
            tasks: [task("Essay", space: "School", due: at(7, 2, 0, 0))])
        let a = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(), now: now, horizonDays: 7)
        let b = NotificationPlanner.plan(snapshot: snap, prefs: defaultPrefs(), now: now, horizonDays: 7)
        XCTAssertEqual(a, b)
    }
}
