import XCTest
@testable import Atlas

/// Pure-logic tests for the editable empty-state starter content. No UI.
final class ProjectTemplateTests: XCTestCase {

    private func project(isClass: Bool) -> Project {
        Project(name: "Test", code: nil, isClass: isClass,
                spaceName: "School", spaceColor: .blue)
    }

    func testStarterIsNonEmptyForBothKinds() {
        let cls = ProjectTemplate.starter(for: project(isClass: true))
        let generic = ProjectTemplate.starter(for: project(isClass: false))

        XCTAssertFalse(cls.overview.isEmpty)
        XCTAssertFalse(cls.sampleTasks.isEmpty)
        XCTAssertFalse(generic.overview.isEmpty)
        XCTAssertFalse(generic.sampleTasks.isEmpty)
    }

    func testClassAndNonClassStartersDiffer() {
        let cls = ProjectTemplate.starter(for: project(isClass: true))
        let generic = ProjectTemplate.starter(for: project(isClass: false))

        // Class vs non-class produce different starter content.
        XCTAssertTrue(cls.overview != generic.overview
                      || cls.sampleTasks != generic.sampleTasks)
        // Class content should mention something class-specific (syllabus).
        XCTAssertTrue(
            cls.overview.localizedCaseInsensitiveContains("syllabus")
            || cls.sampleTasks.contains { $0.localizedCaseInsensitiveContains("syllabus") }
        )
    }

    func testStarterIsDeterministic() {
        let p = project(isClass: true)
        let a = ProjectTemplate.starter(for: p)
        let b = ProjectTemplate.starter(for: p)
        XCTAssertEqual(a.overview, b.overview)
        XCTAssertEqual(a.sampleTasks, b.sampleTasks)
    }
}
