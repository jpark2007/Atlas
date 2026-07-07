import XCTest
@testable import AtlasCore
@testable import Atlas

final class CaptureOutcomeTests: XCTestCase {
    func testDegradedIsDistinctFromPlainTask() {
        XCTAssertNotEqual(CaptureOutcome.degraded.confirmation,
                          CaptureOutcome.task(hasDate: false).confirmation)
    }
    func testTaskWithDateMentionsDue() {
        XCTAssertTrue(CaptureOutcome.task(hasDate: true).confirmation.lowercased().contains("due"))
    }
    func testDegradedMentionsOffline() {
        XCTAssertTrue(CaptureOutcome.degraded.confirmation.lowercased().contains("offline"))
    }
    func testEventAndNoteHaveCopy() {
        XCTAssertFalse(CaptureOutcome.event.confirmation.isEmpty)
        XCTAssertFalse(CaptureOutcome.note.confirmation.isEmpty)
    }
}
