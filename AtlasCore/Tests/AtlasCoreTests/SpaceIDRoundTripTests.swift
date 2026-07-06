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

    func testNilSpaceIDStaysNil() {
        let p = Project(name: "Essay", isClass: false, spaceName: "School", spaceColor: .blue)
        XCTAssertNil(ProjectRow(domain: p).toDomain().spaceID)
    }
}
