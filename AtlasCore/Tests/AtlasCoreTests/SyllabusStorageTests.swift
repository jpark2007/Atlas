import XCTest
import SwiftUI
@testable import AtlasCore

/// v1.1 Phase 3.5 — the kept syllabus. Only the pure parts are testable without a
/// network: the object path (whose FIRST segment is the owner check the storage RLS
/// policy makes, so getting it wrong is a security bug, not a cosmetic one) and the
/// extension QuickLook renders from.
final class SyllabusStorageTests: XCTestCase {

    private let user = "8b1d3b8e-0e5a-4f4a-9d29-1f0d6b2a4c11"
    private let project = UUID(uuidString: "1c9a7f3e-2b44-4b8e-9c1a-77c0f4c9d2a1")!

    func testPathStartsWithTheOwnerFolder() {
        let path = SyllabusStorage.path(userID: user, projectID: project, fileExtension: "pdf")
        XCTAssertEqual(path, "\(user)/1c9a7f3e-2b44-4b8e-9c1a-77c0f4c9d2a1/syllabus.pdf")
        XCTAssertEqual(path.split(separator: "/").first.map(String.init), user)
    }

    func testPathNormalizesTheExtension() {
        XCTAssertTrue(SyllabusStorage.path(userID: user, projectID: project,
                                           fileExtension: ".PNG").hasSuffix("syllabus.png"))
        // No extension at all still has to land on something QuickLook can open.
        XCTAssertTrue(SyllabusStorage.path(userID: user, projectID: project,
                                           fileExtension: "").hasSuffix("syllabus.pdf"))
    }

    func testRescanReusesTheSamePath() {
        // Overwrite, never version — two uploads for one class are one object.
        XCTAssertEqual(SyllabusStorage.path(userID: user, projectID: project, fileExtension: "pdf"),
                       SyllabusStorage.path(userID: user, projectID: project, fileExtension: "pdf"))
    }

    func testFileExtensionOfPath() {
        XCTAssertEqual(SyllabusStorage.fileExtension(ofPath: "u/p/syllabus.PDF"), "pdf")
        XCTAssertEqual(SyllabusStorage.fileExtension(ofPath: "u/p/syllabus.jpeg"), "jpeg")
        XCTAssertEqual(SyllabusStorage.fileExtension(ofPath: "u/p/syllabus"), "pdf")
    }

    /// The pointer has to survive a round trip through `ProjectRow`, or a stored syllabus
    /// is forgotten the next time the class is loaded.
    func testProjectRowRoundTripsTheSyllabusPointer() {
        var project = Project(name: "Systems", isClass: true, spaceName: "School",
                              spaceColor: .blue)
        project.syllabusPath = "u/p/syllabus.pdf"
        XCTAssertEqual(ProjectRow(domain: project).toDomain().syllabusPath, "u/p/syllabus.pdf")
    }
}
