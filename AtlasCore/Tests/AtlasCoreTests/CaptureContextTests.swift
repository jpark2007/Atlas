import XCTest
import SwiftUI
@testable import AtlasCore

/// Phase 4 §2 — the richer context we hand the capture model, and the
/// update-vs-create decision that context makes possible.
final class CaptureContextTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // fixed reference

    private func task(_ title: String,
                      due: Date?,
                      done: Bool = false,
                      project: String = "") -> TaskItem {
        TaskItem(title: title,
                 dueLabel: TaskItem.dueLabel(for: due),
                 done: done,
                 dueDate: due,
                 projectName: project)
    }

    private func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    // MARK: - Deadline window selection

    func test_deadlineContext_keepsOnlyTheNextTwoWeeks() {
        let tasks = [
            task("Yesterday", due: days(-1)),
            task("Tomorrow", due: days(1)),
            task("In ten days", due: days(10)),
            task("In thirty days", due: days(30)),
            task("Undated", due: nil),
        ]
        let titles = AtlasAI.deadlineContext(from: tasks, now: now).map(\.title)
        XCTAssertEqual(titles, ["Tomorrow", "In ten days"])
    }

    func test_deadlineContext_includesTodayFromMidnight() {
        // A deadline earlier TODAY is still today's work — the window starts at
        // the local start of day, not at "now".
        let earlierToday = Calendar.current.startOfDay(for: now).addingTimeInterval(60)
        let titles = AtlasAI.deadlineContext(from: [task("This morning", due: earlierToday)],
                                             now: now).map(\.title)
        XCTAssertEqual(titles, ["This morning"])
    }

    func test_deadlineContext_dropsCompletedTasks() {
        let tasks = [task("Done already", due: days(2), done: true),
                     task("Still open", due: days(2))]
        XCTAssertEqual(AtlasAI.deadlineContext(from: tasks, now: now).map(\.title),
                       ["Still open"])
    }

    func test_deadlineContext_sortsEarliestFirstAndCaps() {
        let tasks = (1...40).map { task("T\($0)", due: days(Double(41 - $0) * 0.3)) }
        let context = AtlasAI.deadlineContext(from: tasks, now: now, limit: 5)
        XCTAssertEqual(context.count, 5)
        XCTAssertEqual(context.map(\.title), ["T40", "T39", "T38", "T37", "T36"])
    }

    func test_deadlineContext_carriesIdAndProject() throws {
        let t = task("Ecology essay", due: days(3), project: "Biology")
        let entry = try XCTUnwrap(AtlasAI.deadlineContext(from: [t], now: now).first)
        XCTAssertEqual(entry.id, t.id.uuidString)
        XCTAssertEqual(entry.projectName, "Biology")
        XCTAssertTrue(entry.dueISO.hasSuffix("Z"))
    }

    func test_deadlineContext_omitsBlankProject() {
        let entry = AtlasAI.deadlineContext(from: [task("Loose end", due: days(1))],
                                            now: now).first
        XCTAssertNil(entry?.projectName)
    }

    // MARK: - Recent capture referents

    func test_recentContext_capsCountAndLength() {
        let texts = (1...10).map { "capture \($0) " + String(repeating: "x", count: 400) }
        let recent = AtlasAI.recentContext(texts, limit: 3, maxChars: 20)
        XCTAssertEqual(recent.count, 3)
        XCTAssertTrue(recent.allSatisfy { $0.count <= 21 })   // 20 + the ellipsis
        XCTAssertTrue(recent[0].hasPrefix("capture 1"))
    }

    func test_recentContext_dropsBlanks() {
        XCTAssertEqual(AtlasAI.recentContext(["  ", "real", ""]), ["real"])
    }

    // MARK: - Context payload shape

    func test_requestBody_omitsEmptyContext() throws {
        let data = try AtlasAI.requestBody(text: "x", spaces: [], timezone: "UTC")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["deadlines"])
        XCTAssertNil(obj["recent"])
        XCTAssertNil(obj["spaces"])
    }

    func test_requestBody_carriesDeadlinesAndRecent() throws {
        let deadline = CaptureContextDeadline(id: "abc", title: "Essay",
                                              dueISO: "2026-09-01T00:00:00Z",
                                              projectName: "ENG 101")
        let data = try AtlasAI.requestBody(text: "the essay is friday", spaces: [],
                                           timezone: "UTC",
                                           deadlines: [deadline], recent: ["gym 3x"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let deadlines = try XCTUnwrap(obj["deadlines"] as? [[String: Any]])
        XCTAssertEqual(deadlines.first?["id"] as? String, "abc")
        XCTAssertEqual(deadlines.first?["projectName"] as? String, "ENG 101")
        XCTAssertEqual(obj["recent"] as? [String], ["gym 3x"])
    }

    func test_context_marksClassesAndKeepsCodes() {
        let space = Space(name: "School", color: .blue, projects: [
            Project(name: "Biology", code: "BIO 201", isClass: true,
                    spaceName: "School", spaceColor: .blue),
            Project(name: "Side site", code: nil, isClass: false,
                    spaceName: "School", spaceColor: .blue),
        ])
        let projects = AtlasAI.context(from: [space]).first?.projects ?? []
        XCTAssertEqual(projects.first?.code, "BIO 201")
        XCTAssertEqual(projects.first?.isClass, true)
        // Non-classes send nothing at all rather than `false` — smaller payload.
        XCTAssertNil(projects.last?.isClass)
    }

    // MARK: - Update vs create

    private func update(targetId: String?) -> CaptureResult {
        CaptureResult(kind: "update", title: "Essay", spaceName: "School", targetId: targetId)
    }

    func test_decide_updatesOnAKnownTarget() {
        let id = UUID()
        XCTAssertEqual(CaptureAction.decide(update(targetId: id.uuidString), knownIDs: [id]),
                       .update(targetId: id))
    }

    func test_decide_createsWhenTheTargetIsUnknown() {
        XCTAssertEqual(CaptureAction.decide(update(targetId: UUID().uuidString),
                                            knownIDs: [UUID()]),
                       .create)
    }

    func test_decide_createsOnAMalformedOrMissingTarget() {
        XCTAssertEqual(CaptureAction.decide(update(targetId: "not-a-uuid"), knownIDs: []), .create)
        XCTAssertEqual(CaptureAction.decide(update(targetId: nil), knownIDs: []), .create)
    }

    func test_decide_neverUpdatesFromANonUpdateKind() {
        let id = UUID()
        let task = CaptureResult(kind: "task", title: "Essay", spaceName: "School",
                                 targetId: id.uuidString)
        XCTAssertEqual(CaptureAction.decide(task, knownIDs: [id]), .create)
    }

    // MARK: - Confidence

    func test_lowConfidence_onlyWhenTheModelSaidSo() {
        let sure = CaptureResult(kind: "task", title: "x", spaceName: "S", confidence: 0.9)
        let unsure = CaptureResult(kind: "task", title: "x", spaceName: "S", confidence: 0.3)
        let silent = CaptureResult(kind: "task", title: "x", spaceName: "S")
        XCTAssertFalse(sure.isLowConfidence)
        XCTAssertTrue(unsure.isLowConfidence)
        XCTAssertFalse(silent.isLowConfidence, "an old deploy sends no confidence at all")
    }

    func test_decodeResults_toleratesTheNewFields() throws {
        let json = """
        [{"kind":"update","title":"Essay","spaceName":"School",
          "targetId":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","confidence":0.42}]
        """.data(using: .utf8)!
        let results = try AtlasAI.decodeResults(from: json)
        XCTAssertEqual(results.first?.targetId, "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        XCTAssertTrue(results.first!.isLowConfidence)
    }
}
