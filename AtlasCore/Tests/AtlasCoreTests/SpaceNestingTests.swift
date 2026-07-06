import XCTest
@testable import AtlasCore

final class SpaceNestingTests: XCTestCase {
    private func space(_ name: String, id: UUID = UUID()) -> Space {
        Space(id: id, name: name, color: .blue, projects: [])
    }
    private func project(_ name: String, spaceName: String, spaceID: UUID? = nil) -> Project {
        Project(name: name, isClass: false, spaceName: spaceName, spaceColor: .blue, spaceID: spaceID)
    }

    func testNestsByIDEvenWhenNameDiffers() {
        let school = space("School")
        // Renamed space: project still carries the old name but the right id.
        let p = project("Essay", spaceName: "Skool", spaceID: school.id)
        let result = SpaceNesting.nest(projects: [p], into: [school])
        XCTAssertEqual(result[0].projects.map(\.name), ["Essay"])
    }

    func testFallsBackToNameWhenIDMissing() {
        let school = space("School")
        let p = project("Essay", spaceName: "School", spaceID: nil)
        let result = SpaceNesting.nest(projects: [p], into: [school])
        XCTAssertEqual(result[0].projects.map(\.name), ["Essay"])
    }

    func testIDWinsOverNameMatch() {
        let school = space("School")
        let personal = space("Personal")
        // ID points at Personal even though the name says School — ID is authoritative.
        let p = project("Essay", spaceName: "School", spaceID: personal.id)
        let result = SpaceNesting.nest(projects: [p], into: [school, personal])
        XCTAssertTrue(result[0].projects.isEmpty)
        XCTAssertEqual(result[1].projects.map(\.name), ["Essay"])
    }

    func testOrphanLandsNowhere() {
        let school = space("School")
        let p = project("Essay", spaceName: "Gone", spaceID: UUID())
        let result = SpaceNesting.nest(projects: [p], into: [school])
        XCTAssertTrue(result[0].projects.isEmpty)
    }
}
