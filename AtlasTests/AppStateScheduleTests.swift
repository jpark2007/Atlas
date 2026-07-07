import XCTest
@testable import AtlasCore
@testable import Atlas

@MainActor
final class AppStateScheduleTests: XCTestCase {
    private let cal = Calendar.current
    /// A fixed day with no MockData events (those land on the real "today").
    private var day: Date { cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000)) }
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }

    // MARK: setDueDate

    func testSetDueDateUpdatesDateAndLabel() {
        let state = AppState()
        let t = state.addTask(title: "Essay")
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        state.setDueDate(taskId: t.id, date: due)
        let updated = state.tasks.first { $0.id == t.id }!
        XCTAssertEqual(updated.dueDate, due)
        XCTAssertEqual(updated.dueLabel, TaskItem.dueLabel(for: due))
    }

    func testSetDueDateNilClears() {
        let state = AppState()
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t = state.addTask(title: "Essay", dueDate: due)
        XCTAssertFalse(t.dueLabel.isEmpty)
        state.setDueDate(taskId: t.id, date: nil)
        let updated = state.tasks.first { $0.id == t.id }!
        XCTAssertNil(updated.dueDate)
        XCTAssertEqual(updated.dueLabel, "")
    }

    // MARK: suggestSlot

    func testSuggestSlotReturnsStartHourOnEmptyDay() {
        let state = AppState()
        let t = state.addTask(title: "Study", durationMin: 60)
        let slot = state.suggestSlot(for: t, on: day, now: at(0))
        XCTAssertEqual(slot, at(CalendarLayout.workdayStartHour))
    }

    func testSuggestSlotAvoidsAnAlreadyScheduledTask() {
        let state = AppState()
        let blocker = state.addTask(title: "Blocker", durationMin: 60)
        state.schedule(taskId: blocker.id, at: at(CalendarLayout.workdayStartHour))
        let t = state.addTask(title: "Study", durationMin: 60)
        let slot = state.suggestSlot(for: t, on: day, now: at(0))
        XCTAssertEqual(slot, at(CalendarLayout.workdayStartHour + 1))
    }

    // MARK: revert-after-slot via unscheduledTasks (the "needs replan" rule)

    func testOverduePastSlotResurfacesInTray() {
        let state = AppState()
        let base = at(9)
        // 30-min slot ending 9:30, due 9:30. Once both pass it's overdue → back to the tray.
        let t = state.addTask(title: "Past block", dueDate: at(9, 30), durationMin: 30)
        state.schedule(taskId: t.id, at: base)

        // Before the slot ends and before it's due → not in the tray.
        state.now = base
        XCTAssertFalse(state.unscheduledTasks.contains { $0.id == t.id })

        // After the slot elapses AND the due date has passed → resurfaces (overdue).
        state.now = base.addingTimeInterval(60 * 60)
        XCTAssertTrue(state.unscheduledTasks.contains { $0.id == t.id })
    }

    func testNonOverduePastSlotStaysOnGrid() {
        let state = AppState()
        let base = at(9)
        // Slot elapses but the due date is hours away → stays on the grid (dimmed), not the tray.
        let t = state.addTask(title: "Past block, due later", dueDate: at(20), durationMin: 30)
        state.schedule(taskId: t.id, at: base)

        state.now = base.addingTimeInterval(60 * 60)
        XCTAssertFalse(state.unscheduledTasks.contains { $0.id == t.id })
    }

    func testCompletedTaskNeverResurfaces() {
        let state = AppState()
        let base = at(9)
        // Past slot + past due would normally resurface — being done must keep it out.
        let t = state.addTask(title: "Done block", dueDate: at(9, 30), durationMin: 30)
        state.schedule(taskId: t.id, at: base)
        state.toggleTask(t.id)                 // mark done
        state.now = base.addingTimeInterval(60 * 60)
        XCTAssertFalse(state.unscheduledTasks.contains { $0.id == t.id })
    }
}
