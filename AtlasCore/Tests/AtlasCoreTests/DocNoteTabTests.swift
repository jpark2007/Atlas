import XCTest
@testable import AtlasCore

final class DocNoteTabTests: XCTestCase {
    func testDisplayTitleNestsParent() {
        let parent = DocNoteTab(id: UUID(), referenceID: UUID(), tabId: "t.p", parentTabId: nil,
                                title: "Project A", ord: 0, bodyMD: "", writable: true, readonlyReason: nil)
        let child = DocNoteTab(id: UUID(), referenceID: parent.referenceID, tabId: "t.c", parentTabId: "t.p",
                               title: "Notes", ord: 1, bodyMD: "", writable: true, readonlyReason: nil)
        let tabs = [parent, child]
        XCTAssertEqual(child.displayTitle(in: tabs), "Project A ▸ Notes")
        XCTAssertEqual(parent.displayTitle(in: tabs), "Project A")
    }
}
