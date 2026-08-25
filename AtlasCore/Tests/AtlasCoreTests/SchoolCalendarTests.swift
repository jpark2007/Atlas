import XCTest
import SwiftUI
@testable import AtlasCore

/// School framework, stage B: turning a term + its classes into dated calendar blocks,
/// and how those blocks behave when the same lecture also arrives from another calendar.
final class SchoolCalendarTests: XCTestCase {

    private func day(_ s: String) -> Date { TermDay.date(from: s)! }

    /// Fall 2026: Sep 1 – Dec 15, with Thanksgiving off and an add/drop deadline.
    private var fall: Term {
        Term(name: "Fall 2026",
             startsOn: day("2026-09-01"),
             endsOn:   day("2026-12-15"),
             keyDates: [
                TermKeyDate(label: "Add/drop ends", date: day("2026-09-11"), kind: .addDrop),
                TermKeyDate(label: "Thanksgiving",  date: day("2026-11-26"), kind: .holiday),
             ])
    }

    /// MWF 10:00–10:50 in Tech 204. 2026-09-02 is a Wednesday.
    private func bio(_ blocks: [MeetingBlock]) -> Project {
        var p = Project(name: "Bio 201", code: "BIO 201", isClass: true,
                        spaceName: "School", spaceColor: .blue)
        p.meetingPattern = blocks
        return p
    }

    private var mwf: MeetingBlock {
        MeetingBlock(weekdays: [2, 4, 6], start: "10:00", end: "10:50", location: "Tech 204")
    }

    // MARK: - Meetings

    func testMeetingIsDrawnOnAPatternWeekday() {
        let meetings = SchoolCalendar.meetings(on: day("2026-09-02"), classes: [bio([mwf])], term: fall)
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(meetings.first?.className, "Bio 201")
        XCTAssertEqual(meetings.first?.location, "Tech 204")
        XCTAssertEqual(Calendar.current.component(.hour, from: meetings[0].start), 10)
        XCTAssertEqual(Calendar.current.component(.minute, from: meetings[0].end), 50)
    }

    func testNoMeetingOnANonPatternWeekday() {
        // 2026-09-03 is a Thursday; the pattern is Mon/Wed/Fri.
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-09-03"), classes: [bio([mwf])], term: fall).isEmpty)
    }

    func testNoMeetingOutsideTheTerm() {
        // 2026-08-26 is a Wednesday, but the term hasn't begun.
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-08-26"), classes: [bio([mwf])], term: fall).isEmpty)
        // 2026-12-16 is a Wednesday one day after the term ends.
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-12-16"), classes: [bio([mwf])], term: fall).isEmpty)
    }

    func testHolidayKeyDateStopsMeetings() {
        // 2026-11-26 is a Thursday… but Thanksgiving is a holiday, and the class doesn't
        // meet Thursdays anyway — so use a holiday landing on a Wednesday to be sure.
        var term = fall
        term.keyDates.append(TermKeyDate(label: "Fall break", date: day("2026-11-25"), kind: .breakPeriod))
        XCTAssertTrue(SchoolCalendar.isBreakDay(day("2026-11-25"), in: term))
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-11-25"), classes: [bio([mwf])], term: term).isEmpty)
    }

    func testAddDropDeadlineIsAFlagNotADayOff() {
        // 2026-09-11 is a Friday: the add/drop flag must not cancel class.
        XCTAssertFalse(SchoolCalendar.isBreakDay(day("2026-09-11"), in: fall))
        XCTAssertEqual(SchoolCalendar.meetings(on: day("2026-09-11"), classes: [bio([mwf])], term: fall).count, 1)
        XCTAssertEqual(SchoolCalendar.keyDates(on: day("2026-09-11"), in: fall).first?.label, "Add/drop ends")
    }

    func testArchivedClassDrawsNothing() {
        var klass = bio([mwf])
        klass.archivedAt = Date()
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-09-02"), classes: [klass], term: fall).isEmpty)
    }

    func testUnparseableOrInvertedBlockIsSkippedNotGuessedAt() {
        let garbage = bio([MeetingBlock(weekdays: [4], start: "ten", end: "10:50"),
                           MeetingBlock(weekdays: [4], start: "11:00", end: "10:00")])
        XCTAssertTrue(SchoolCalendar.meetings(on: day("2026-09-02"), classes: [garbage], term: fall).isEmpty)
    }

    func testMeetingsAreTimeOrdered() {
        let two = bio([MeetingBlock(weekdays: [4], start: "14:00", end: "15:00"),
                       MeetingBlock(weekdays: [4], start: "10:00", end: "10:50")])
        let meetings = SchoolCalendar.meetings(on: day("2026-09-02"), classes: [two], term: fall)
        XCTAssertEqual(meetings.map { Calendar.current.component(.hour, from: $0.start) }, [10, 14])
    }

    // MARK: - Door 2: the lecture is also in Google

    /// A synthesized class meeting and the same lecture imported from Google collapse into
    /// ONE tile — attribution, not duplication — with the writable Atlas copy winning and
    /// carrying Google as an "also in" source. No new matching code: the Phase-3 dedup
    /// rule (normalized title + same start) already covers it.
    func testSynthesizedMeetingAbsorbsTheGoogleCopy() {
        let meeting = SchoolCalendar.meetings(on: day("2026-09-02"), classes: [bio([mwf])], term: fall)[0]
        let synthesized = CalendarEvent(title: meeting.className, subtitle: "Tech 204",
                                        start: meeting.start, end: meeting.end,
                                        color: .blue, spaceName: "School",
                                        isReadOnly: true, source: .atlas)
        let imported = CalendarEvent(title: "BIO 201", subtitle: "",
                                     start: meeting.start, end: meeting.end,
                                     color: .gray, spaceName: "School",
                                     isReadOnly: true, source: .google, isRecurring: true)

        let collapsed = CalendarSync.collapsingDuplicates([synthesized, imported])
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.source, .atlas)
        XCTAssertEqual(collapsed.first?.duplicateSources, [.google])
    }

    /// Two different classes back to back are NOT one block, however adjacent.
    func testDifferentClassesDoNotCollapse() {
        let start = SchoolCalendar.time("10:00", on: day("2026-09-02"))!
        let end   = SchoolCalendar.time("10:50", on: day("2026-09-02"))!
        let a = CalendarEvent(title: "Bio 201", subtitle: "", start: start, end: end,
                              color: .blue, spaceName: "School", source: .atlas)
        let b = CalendarEvent(title: "Chem 110", subtitle: "", start: start, end: end,
                              color: .green, spaceName: "School", source: .google)
        XCTAssertEqual(CalendarSync.collapsingDuplicates([a, b]).count, 2)
    }

    // MARK: - Next term name

    func testNextTermNameFollowsTheAcademicCycle() {
        XCTAssertEqual(SchoolCalendar.nextTermName(after: "Fall 2026"), "Spring 2027")
        XCTAssertEqual(SchoolCalendar.nextTermName(after: "Spring 2027"), "Summer 2027")
        XCTAssertEqual(SchoolCalendar.nextTermName(after: "Summer 2027"), "Fall 2027")
        // Anything Atlas can't read leaves the field blank rather than guessing wrong.
        XCTAssertEqual(SchoolCalendar.nextTermName(after: "Michaelmas"), "")
    }
}
