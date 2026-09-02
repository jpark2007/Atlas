import XCTest
@testable import AtlasCore

/// Pre-picking the student's section from the schedule the class already has.
/// Weekdays are Foundation's: 1 = Sunday … 7 = Saturday, so 3 = Tuesday.
final class SyllabusSectionMatchTests: XCTestCase {

    /// One lecture everybody attends, three recitations of which the student is in one.
    private func sectionedGroup() -> SyllabusDraftGroup {
        SyllabusDraftGroup(meetingPattern: [
            MeetingBlock(weekdays: [2, 4], start: "14:00", end: "15:20",
                         sectionLabel: "Sec. 37–39", kind: "lecture"),
            MeetingBlock(weekdays: [3], start: "14:00", end: "15:20",
                         sectionLabel: "Section 37", kind: "recitation"),
            MeetingBlock(weekdays: [3], start: "15:50", end: "17:10",
                         sectionLabel: "Section 38", kind: "recitation"),
            MeetingBlock(weekdays: [3], start: "17:40", end: "19:00",
                         sectionLabel: "Section 39", kind: "recitation"),
        ])
    }

    func testOneMatchingBlockPrePicksThatSection() {
        var group = sectionedGroup()
        // The wizard's ICS gave Tuesday 15:55 — five minutes off Section 38's 15:50.
        let existing = [MeetingBlock(weekdays: [3], start: "15:55", end: "17:10")]
        XCTAssertEqual(SyllabusSectionMatch.autoPick(&group, existing: existing), "Section 38")
        XCTAssertEqual(group.meetingIncluded, [true, false, true, false])
        XCTAssertEqual(group.includedMeetings.map(\.sectionLabel), ["Sec. 37–39", "Section 38"])
    }

    func testATimeOutsideToleranceDoesNotMatch() {
        var group = sectionedGroup()
        let existing = [MeetingBlock(weekdays: [3], start: "16:10", end: "17:30")]
        XCTAssertNil(SyllabusSectionMatch.autoPick(&group, existing: existing))
        XCTAssertEqual(group.meetingIncluded, [true, true, true, true])
    }

    func testAWrongWeekdayDoesNotMatch() {
        var group = sectionedGroup()
        // Same clock time as Section 38, but Thursday.
        let existing = [MeetingBlock(weekdays: [5], start: "15:50", end: "17:10")]
        XCTAssertNil(SyllabusSectionMatch.match(for: group, existing: existing))
    }

    func testTwoMatchesChangeNothing() {
        var group = sectionedGroup()
        let existing = [MeetingBlock(weekdays: [3], start: "15:50", end: "17:10"),
                        MeetingBlock(weekdays: [3], start: "17:40", end: "19:00")]
        XCTAssertNil(SyllabusSectionMatch.autoPick(&group, existing: existing))
        XCTAssertEqual(group.meetingIncluded, [true, true, true, true])
    }

    func testNoExistingPatternChangesNothing() {
        var group = sectionedGroup()
        XCTAssertNil(SyllabusSectionMatch.autoPick(&group, existing: []))
        XCTAssertEqual(group.meetingIncluded, [true, true, true, true])
    }

    /// A single-section syllabus has nothing to disambiguate, so nothing is pre-picked.
    func testASingleSectionIsLeftAlone() {
        var group = SyllabusDraftGroup(meetingPattern: [
            MeetingBlock(weekdays: [3], start: "15:50", end: "17:10",
                         sectionLabel: "Section 38", kind: "recitation"),
        ])
        let existing = [MeetingBlock(weekdays: [3], start: "15:50", end: "17:10")]
        XCTAssertNil(SyllabusSectionMatch.autoPick(&group, existing: existing))
        XCTAssertEqual(group.meetingIncluded, [true])
    }

    /// The lecture everybody shares must not be what decides the section.
    func testTheSharedLectureDoesNotDecide() {
        var group = sectionedGroup()
        let existing = [MeetingBlock(weekdays: [2, 4], start: "14:00", end: "15:20")]
        XCTAssertNil(SyllabusSectionMatch.autoPick(&group, existing: existing))
        XCTAssertEqual(group.meetingIncluded, [true, true, true, true])
    }
}
