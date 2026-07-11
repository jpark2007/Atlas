import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

/// Task 11 — the pure decisions behind Apple Calendar write-back. `shouldWriteBackApple`
/// gates the Atlas→Apple mirror; `excludingOwnMirrors` keeps a mirrored event from
/// double-displaying when EventKit re-reads it on the next fetch. Both are extracted from
/// the EventKit/app-state wiring so the logic can be verified in isolation.
final class AppleWritebackTests: XCTestCase {

    private func event(source: EventSource = .atlas,
                       isReadOnly: Bool = false,
                       googleEventId: String? = nil,
                       appleEventId: String? = nil) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return CalendarEvent(title: "E", subtitle: "", start: start,
                             end: start.addingTimeInterval(3600),
                             color: .blue, spaceName: "S",
                             isReadOnly: isReadOnly, source: source,
                             googleEventId: googleEventId, appleEventId: appleEventId)
    }

    // MARK: - shouldWriteBackApple gate

    /// The happy path: toggle on, access granted, a writable Atlas event → mirror it.
    func testGate_mirrorsWritableAtlasEventWhenEnabledAndAuthorized() {
        XCTAssertTrue(CalendarSync.shouldWriteBackApple(
            enabled: true, authorized: true, event: event()))
    }

    /// Toggle off → never mirror, even with access.
    func testGate_offWhenDisabled() {
        XCTAssertFalse(CalendarSync.shouldWriteBackApple(
            enabled: false, authorized: true, event: event()))
    }

    /// No EventKit access → never mirror, even when enabled.
    func testGate_offWhenNotAuthorized() {
        XCTAssertFalse(CalendarSync.shouldWriteBackApple(
            enabled: true, authorized: false, event: event()))
    }

    /// External events (Apple/Google/Canvas reads) are never re-mirrored — only `.atlas`.
    func testGate_offForNonAtlasSource() {
        for src in [EventSource.apple, .google, .canvas] {
            XCTAssertFalse(CalendarSync.shouldWriteBackApple(
                enabled: true, authorized: true, event: event(source: src)),
                "\(src) should not be mirrored")
        }
    }

    /// A read-only Atlas event (defensive) is not mirrored.
    func testGate_offForReadOnlyEvent() {
        XCTAssertFalse(CalendarSync.shouldWriteBackApple(
            enabled: true, authorized: true, event: event(isReadOnly: true)))
    }

    // MARK: - excludingOwnMirrors de-dupe

    /// An Apple event whose id is one of ours (we mirrored it) is dropped from the external
    /// pool — otherwise it double-displays: native tile + read-only Apple copy.
    func testDedupe_dropsOwnMirroredAppleEvent() {
        let apple = event(source: .apple, appleEventId: "A1")
        let result = CalendarSync.excludingOwnMirrors(
            external: [apple], ownGoogleIDs: [], ownAppleIDs: ["A1"])
        XCTAssertTrue(result.isEmpty)
    }

    /// A genuine Apple event we did NOT mirror is kept.
    func testDedupe_keepsUnrelatedAppleEvent() {
        let apple = event(source: .apple, appleEventId: "A2")
        let result = CalendarSync.excludingOwnMirrors(
            external: [apple], ownGoogleIDs: [], ownAppleIDs: ["A1"])
        XCTAssertEqual(result.count, 1)
    }

    /// The existing Google de-dupe still holds through the shared helper.
    func testDedupe_dropsOwnMirroredGoogleEvent() {
        let google = event(source: .google, googleEventId: "G1")
        let result = CalendarSync.excludingOwnMirrors(
            external: [google], ownGoogleIDs: ["G1"], ownAppleIDs: [])
        XCTAssertTrue(result.isEmpty)
    }

    /// An external event with no backing id (neither mirror) is always kept.
    func testDedupe_keepsEventWithNoIDs() {
        let ext = event(source: .apple)
        let result = CalendarSync.excludingOwnMirrors(
            external: [ext], ownGoogleIDs: ["G1"], ownAppleIDs: ["A1"])
        XCTAssertEqual(result.count, 1)
    }
}
