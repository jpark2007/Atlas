import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

/// Locks the pure node/edge derivation behind the relationship graph.
final class GraphSnapshotTests: XCTestCase {

    func testEmptyInputs_produceNoGraph() {
        let g = GraphSnapshot.build(spaces: [], tasks: [], notes: [], events: [], goals: [])
        XCTAssertTrue(g.nodes.isEmpty)
        XCTAssertTrue(g.edges.isEmpty)
    }

    func testMentionsHelper_extractsBracketedTargets() {
        XCTAssertEqual(GraphSnapshot.mentions(in: "pair [[Calc II]] with [[Heaps]] tonight"),
                       ["Calc II", "Heaps"])
        XCTAssertEqual(GraphSnapshot.mentions(in: "no mentions here"), [])
    }

    func testDerivesNodesAndEdges_fromRealRelationships() {
        // One project (with one assignment) inside a space.
        let assignment = TaskItem(title: "PS4", dueLabel: "")
        let project = Project(name: "Data Structures", code: "CS 201", isClass: true,
                              spaceName: "School", spaceColor: .blue,
                              assignments: [assignment])
        let space = Space(id: UUID(), name: "School", color: .blue, projects: [project])

        // A flat dashboard task in the same space.
        var grocery = TaskItem(title: "Grocery run", dueLabel: "")
        grocery.spaceName = "School"

        // A note that [[mentions]] the project by title.
        let note = Note(title: "Study plan",
                        body: "Re-derive Dijkstra. Pairs with [[Data Structures]].",
                        spaceName: "School")

        // An event linked to the project via projectID.
        var lecture = CalendarEvent(title: "Lecture", subtitle: "",
                                    start: Date(), end: Date().addingTimeInterval(3600),
                                    color: .blue, spaceName: "School")
        lecture.projectID = project.id

        let goal = Goal(id: UUID(), title: "Pass the midterm", progress: 0.3, label: "")

        let g = GraphSnapshot.build(spaces: [space], tasks: [grocery],
                                    notes: [note], events: [lecture], goals: [goal])

        // 7 nodes: space, project, assignment, flat task, note, event, goal.
        XCTAssertEqual(g.nodes.count, 7)

        // Helper: is there an (undirected) edge between two ids?
        func linked(_ a: UUID, _ b: UUID) -> Bool {
            g.edges.contains { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }
        }

        XCTAssertTrue(linked(space.id, project.id),       "space → project")
        XCTAssertTrue(linked(project.id, assignment.id),  "project → assignment task")
        XCTAssertTrue(linked(space.id, grocery.id),       "flat task → space by name")
        XCTAssertTrue(linked(space.id, note.id),          "note → space by name")
        XCTAssertTrue(linked(project.id, lecture.id),     "event → project via projectID")
        XCTAssertTrue(linked(note.id, project.id),        "note [[mention]] → project")

        // Event with a projectID should NOT also be linked straight to the space.
        XCTAssertFalse(linked(space.id, lecture.id), "event links to project, not space, when projectID is set")
    }

    func testNodeCap_isRespected() {
        let many = (0..<(GraphSnapshot.nodeCap + 50)).map { Note(title: "n\($0)", body: "") }
        let g = GraphSnapshot.build(spaces: [], tasks: [], notes: many, events: [], goals: [])
        XCTAssertLessThanOrEqual(g.nodes.count, GraphSnapshot.nodeCap)
    }
}
