import XCTest
@testable import AtlasCore
@testable import Atlas

final class CaptureDateParserTests: XCTestCase {
    func testNilReturnsNil() { XCTAssertNil(CaptureDateParser.date(from: nil)) }
    func testWholeSecondsParses() {
        XCTAssertNotNil(CaptureDateParser.date(from: "2026-06-27T20:00:00Z"))
    }
    func testFractionalSecondsParses() {
        XCTAssertNotNil(CaptureDateParser.date(from: "2026-06-27T20:00:00.000Z"))
    }
    func testGarbageReturnsNil() { XCTAssertNil(CaptureDateParser.date(from: "not a date")) }
}
