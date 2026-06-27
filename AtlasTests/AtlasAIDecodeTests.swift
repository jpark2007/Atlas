import XCTest
@testable import Atlas

/// TDD: decode CaptureResult from raw JSON for each kind.
/// Step 1 (RED): these fail because AtlasAI / CaptureResult don't exist yet.
/// Step 2 (GREEN): pass after Atlas/Services/AtlasAI.swift is added.
final class AtlasAIDecodeTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - task

    func testDecodeTask() throws {
        let json = """
        {
          "kind": "task",
          "title": "Write essay outline",
          "spaceName": "School",
          "dueISO": "2026-06-30T23:59:00Z"
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(CaptureResult.self, from: json)

        XCTAssertEqual(result.kind, "task")
        XCTAssertEqual(result.title, "Write essay outline")
        XCTAssertEqual(result.spaceName, "School")
        XCTAssertEqual(result.dueISO, "2026-06-30T23:59:00Z")
        XCTAssertNil(result.projectName)
        XCTAssertNil(result.startISO)
        XCTAssertNil(result.durationMin)
        XCTAssertNil(result.notes)
    }

    // MARK: - event (all optional fields present)

    func testDecodeEvent() throws {
        let json = """
        {
          "kind": "event",
          "title": "Study session",
          "spaceName": "School",
          "projectName": "CS101",
          "startISO": "2026-06-28T14:00:00Z",
          "durationMin": 90,
          "notes": "Bring textbook"
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(CaptureResult.self, from: json)

        XCTAssertEqual(result.kind, "event")
        XCTAssertEqual(result.title, "Study session")
        XCTAssertEqual(result.spaceName, "School")
        XCTAssertEqual(result.projectName, "CS101")
        XCTAssertEqual(result.startISO, "2026-06-28T14:00:00Z")
        XCTAssertEqual(result.durationMin, 90)
        XCTAssertEqual(result.notes, "Bring textbook")
        XCTAssertNil(result.dueISO)
    }

    // MARK: - note

    func testDecodeNote() throws {
        let json = """
        {
          "kind": "note",
          "title": "Meeting notes",
          "spaceName": "Work",
          "notes": "Discussed Q3 roadmap and priorities."
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(CaptureResult.self, from: json)

        XCTAssertEqual(result.kind, "note")
        XCTAssertEqual(result.title, "Meeting notes")
        XCTAssertEqual(result.spaceName, "Work")
        XCTAssertEqual(result.notes, "Discussed Q3 roadmap and priorities.")
        XCTAssertNil(result.projectName)
        XCTAssertNil(result.dueISO)
        XCTAssertNil(result.startISO)
        XCTAssertNil(result.durationMin)
    }

    // MARK: - minimal (only required fields)

    func testDecodeMinimalTask() throws {
        let json = """
        {"kind":"task","title":"Call dentist","spaceName":"Personal"}
        """.data(using: .utf8)!

        let result = try decoder.decode(CaptureResult.self, from: json)

        XCTAssertEqual(result.kind, "task")
        XCTAssertEqual(result.title, "Call dentist")
        XCTAssertEqual(result.spaceName, "Personal")
        XCTAssertNil(result.dueISO)
    }
}
