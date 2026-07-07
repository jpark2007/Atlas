import XCTest
@testable import AtlasCore
@testable import Atlas

/// Gap-finding logic for auto-scheduling. Synthetic busy intervals only — no
/// AppState — so behavior is deterministic. Compares Dates built from the same
/// Calendar (never hardcoded clock strings).
final class SlotFinderTests: XCTestCase {
    private let cal = Calendar.current
    /// A fixed reference day, normalized to its start.
    private var day: Date { cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000)) }
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }
    /// End of the visible scheduling window. Uses date-adding so it's valid even when
    /// `endHour == 24` (where `at(24)`/`bySettingHour: 24` returns nil and would crash).
    private var windowEnd: Date {
        cal.date(byAdding: .hour, value: CalendarLayout.workdayEndHour - CalendarLayout.workdayStartHour, to: at(CalendarLayout.workdayStartHour))!
    }
    /// "now" before the visible window so it doesn't constrain unless intended.
    private var earlyNow: Date { at(0, 0) }

    private func slot(_ duration: Int, busy: [DateInterval], now: Date) -> Date? {
        SlotFinder.firstFreeSlot(durationMin: duration, on: day, busy: busy, now: now, calendar: cal)
    }

    func testEmptyDayReturnsStartHour() {
        XCTAssertEqual(slot(60, busy: [], now: earlyNow), at(CalendarLayout.workdayStartHour))
    }

    func testNowSnappedUpToFifteen() {
        // now = 9:05 → first candidate snaps up to 9:15
        XCTAssertEqual(slot(60, busy: [], now: at(9, 5)), at(9, 15))
    }

    func testNowExactlyOnBoundaryIsNotBumped() {
        XCTAssertEqual(slot(60, busy: [], now: at(9, 15)), at(9, 15))
    }

    func testSkipsLeadingBusyBlock() {
        let busy = [DateInterval(start: at(7), end: at(8))]
        XCTAssertEqual(slot(60, busy: busy, now: earlyNow), at(8))
    }

    func testFitsImmediatelyAfterShortBlock() {
        let busy = [DateInterval(start: at(7), end: at(7, 30))]
        XCTAssertEqual(slot(60, busy: busy, now: earlyNow), at(7, 30))
    }

    func testSnapsAfterUnalignedBlockEnd() {
        // Block ends 7:40 → next 15-min boundary is 7:45.
        let busy = [DateInterval(start: at(7), end: at(7, 40))]
        XCTAssertEqual(slot(60, busy: busy, now: earlyNow), at(7, 45))
    }

    func testFitsInGapBetweenEvents() {
        let busy = [
            DateInterval(start: at(7), end: at(8)),
            DateInterval(start: at(9), end: at(10)),
        ]
        // 8:00–9:00 gap fits a 60-min task.
        XCTAssertEqual(slot(60, busy: busy, now: earlyNow), at(8))
    }

    func testNowInsideEventPushesPastIt() {
        let busy = [DateInterval(start: at(9), end: at(10))]
        XCTAssertEqual(slot(30, busy: busy, now: at(9, 30)), at(10))
    }

    func testFullDayReturnsNil() {
        let busy = [DateInterval(start: at(CalendarLayout.workdayStartHour), end: windowEnd)]
        XCTAssertNil(slot(60, busy: busy, now: earlyNow))
    }

    func testTooLongToFitReturnsNil() {
        // Only 21:30–22:00 free (30 min) but task needs 120.
        let busy = [DateInterval(start: at(CalendarLayout.workdayStartHour), end: at(21, 30))]
        XCTAssertNil(slot(120, busy: busy, now: earlyNow))
    }

    func testPastDayReturnsNil() {
        // now after the whole window → nothing left today.
        XCTAssertNil(slot(60, busy: [], now: windowEnd))
    }

    func testChainedOverlapsResolve() {
        let busy = [
            DateInterval(start: at(7), end: at(8, 30)),
            DateInterval(start: at(8), end: at(9, 15)),
        ]
        // Overlapping blocks chain to 9:15.
        XCTAssertEqual(slot(60, busy: busy, now: earlyNow), at(9, 15))
    }
}
