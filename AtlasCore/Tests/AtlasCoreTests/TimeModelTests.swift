import XCTest
@testable import AtlasCore

/// Phase 2 (time model & calendar language): late detection, the reserved red state,
/// and the deadline↔work-session planned-time math. All pure — a fixed `now` and an
/// explicit `Calendar` keep every assertion deterministic.
final class TimeModelTests: XCTestCase {

    private let cal = Calendar.current
    /// A fixed "now" at 10 AM today, so "due at 5 PM today" is genuinely still ahead.
    private var now: Date { cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! }

    private func task(_ title: String, due: Date? = nil, scheduled: Date? = nil,
                      done: Bool = false, originalDue: Date? = nil) -> TaskItem {
        var t = TaskItem(title: title, dueLabel: "", done: done, scheduledAt: scheduled, dueDate: due)
        t.originalDueDate = originalDue
        return t
    }

    private func daysFromToday(_ days: Int, hour: Int = 17) -> Date {
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    // MARK: - Late detection

    func test_lateItems_picksUpOnlyOverdueOpenTasks() {
        let items = TimeModel.lateItems(tasks: [
            task("Missed essay", due: daysFromToday(-3)),
            task("Due today", due: daysFromToday(0)),
            task("Future", due: daysFromToday(4)),
            task("Undated"),
            task("Already done", due: daysFromToday(-5), done: true)
        ], now: now, calendar: cal)

        XCTAssertEqual(items.map(\.title), ["Missed essay"])
        XCTAssertEqual(items.first?.daysLate, 3)
    }

    /// Something due at 5 PM today is DUE TODAY, not late — day granularity, not `< now`.
    func test_dueLaterToday_isNotLate() {
        let items = TimeModel.lateItems(tasks: [task("Lab", due: daysFromToday(0))], now: now, calendar: cal)
        XCTAssertTrue(items.isEmpty)
    }

    func test_lateItems_sortOldestFirst() {
        let items = TimeModel.lateItems(tasks: [
            task("Two days", due: daysFromToday(-2)),
            task("Nine days", due: daysFromToday(-9)),
            task("One day", due: daysFromToday(-1))
        ], now: now, calendar: cal)
        XCTAssertEqual(items.map(\.title), ["Nine days", "Two days", "One day"])
    }

    /// After a late-reschedule the ORIGINAL due date is what the bar reports — the miss
    /// survives visibly, and "days late" keeps counting from the original date.
    func test_rescheduledLateItem_reportsOriginalDueDate() {
        let original = daysFromToday(-6)
        let items = TimeModel.lateItems(
            tasks: [task("Rewrite", due: daysFromToday(-1), originalDue: original)],
            now: now, calendar: cal
        )
        XCTAssertEqual(items.first?.originalDue, original)
        XCTAssertEqual(items.first?.daysLate, 6)
    }

    func test_daysLateLabel_singularAndPlural() {
        XCTAssertEqual(TimeModel.daysLateLabel(1), "1 day late")
        XCTAssertEqual(TimeModel.daysLateLabel(4), "4 days late")
    }

    // MARK: - Red is reserved

    func test_dueTodayWithNoPlan_isRed() {
        XCTAssertTrue(TimeModel.isDueTodayUnplanned(task("Problem set", due: daysFromToday(0)),
                                                    now: now, calendar: cal))
    }

    func test_dueTodayWithPlannedSession_isNotRed() {
        let planned = task("Problem set", due: daysFromToday(0), scheduled: daysFromToday(0, hour: 13))
        XCTAssertFalse(TimeModel.isDueTodayUnplanned(planned, now: now, calendar: cal))
    }

    /// Overdue is amber, never red — red graveyards cause avoidance.
    func test_overdueUnplanned_isNotRed() {
        XCTAssertFalse(TimeModel.isDueTodayUnplanned(task("Old", due: daysFromToday(-2)),
                                                     now: now, calendar: cal))
    }

    func test_doneOrUndated_isNotRed() {
        XCTAssertFalse(TimeModel.isDueTodayUnplanned(task("Done", due: daysFromToday(0), done: true),
                                                     now: now, calendar: cal))
        XCTAssertFalse(TimeModel.isDueTodayUnplanned(task("Undated"), now: now, calendar: cal))
    }

    // MARK: - Planned-time math

    func test_plannedLabel_withEstimate_readsAsFill() {
        XCTAssertEqual(TimeModel.plannedLabel(estimateMin: 240, sessionMinutes: [90, 60]),
                       "2.5h of 4h planned")
    }

    func test_plannedLabel_withEstimateAndNoSessions_readsZero() {
        XCTAssertEqual(TimeModel.plannedLabel(estimateMin: 120, sessionMinutes: []),
                       "0h of 2h planned")
    }

    /// No estimate ⇒ a session COUNT, per the optional-estimate rule.
    func test_plannedLabel_withoutEstimate_countsSessions() {
        XCTAssertEqual(TimeModel.plannedLabel(estimateMin: nil, sessionMinutes: []), "No time planned")
        XCTAssertEqual(TimeModel.plannedLabel(estimateMin: nil, sessionMinutes: [60]), "1 session planned")
        XCTAssertEqual(TimeModel.plannedLabel(estimateMin: nil, sessionMinutes: [60, 30]), "2 sessions planned")
    }

    func test_plannedFraction_clampsAndNilsWithoutEstimate() {
        XCTAssertEqual(TimeModel.plannedFraction(estimateMin: 240, sessionMinutes: [60]) ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(TimeModel.plannedFraction(estimateMin: 60, sessionMinutes: [600]) ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertNil(TimeModel.plannedFraction(estimateMin: nil, sessionMinutes: [60]))
        XCTAssertNil(TimeModel.plannedFraction(estimateMin: 0, sessionMinutes: [60]))
    }

    func test_hoursLabel_formats() {
        XCTAssertEqual(TimeModel.hoursLabel(0), "0h")
        XCTAssertEqual(TimeModel.hoursLabel(45), "45m")
        XCTAssertEqual(TimeModel.hoursLabel(60), "1h")
        XCTAssertEqual(TimeModel.hoursLabel(150), "2.5h")
    }

    // MARK: - "+ more time"

    /// One click = the same clock time TOMORROW. Predictable, never a "smart" slot.
    func test_nextSessionSlot_isSameTimeTomorrow() {
        let past = daysFromToday(-2, hour: 14)
        let next = TimeModel.nextSessionSlot(after: past, now: now, calendar: cal)
        let expectedDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        XCTAssertTrue(cal.isDate(next, inSameDayAs: expectedDay))
        XCTAssertEqual(cal.component(.hour, from: next), 14)
        XCTAssertEqual(cal.component(.minute, from: next), 0)
    }
}
