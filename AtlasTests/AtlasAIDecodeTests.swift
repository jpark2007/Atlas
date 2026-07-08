import XCTest
@testable import AtlasCore
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

    // MARK: - Array decoding (WS-2: multi-item paragraph)

    func testDecodeResultsArray() throws {
        let json = """
        [
          {"kind":"task","title":"Essay outline","spaceName":"School","dueISO":"2026-07-02T23:59:00Z"},
          {"kind":"event","title":"Gym","spaceName":"Health","startISO":"2026-06-28T15:00:00Z","durationMin":60},
          {"kind":"note","title":"Dinner idea","spaceName":"Personal"}
        ]
        """.data(using: .utf8)!

        let results = try AtlasAI.decodeResults(from: json)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].kind, "task")
        XCTAssertEqual(results[0].dueISO, "2026-07-02T23:59:00Z")
        XCTAssertEqual(results[1].kind, "event")
        XCTAssertEqual(results[1].durationMin, 60)
        XCTAssertEqual(results[2].kind, "note")
    }

    /// Tolerance: a stale deploy that still returns a single object must decode
    /// as a one-element array.
    func testDecodeResultsSingleObjectTolerance() throws {
        let json = """
        {"kind":"task","title":"Call dentist","spaceName":"Personal"}
        """.data(using: .utf8)!

        let results = try AtlasAI.decodeResults(from: json)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Call dentist")
    }

    func testDecodeResultsEmptyArray() throws {
        let json = "[]".data(using: .utf8)!
        let results = try AtlasAI.decodeResults(from: json)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Context payload building

    func testContextFromSpacesMapsNamesAndProjects() {
        let school = Space(
            name: "School",
            color: .blue,
            projects: [
                Project(name: "CS101", code: "CS 101", isClass: true,
                        spaceName: "School", spaceColor: .blue,
                        overview: "Intro to programming and data structures."),
                Project(name: "Writing Seminar", code: nil, isClass: true,
                        spaceName: "School", spaceColor: .blue),
            ]
        )
        let personal = Space(name: "Personal", color: .green, projects: [])

        let ctx = AtlasAI.context(from: [school, personal])

        XCTAssertEqual(ctx.count, 2)
        XCTAssertEqual(ctx[0].name, "School")
        XCTAssertEqual(ctx[0].projects.map(\.name), ["CS101", "Writing Seminar"])

        // Code + overview carried through for routing.
        XCTAssertEqual(ctx[0].projects[0].code, "CS 101")
        XCTAssertEqual(ctx[0].projects[0].overview, "Intro to programming and data structures.")

        // No code / no overview → nil (key omitted on the wire).
        XCTAssertNil(ctx[0].projects[1].code)
        XCTAssertNil(ctx[0].projects[1].overview)

        XCTAssertEqual(ctx[1].name, "Personal")
        XCTAssertTrue(ctx[1].projects.isEmpty)
    }

    func testShortOverviewTruncatesLongTextAndKeepsPrefix() {
        let long = String(repeating: "a", count: 400)
        let short = try! XCTUnwrap(AtlasAI.shortOverview(long, limit: 160))
        XCTAssertTrue(short.hasPrefix(String(repeating: "a", count: 160)))
        XCTAssertLessThanOrEqual(short.count, 161) // 160 + ellipsis
        XCTAssertTrue(short.hasSuffix("…"))
    }

    func testShortOverviewPassesThroughShortTextAndDropsBlank() {
        XCTAssertEqual(AtlasAI.shortOverview("  Tidy goal.  "), "Tidy goal.")
        XCTAssertNil(AtlasAI.shortOverview("    "))
        XCTAssertNil(AtlasAI.shortOverview(""))
    }

    // MARK: - Request body building (decode back — never string-compare)

    func testRequestBodyIncludesContextWhenPresent() throws {
        let spaces = [CaptureContextSpace(
            name: "Work",
            projects: [CaptureContextProject(name: "Atlas", code: "ATL",
                                             overview: "Life manager app")])]
        let data = try AtlasAI.requestBody(text: "ship it", spaces: spaces)

        let round = try decoder.decode(CaptureRequest.self, from: data)
        XCTAssertEqual(round.text, "ship it")
        XCTAssertEqual(round.spaces, spaces)
    }

    func testRequestBodyOmitsContextWhenEmpty() throws {
        let data = try AtlasAI.requestBody(text: "ship it", spaces: [])

        // `spaces` must be absent entirely (old-deploy compatible), not [].
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["text"] as? String, "ship it")
        XCTAssertNil(object?["spaces"])

        let round = try decoder.decode(CaptureRequest.self, from: data)
        XCTAssertNil(round.spaces)
    }
}
