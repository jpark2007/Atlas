import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

@MainActor
final class AppStateSpaceTests: XCTestCase {

    // MARK: - addSpace

    func testAddSpaceAppendsExactlyOneWithNameAndColor() {
        let state = AppState()
        let before = state.spaces.count

        let created = state.addSpace(name: "Research", color: AtlasTheme.Colors.side)

        let space = try! XCTUnwrap(created)
        XCTAssertEqual(state.spaces.count, before + 1)
        XCTAssertEqual(state.spaces.last?.id, space.id)
        XCTAssertEqual(space.name, "Research")
        XCTAssertEqual(space.color, AtlasTheme.Colors.side)
        XCTAssertTrue(space.projects.isEmpty)
    }

    func testAddSpaceTrimsWhitespaceFromName() {
        let state = AppState()
        let created = state.addSpace(name: "  Finance  ", color: AtlasTheme.Colors.personal)
        XCTAssertEqual(try XCTUnwrap(created).name, "Finance")
    }

    func testAddSpaceBlankNameRejectedAppendsNothing() {
        let state = AppState()
        let before = state.spaces.count

        XCTAssertNil(state.addSpace(name: "   ", color: AtlasTheme.Colors.accent))
        XCTAssertNil(state.addSpace(name: "", color: AtlasTheme.Colors.accent))

        XCTAssertEqual(state.spaces.count, before, "blank name must append no space")
    }
}
