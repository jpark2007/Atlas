import XCTest
@testable import AtlasCore
@testable import Atlas

@MainActor
final class AppStateProjectTests: XCTestCase {

    // MARK: - addProject

    func testAddProjectAppendsToCorrectSpaceAndNowhereElse() {
        let state = AppState()
        // Snapshot per-space project counts before.
        let before = Dictionary(uniqueKeysWithValues:
            state.spaces.map { ($0.name, $0.projects.count) })

        let created = state.addProject(
            toSpaceNamed: "School",
            name: "Linear Algebra",
            code: "MATH 220",
            isClass: true,
            overview: "Vector spaces and eigenstuff.")

        let project = try! XCTUnwrap(created)

        // Appended to School.
        let school = state.spaces.first { $0.name == "School" }!
        XCTAssertEqual(school.projects.count, before["School"]! + 1)
        XCTAssertTrue(school.projects.contains { $0.id == project.id })

        // Appended to NO other space.
        for space in state.spaces where space.name != "School" {
            XCTAssertEqual(space.projects.count, before[space.name]!,
                           "space \(space.name) gained a project")
            XCTAssertFalse(space.projects.contains { $0.id == project.id })
        }

        // Mirrors the parent space metadata.
        XCTAssertEqual(project.spaceName, "School")
        XCTAssertEqual(project.spaceColor, school.color)
        XCTAssertEqual(project.code, "MATH 220")
        XCTAssertTrue(project.isClass)
        XCTAssertEqual(project.overview, "Vector spaces and eigenstuff.")
    }

    func testAddProjectUnknownSpaceReturnsNilAndAppendsNowhere() {
        let state = AppState()
        let totalBefore = state.spaces.reduce(0) { $0 + $1.projects.count }
        let created = state.addProject(toSpaceNamed: "Nonexistent Space", name: "Ghost")
        XCTAssertNil(created)
        let totalAfter = state.spaces.reduce(0) { $0 + $1.projects.count }
        XCTAssertEqual(totalBefore, totalAfter)
    }

    func testAddProjectBlankCodeBecomesNil() {
        let state = AppState()
        let created = state.addProject(toSpaceNamed: "Personal", name: "Garden", code: "   ")
        XCTAssertNil(try XCTUnwrap(created).code)
    }

    // MARK: - updateProjectOverview

    func testUpdateProjectOverviewUpdatesOnlyTarget() {
        let state = AppState()
        let target = state.addProject(toSpaceNamed: "Personal", name: "Trip", overview: "old")!
        let sibling = state.addProject(toSpaceNamed: "Personal", name: "Reading", overview: "keep")!

        state.updateProjectOverview(projectID: target.id, overview: "new overview")

        XCTAssertEqual(state.project(target.id)?.overview, "new overview")
        XCTAssertEqual(state.project(sibling.id)?.overview, "keep")
    }

    func testUpdateProjectOverviewUnknownIdIsNoOp() {
        let state = AppState()
        let totalBefore = state.spaces.reduce(0) { $0 + $1.projects.count }
        state.updateProjectOverview(projectID: UUID(), overview: "nope")
        let totalAfter = state.spaces.reduce(0) { $0 + $1.projects.count }
        XCTAssertEqual(totalBefore, totalAfter)
    }
}
