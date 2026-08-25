import XCTest
@testable import AtlasCore

final class SpaceIDRoundTripTests: XCTestCase {
    func testProjectRowRoundTripsSpaceID() {
        let sid = UUID()
        var p = Project(name: "Essay", isClass: false, spaceName: "School", spaceColor: .blue)
        p.spaceID = sid
        XCTAssertEqual(ProjectRow(domain: p).toDomain().spaceID, sid)
    }

    func testTaskRowRoundTripsSpaceID() {
        let sid = UUID()
        var t = TaskItem(title: "Read ch. 4", dueLabel: "")
        t.spaceName = "School"
        t.spaceID = sid
        XCTAssertEqual(TaskRow(domain: t).toDomain().spaceID, sid)
    }

    func testEventRowRoundTripsSpaceID() {
        let sid = UUID()
        var e = CalendarEvent(title: "Standup", subtitle: "", start: .now,
                              end: .now.addingTimeInterval(3600),
                              color: .blue, spaceName: "School")
        e.spaceID = sid
        XCTAssertEqual(EventRow(domain: e).toDomain().spaceID, sid)
    }

    func testNoteRowRoundTripsSpaceID() {
        let sid = UUID()
        var n = Note(title: "Lecture notes", body: "")
        n.spaceID = sid
        XCTAssertEqual(NoteRow(domain: n).toDomain().spaceID, sid)
    }

    /// A task's CLASS must survive a save/load. `TaskRow` used to hardcode
    /// `projectId = nil`, so every upsert dropped the link and the next snapshot pull
    /// degraded the class chip to the space tag.
    func testTaskRowRoundTripsProjectID() {
        let pid = UUID()
        var t = TaskItem(title: "Watch Edpuzzle for Chem", dueLabel: "")
        t.spaceName = "School"
        t.projectName = "General Chemistry"
        t.projectID = pid
        XCTAssertEqual(TaskRow(domain: t).toDomain().projectID, pid)
    }

    func testTaskRowNilProjectIDStaysNil() {
        let t = TaskItem(title: "Buy milk", dueLabel: "")
        XCTAssertNil(TaskRow(domain: t).toDomain().projectID)
    }

    func testNilSpaceIDStaysNil() {
        let p = Project(name: "Essay", isClass: false, spaceName: "School", spaceColor: .blue)
        XCTAssertNil(ProjectRow(domain: p).toDomain().spaceID)
    }
}
