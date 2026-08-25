import XCTest
import SwiftUI
@testable import AtlasCore

/// Phase 3 — cross-calendar dedup. The same real block arriving from school ICS + Google,
/// or Google + Apple, must collapse to one tile; anything the rule isn't sure about must
/// show twice. These are the near-misses that decide where that line sits.
final class CalendarDedupTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_770_000_000) // fixed instant

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func event(_ title: String,
                       _ source: EventSource,
                       start: Date,
                       minutes: Int = 60,
                       isDeadline: Bool = false) -> CalendarEvent {
        CalendarEvent(title: title,
                      subtitle: "",
                      start: start,
                      end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                      color: .red,
                      spaceName: "School",
                      source: source,
                      isDeadline: isDeadline)
    }

    // MARK: - Title matching

    func test_punctuationAndSpacingDifferences_collapse() {
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO201 - Lecture", .icsFeed(name: "School"), start: at(9))]
        let out = CalendarSync.collapsingDuplicates(pool)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .google)
    }

    func test_differentCourseNumber_isNotADuplicate() {
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 301 Lecture", .icsFeed(name: "School"), start: at(9))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    func test_caseAndAccentDifferences_collapse() {
        let pool = [event("café meeting", .google, start: at(9)),
                    event("CAFE MEETING", .apple, start: at(9))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    func test_oneTitleExtendingTheOther_collapses() {
        let pool = [event("Organic Chemistry Lab", .google, start: at(13)),
                    event("Organic Chemistry Lab — Room 214", .apple, start: at(13))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    func test_shortSharedPrefix_isTooWeakToCollapse() {
        // "Lab" is a prefix of "Lab safety quiz" but far too short to be distinctive.
        let pool = [event("Lab", .google, start: at(13)),
                    event("Lab safety quiz", .apple, start: at(13))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    func test_emptyTitles_neverCollapse() {
        let pool = [event("", .google, start: at(9)), event("", .apple, start: at(9))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    // MARK: - Time matching

    func test_identicalTitleDifferentDay_isNotADuplicate() {
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 201 Lecture", .apple, start: at(9).addingTimeInterval(86_400))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    func test_startsWithinSecondsOfEachOther_collapse() {
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 201 Lecture", .apple, start: at(9).addingTimeInterval(30))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    func test_sameDayHeavyOverlap_collapses() {
        // 9:00–10:00 vs 9:15–10:15 — 45 of 60 minutes shared, comfortably one block.
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 201 Lecture", .apple, start: at(9, 15))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    func test_sameDayShallowOverlap_showsBoth() {
        // 9:00–10:00 vs 9:50–10:50 — 10 of 60 minutes shared. When unsure, show both.
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 201 Lecture", .apple, start: at(9, 50))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    func test_sameTitleSameDayNoOverlap_showsBoth() {
        // A course that genuinely meets twice in one day is two real blocks.
        let pool = [event("BIO 201 Lecture", .google, start: at(9)),
                    event("BIO 201 Lecture", .apple, start: at(14))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    func test_zeroLengthEventsAtDifferentTimes_showBoth() {
        let pool = [event("Advising", .google, start: at(9), minutes: 0),
                    event("Advising", .apple, start: at(10), minutes: 0)]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 2)
    }

    // MARK: - Winner order + the "also in" note

    func test_atlasNativeBeatsGoogleAndApple_regardlessOfInputOrder() {
        let pool = [event("Study group", .apple, start: at(16)),
                    event("Study group", .google, start: at(16)),
                    event("Study group", .atlas, start: at(16))]
        let out = CalendarSync.collapsingDuplicates(pool)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .atlas)
        XCTAssertEqual(out[0].duplicateSources, [.apple, .google])
    }

    func test_googleBeatsIcsFeed_andCarriesTheFeedsOwnName() {
        let pool = [event("BIO 201 Lecture", .icsFeed(name: "Schoology"), start: at(9)),
                    event("BIO 201 Lecture", .google, start: at(9))]
        let out = CalendarSync.collapsingDuplicates(pool)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .google)
        // Rule 5: the hidden copy is labelled as the feed it actually came from.
        XCTAssertEqual(out[0].duplicateSources.map(\.displayName), ["Schoology"])
    }

    func test_winnerKeepsItsOwnSourceAndReadOnlyFlag() {
        let pool = [event("Study group", .atlas, start: at(16)),
                    event("Study group", .apple, start: at(16))]
        let out = CalendarSync.collapsingDuplicates(pool)
        XCTAssertEqual(out[0].source, .atlas)
        XCTAssertFalse(out[0].isReadOnly)
    }

    func test_nonDuplicatesCarryNoAlsoInNote() {
        let out = CalendarSync.collapsingDuplicates([event("Standup", .google, start: at(9))])
        XCTAssertTrue(out[0].duplicateSources.isEmpty)
    }

    func test_threeWayDuplicate_listsBothHiddenSourcesOnce() {
        let pool = [event("Chem lecture", .google, start: at(11)),
                    event("Chem lecture", .apple, start: at(11)),
                    event("Chem lecture", .icsFeed(name: "School"), start: at(11))]
        let out = CalendarSync.collapsingDuplicates(pool)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .google)
        XCTAssertEqual(out[0].duplicateSources.map(\.displayName), ["Apple Calendar", "School"])
    }

    func test_unrelatedEventsKeepTheirOrder() {
        let pool = [event("Standup", .google, start: at(9)),
                    event("Lunch", .apple, start: at(12)),
                    event("Gym", .atlas, start: at(18))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).map(\.title),
                       ["Standup", "Lunch", "Gym"])
    }

    // MARK: - Deadlines

    func test_deadlinePillIsNeverCollapsedIntoAWorkSession() {
        var deadline = event("English essay", .atlas, start: at(17), minutes: 0, isDeadline: true)
        deadline.isAllDay = true
        let session = event("English essay", .atlas, start: at(17), minutes: 60)
        XCTAssertEqual(CalendarSync.collapsingDuplicates([deadline, session]).count, 2)
    }

    // MARK: - Work-session mirror round trip (the prefix must not duplicate)

    func test_mirroredWorkSessionComingBackInbound_collapsesIntoTheNativeSession() {
        var session = event("English essay", .atlas, start: at(15))
        session.isWorkBlock = true
        let mirror = event("Work: English essay", .apple, start: at(15))
        let out = CalendarSync.collapsingDuplicates([session, mirror])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .atlas)
        XCTAssertTrue(out[0].isWorkBlock)
        XCTAssertEqual(out[0].duplicateSources.map(\.displayName), ["Apple Calendar"])
    }

    func test_customPrefixIsHonoured() {
        var session = event("English essay", .atlas, start: at(15))
        session.isWorkBlock = true
        let mirror = event("Focus — English essay", .google, start: at(15))
        XCTAssertEqual(
            CalendarSync.collapsingDuplicates([session, mirror], workSessionPrefix: "Focus — ").count, 1)
        // With the default prefix the two titles are simply different events.
        XCTAssertEqual(CalendarSync.collapsingDuplicates([session, mirror]).count, 2)
    }

    func test_prefixIsStrippedFromBothSides_soTwoMirrorsStillCollapse() {
        let pool = [event("Work: English essay", .google, start: at(15)),
                    event("Work: English essay", .apple, start: at(15))]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    func test_prefixOnlyTitleIsNotStrippedToNothing() {
        let pool = [event("Work", .google, start: at(15)),
                    event("Work", .apple, start: at(15))]
        // Still one block — but it collapsed on the real title, not on an emptied key.
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool).count, 1)
    }

    // MARK: - Mirror titling

    func test_mirroredWorkSessionTitle_addsTheDefaultPrefix() {
        XCTAssertEqual(CalendarSync.mirroredWorkSessionTitle("English essay"),
                       "Work: English essay")
    }

    func test_mirroredWorkSessionTitle_neverDoublePrefixes() {
        XCTAssertEqual(CalendarSync.mirroredWorkSessionTitle("Work: English essay"),
                       "Work: English essay")
    }

    func test_mirroredWorkSessionTitle_honoursACustomPrefix() {
        XCTAssertEqual(CalendarSync.mirroredWorkSessionTitle("English essay", prefix: "Focus — "),
                       "Focus — English essay")
    }

    func test_mirroredWorkSessionTitle_withEmptyPrefix_leavesTitleAlone() {
        XCTAssertEqual(CalendarSync.mirroredWorkSessionTitle("English essay", prefix: ""),
                       "English essay")
    }
}
