import XCTest
@testable import AtlasCore

/// Spec §3: a date-only string from the model means the user's LOCAL calendar
/// day — parsing it as UTC midnight shifts "due Friday" to Thursday evening
/// in US timezones.
final class CaptureDateParserTests: XCTestCase {

    func test_dateOnly_parsesAsLocalMidnight() {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 30
        XCTAssertEqual(CaptureDateParser.date(from: "2026-06-30"),
                       Calendar.current.date(from: c))
    }

    func test_fullISO_stillParses() {
        XCTAssertEqual(CaptureDateParser.date(from: "2026-06-30T17:30:00Z"),
                       Date(timeIntervalSince1970: 1_782_840_600))
    }
}
