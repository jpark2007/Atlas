import XCTest
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

    // MARK: revert-after-slot via unscheduledTasks

    func testUnscheduledTasksResurfaceAfterSlotPasses() {
        let state = AppState()
        let t = state.addTask(title: "Past block", durationMin: 30)
        let base = at(9)
        state.schedule(taskId: t.id, at: base)

        // Before the slot ends → not in the tray.
        state.now = base
        XCTAssertFalse(state.unscheduledTasks.contains { $0.id == t.id })

        // After the slot fully elapses → resurfaces in the tray.
        state.now = base.addingTimeInterval(60 * 60)
        XCTAssertTrue(state.unscheduledTasks.contains { $0.id == t.id })
    }

    func testCompletedTaskNeverResurfaces() {
        let state = AppState()
        let t = state.addTask(title: "Done block", durationMin: 30)
        let base = at(9)
        state.schedule(taskId: t.id, at: base)
        state.toggleTask(t.id)                 // mark done
        state.now = base.addingTimeInterval(60 * 60)
        XCTAssertFalse(state.unscheduledTasks.contains { $0.id == t.id })
    }
}
