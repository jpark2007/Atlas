import XCTest
@testable import Atlas

/// Locks the WS-10 native foundation: a note's project link survives the DB
/// round-trip (it persists via the existing `notes.project_id` column).
final class NoteProjectLinkTests: XCTestCase {

    func testNoteProjectID_survivesRowRoundTrip() {
        let projectID = UUID()
        var note = Note(title: "Lecture 12", body: "Dijkstra")
        note.projectID = projectID
        note.spaceName = "School"

        let restored = NoteRow(domain: note).toDomain()

        XCTAssertEqual(restored.projectID, projectID, "project link must persist through NoteRow")
        XCTAssertEqual(restored.spaceName, "School")
        XCTAssertEqual(restored.title, "Lecture 12")
    }

    func testLooseNote_hasNilProjectID() {
        let note = Note(title: "Loose", body: "")
        let restored = NoteRow(domain: note).toDomain()
        XCTAssertNil(restored.projectID)
    }
}
