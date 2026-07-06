import XCTest
@testable import AtlasCore

final class TaskAssignmentTests: XCTestCase {
    func testUnassignedTaskIsClaimable() {
        let task = TaskItem(title: "Write intro", dueLabel: "")
        XCTAssertNil(task.assigneeID)
        XCTAssertTrue(task.isClaimable)
    }

    func testAssignedTaskIsNotClaimable() {
        var task = TaskItem(title: "Write intro", dueLabel: "")
        task.assigneeID = UUID()
        XCTAssertFalse(task.isClaimable)
    }

    func testClaimSetsAssignee() {
        var task = TaskItem(title: "Write intro", dueLabel: "")
        let me = UUID()
        task.claim(by: me)
        XCTAssertEqual(task.assigneeID, me)
    }

    func testClaimIsNoOpIfAlreadyAssigned() {
        var task = TaskItem(title: "Write intro", dueLabel: "")
        let original = UUID()
        task.assigneeID = original
        task.claim(by: UUID())
        XCTAssertEqual(task.assigneeID, original, "claim() must not steal an already-assigned task")
    }

    func testTaskRowRoundTripsAssignment() {
        var task = TaskItem(title: "Write intro", dueLabel: "")
        task.assigneeID = UUID()
        task.createdByID = UUID()
        let row = TaskRow(domain: task)
        XCTAssertEqual(row.toDomain().assigneeID, task.assigneeID)
        XCTAssertEqual(row.toDomain().createdByID, task.createdByID)
    }
}
