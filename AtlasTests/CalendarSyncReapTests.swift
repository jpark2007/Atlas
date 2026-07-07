import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

/// Phase 1a — the data-loss-critical reaper. `reapableEventIDs` decides which local
/// Atlas-origin events were deleted on Google (absent from a fresh listing) and should
/// be removed locally. These tests pin the safety rules from the design review:
/// window-scoping (B1) and the pending-push snapshot guard (B2).
final class CalendarSyncReapTests: XCTestCase {

    private let windowStart = Date(timeIntervalSince1970: 1_780_000_000)
    private var windowEnd: Date { windowStart.addingTimeInterval(7 * 86_400) }
    private var inWindow: Date { windowStart.addingTimeInterval(86_400) }      // day 1
    private var outOfWindow: Date { windowStart.addingTimeInterval(30 * 86_400) }

    private func event(_ gid: String?,
                       start: Date,
                       source: EventSource = .atlas) -> CalendarEvent {
        CalendarEvent(title: "E", subtitle: "", start: start,
                      end: start.addingTimeInterval(3600),
                      color: .blue, spaceName: "S",
                      source: source, googleEventId: gid)
    }

    /// The core case: a mirror we pushed, gone from Google, in-window, pre-fetch eligible.
    func testReapsMirrorDeletedOnGoogle() {
        let e = event("g1", start: inWindow)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: [],
            eligibleGoogleIDs: ["g1"],
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertEqual(ids, [e.id])
    }

    /// Still present on Google → keep it.
    func testKeepsEventStillPresentOnGoogle() {
        let e = event("g1", start: inWindow)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: ["g1"],
            eligibleGoogleIDs: ["g1"],
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertTrue(ids.isEmpty)
    }

    /// B1 — an event outside the fetched window is absent for benign reasons; never reap.
    func testDoesNotReapOutsideFetchedWindow() {
        let e = event("g1", start: outOfWindow)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: [],
            eligibleGoogleIDs: ["g1"],
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertTrue(ids.isEmpty)
    }

    /// B2 — a gid that was NOT in the pre-fetch snapshot is a freshly-pushed event whose
    /// id landed mid-pull; the listing predates it, so it must not be reaped.
    func testDoesNotReapPendingPushNotInEligibleSnapshot() {
        let e = event("g1", start: inWindow)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: [],
            eligibleGoogleIDs: [],          // snapshot taken before this id existed
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertTrue(ids.isEmpty)
    }

    /// Only Atlas-origin mirrors are reaped here; Google-origin reads are replaced wholesale.
    func testDoesNotReapGoogleOriginEvent() {
        let e = event("g1", start: inWindow, source: .google)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: [],
            eligibleGoogleIDs: ["g1"],
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertTrue(ids.isEmpty)
    }

    /// An Atlas event never pushed (no gid) is purely local — never reap.
    func testDoesNotReapEventWithoutGoogleID() {
        let e = event(nil, start: inWindow)
        let ids = CalendarSync.reapableEventIDs(
            events: [e],
            presentGoogleIDs: [],
            eligibleGoogleIDs: [],
            windowStart: windowStart, windowEnd: windowEnd)
        XCTAssertTrue(ids.isEmpty)
    }
}
