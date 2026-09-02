import XCTest
@testable import AtlasCore

/// `due_moved_from` (migration 0047): the previous due_date a Canvas re-sync stamps
/// when it actually moves the deadline on a non-done task, so the client can show a
/// "Due date moved" chip. The rule under test is the row round-trip — server-written,
/// client-editable (the dismiss "x" clears it locally then persists via upsert).
final class TaskDueMovedTests: XCTestCase {

    func testTaskRowRoundTripsDueMovedFrom() {
        let previousDue = Date(timeIntervalSince1970: 1_700_000_000)
        var t = TaskItem(title: "Problem set 3", dueLabel: "")
        t.dueMovedFrom = previousDue
        XCTAssertEqual(TaskRow(domain: t).toDomain().dueMovedFrom, previousDue)
    }

    /// A task Canvas has never re-dated must stay unflagged.
    func testTaskRowNilDueMovedFromStaysNil() {
        let t = TaskItem(title: "Buy milk", dueLabel: "")
        XCTAssertNil(TaskRow(domain: t).toDomain().dueMovedFrom)
    }

    /// A row from a DB that predates 0047 has no `due_moved_from` key at all; decoding
    /// must yield no marker rather than fail the whole snapshot load.
    func testTaskRowDecodesWithoutDueMovedFromColumn() throws {
        let json = """
        {"id":"\(UUID().uuidString)","space_name":"School","title":"Read ch. 4",
         "status":"open","done":false,"is_all_day":false}
        """
        let row = try JSONDecoder().decode(TaskRow.self, from: Data(json.utf8))
        XCTAssertNil(row.toDomain().dueMovedFrom)
    }
}
