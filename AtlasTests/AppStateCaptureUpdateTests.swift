import XCTest
@testable import AtlasCore
@testable import Atlas

/// Phase 4 §2/§3 — capture attaching to an item the user ALREADY has, and the
/// undo rule that follows from it: capture may delete only what capture made.
@MainActor
final class AppStateCaptureUpdateTests: XCTestCase {

    private func update(targetId: String?,
                        title: String = "Essay",
                        dueISO: String? = nil,
                        notes: String? = nil) -> CaptureResult {
        CaptureResult(kind: "update", title: title, spaceName: "School",
                      dueISO: dueISO, notes: notes, targetId: targetId)
    }

    func testUpdateMovesTheExistingTaskInsteadOfCreatingOne() throws {
        let state = AppState()
        let existing = state.addTask(title: "Essay", dueDate: nil)
        let before = state.tasks.count

        let applied = state.applyCapture(update(targetId: existing.id.uuidString,
                                                dueISO: "2026-09-04T23:59:00Z"))

        XCTAssertEqual(applied.outcome, .updated)
        XCTAssertEqual(state.tasks.count, before, "no duplicate was created")
        let after = try XCTUnwrap(state.tasks.first { $0.id == existing.id })
        XCTAssertNotNil(after.dueDate)
        XCTAssertEqual(applied.item.id, existing.id)
    }

    func testUpdateAppendsNotesWithoutLosingWhatWasThere() throws {
        let state = AppState()
        let existing = state.addTask(title: "Essay", notes: "outline done")
        state.applyCapture(update(targetId: existing.id.uuidString, notes: "needs sources"))
        let after = try XCTUnwrap(state.tasks.first { $0.id == existing.id })
        XCTAssertTrue(after.notes.contains("outline done"))
        XCTAssertTrue(after.notes.contains("needs sources"))
    }

    func testUnknownTargetFallsBackToCreatingATask() {
        let state = AppState()
        let before = state.tasks.count
        let applied = state.applyCapture(update(targetId: UUID().uuidString,
                                                dueISO: "2026-09-04T23:59:00Z"))
        XCTAssertEqual(applied.outcome, .task(hasDate: true))
        XCTAssertEqual(state.tasks.count, before + 1, "the capture is never lost")
    }

    func testMalformedTargetFallsBackToCreatingATask() {
        let state = AppState()
        let before = state.tasks.count
        XCTAssertEqual(state.applyCapture(update(targetId: "nonsense")).outcome,
                       .task(hasDate: false))
        XCTAssertEqual(state.tasks.count, before + 1)
    }

    // MARK: - Undo

    func testRevertRestoresAnUpdatedTaskRatherThanDeletingIt() throws {
        let state = AppState()
        let existing = state.addTask(title: "Essay", notes: "outline done")
        let before = state.tasks.count
        let applied = state.applyCapture(update(targetId: existing.id.uuidString,
                                                dueISO: "2026-09-04T23:59:00Z",
                                                notes: "needs sources"))

        state.revert(applied.item)

        XCTAssertEqual(state.tasks.count, before, "the pre-existing task survives undo")
        let after = try XCTUnwrap(state.tasks.first { $0.id == existing.id })
        XCTAssertNil(after.dueDate)
        XCTAssertEqual(after.notes, "outline done")
    }

    func testRevertDeletesAnItemCaptureActuallyCreated() {
        let state = AppState()
        let applied = state.applyCapture(
            CaptureResult(kind: "task", title: "New thing", spaceName: "Personal"))
        let before = state.tasks.count
        state.revert(applied.item)
        XCTAssertEqual(state.tasks.count, before - 1)
    }

    // MARK: - Chip corrections

    func testDueChipMovesACommittedTask() throws {
        let state = AppState()
        let applied = state.applyCapture(
            CaptureResult(kind: "task", title: "Reading", spaceName: "School"))
        let target = Date(timeIntervalSinceReferenceDate: 900_000)

        let updated = try XCTUnwrap(state.recaptureDue(applied.item, date: target))

        XCTAssertEqual(updated.dueDate, target)
        XCTAssertEqual(state.tasks.first { $0.id == applied.item.id }?.dueDate, target)
    }

    func testTypeChipConvertsATaskIntoAnEvent() throws {
        let state = AppState()
        let applied = state.applyCapture(
            CaptureResult(kind: "task", title: "Study group", spaceName: "School",
                          dueISO: "2026-09-04T18:00:00Z"))
        let tasksBefore = state.tasks.count
        let eventsBefore = state.events.count

        let converted = try XCTUnwrap(state.recaptureType(applied.item, to: .event))

        XCTAssertEqual(converted.kind, .event)
        XCTAssertEqual(converted.title, "Study group")
        XCTAssertEqual(state.tasks.count, tasksBefore - 1)
        XCTAssertEqual(state.events.count, eventsBefore + 1)
    }

    func testTypeChipRefusesToConvertAnUpdatedItem() {
        let state = AppState()
        let existing = state.addTask(title: "Essay")
        let applied = state.applyCapture(update(targetId: existing.id.uuidString))
        // Converting would delete a task the user already had — so it doesn't.
        XCTAssertNil(state.recaptureType(applied.item, to: .event))
        XCTAssertNotNil(state.tasks.first { $0.id == existing.id })
    }
}
