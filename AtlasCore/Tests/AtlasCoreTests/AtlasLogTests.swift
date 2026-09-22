import XCTest
@testable import AtlasCore

/// The 2026-09-18 "everything overdue" report arrived with `log = null`: the ring buffer
/// only records failures, a clean session has none, and the sheet sends nil for an empty
/// snapshot. The attachment must always carry the reporter's time zone — that report's
/// root cause was a date bug, and the time zone had to be guessed.
final class AtlasLogTests: XCTestCase {
    func testReportAttachmentIsNeverEmptyAndNamesTheTimeZone() {
        let log = AtlasLog.reportAttachment(timeZone: TimeZone(identifier: "America/Toronto")!)
        XCTAssertFalse(log.isEmpty)
        XCTAssertTrue(log.hasPrefix("context: tz=America/Toronto"), log)
    }

    func testReportAttachmentStaysWithinTheColumnLimit() {
        for _ in 0..<200 { AtlasLog.append(String(repeating: "x", count: 200)) }
        XCTAssertLessThanOrEqual(AtlasLog.reportAttachment().count, 16000)
    }
}
