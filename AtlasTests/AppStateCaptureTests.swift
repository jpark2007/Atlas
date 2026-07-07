import XCTest
@testable import AtlasCore
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

    // MARK: - applyCapture seam (WS-2)

    private func result(kind: String,
                        title: String,
                        space: String = "Personal",
                        dueISO: String? = nil,
                        startISO: String? = nil,
                        durationMin: Int? = nil,
                        notes: String? = nil) -> CaptureResult {
        CaptureResult(kind: kind, title: title, spaceName: space,
                      projectName: nil, dueISO: dueISO, startISO: startISO,
                      durationMin: durationMin, notes: notes)
    }

    func testApplyCaptureTaskWithDate() {
        let state = AppState()
        let before = state.tasks.count
        let outcome = state.applyCapture(
            result(kind: "task", title: "Essay", space: "School",
                   dueISO: "2026-07-02T23:59:00Z"))
        XCTAssertEqual(outcome, .task(hasDate: true))
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertNotNil(state.tasks.last?.dueDate)
    }

    func testApplyCaptureTaskWithoutDate() {
        let state = AppState()
        let outcome = state.applyCapture(result(kind: "task", title: "Call dentist"))
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertNil(state.tasks.last?.dueDate)
    }

    func testApplyCaptureNote() {
        let state = AppState()
        let before = state.notes.count
        let outcome = state.applyCapture(
            result(kind: "note", title: "Idea", notes: "remember this"))
        XCTAssertEqual(outcome, .note)
        XCTAssertEqual(state.notes.count, before + 1)
    }

    func testApplyCaptureEventWithStartAddsEvent() throws {
        let state = AppState()
        let before = state.events.count
        let outcome = state.applyCapture(
            result(kind: "event", title: "Gym", space: "Health",
                   startISO: "2026-06-28T15:00:00Z", durationMin: 45))
        XCTAssertEqual(outcome, .event)
        XCTAssertEqual(state.events.count, before + 1)
        let added = try XCTUnwrap(state.events.last)
        XCTAssertEqual(added.title, "Gym")
        XCTAssertEqual(added.end.timeIntervalSince(added.start), 45 * 60, accuracy: 0.5)
    }

    func testApplyCaptureEventWithoutStartFallsBackToTask() {
        let state = AppState()
        let eventsBefore = state.events.count
        let tasksBefore = state.tasks.count
        let outcome = state.applyCapture(result(kind: "event", title: "Mystery meeting"))
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertEqual(state.events.count, eventsBefore)        // no event
        XCTAssertEqual(state.tasks.count, tasksBefore + 1)      // saved as task
    }

    func testApplyCaptureUnknownKindBecomesTask() {
        let state = AppState()
        let outcome = state.applyCapture(result(kind: "wat", title: "Strange"))
        XCTAssertEqual(outcome, .task(hasDate: false))
        XCTAssertEqual(state.tasks.last?.title, "Strange")
    }

    func testMultiItemCaptureConfirmationCount() {
        let state = AppState()
        let results = [
            result(kind: "task", title: "A"),
            result(kind: "note", title: "B"),
            result(kind: "event", title: "C", startISO: "2026-06-28T15:00:00Z"),
        ]
        let outcomes = results.map { state.applyCapture($0) }
        XCTAssertEqual(CaptureOutcome.confirmation(for: outcomes), "✓ Added 3 items")
    }

    func testSingleItemCaptureKeepsPerKindConfirmation() {
        let state = AppState()
        let outcomes = [state.applyCapture(result(kind: "note", title: "Solo"))]
        XCTAssertEqual(CaptureOutcome.confirmation(for: outcomes),
                       CaptureOutcome.note.confirmation)
    }
}
