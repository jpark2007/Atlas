import XCTest
@testable import Atlas

@MainActor
final class AppStateCaptureTests: XCTestCase {
    func testAddTaskWithDueDateSetsDateAndLabel() {
        let state = AppState()
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let before = state.tasks.count
        let t = state.addTask(title: "Finish pset", dueDate: due, durationMin: 45)
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 45)
        XCTAssertEqual(t.dueLabel, TaskItem.dueLabel(for: due))
        XCTAssertEqual(state.tasks.last?.dueDate, due)
    }

    func testAddTaskTitleOnlyStillWorks() {
        let state = AppState()
        let t = state.addTask(title: "Loose task")
        XCTAssertNil(t.dueDate)
        XCTAssertEqual(t.dueLabel, "")
    }
}
