import XCTest
@testable import AtlasCore

/// The one-time `.ics` FILE import — what a registrar's "Export course schedule" button
/// actually hands a student. Only what a class schedule needs is parsed; the rest of the
/// file is ignored rather than half-understood.
final class ICSFileTests: XCTestCase {

    /// Everything is read in a fixed zone so a floating time means the same thing in CI.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func ics(_ body: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(body)\r\nEND:VCALENDAR\r\n"
    }

    // MARK: - Events

    func testReadsSummaryTimesAndLocation() {
        let events = ICSFile.events(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry\r
        DTSTART;TZID=America/New_York:20260901T100000\r
        DTEND;TZID=America/New_York:20260901T105000\r
        LOCATION:Tech Hall 204\r
        END:VEVENT
        """), calendar: calendar)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.summary, "Organic Chemistry")
        XCTAssertEqual(events.first?.location, "Tech Hall 204")
        XCTAssertEqual(calendar.component(.hour, from: events[0].start), 10)
        XCTAssertEqual(calendar.component(.minute, from: events[0].end!), 50)
    }

    /// A folded line (RFC 5545 wraps at 75 octets) must rejoin, or long class names arrive
    /// truncated.
    func testUnfoldsWrappedLines() {
        let events = ICSFile.events(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Introduction to Organic\r
          Chemistry II\r
        DTSTART:20260901T100000\r
        DTEND:20260901T105000\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(events.first?.summary, "Introduction to Organic Chemistry II")
    }

    func testEventWithoutASummaryOrStartIsSkipped() {
        XCTAssertTrue(ICSFile.events(in: ics("""
        BEGIN:VEVENT\r
        DTSTART:20260901T100000\r
        END:VEVENT
        """), calendar: calendar).isEmpty)
    }

    // MARK: - Weekly RRULE

    func testWeeklyRuleGivesItsByDays() {
        let events = ICSFile.events(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry\r
        DTSTART:20260901T100000\r
        DTEND:20260901T105000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261211T235959Z\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(events.first?.weekdays, [2, 4, 6])   // Mon, Wed, Fri
    }

    /// Anything that isn't a weekly rule is not a meeting pattern — the event's own day is
    /// used instead of pretending to understand the rule.
    func testNonWeeklyRuleYieldsNoWeekdays() {
        let events = ICSFile.events(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Registration opens\r
        DTSTART:20260901T100000\r
        DTEND:20260901T105000\r
        RRULE:FREQ=MONTHLY;BYMONTHDAY=1\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(events.first?.weekdays, [])
    }

    // MARK: - Course attribution (same rule as the server's feed path)

    func testTrailingBracketIsTheCourseCode() {
        let parsed = ICSFile.course(from: "Essay 2 due [CHEM 101]")
        XCTAssertEqual(parsed.title, "Essay 2 due")
        XCTAssertEqual(parsed.code, "CHEM 101")
    }

    func testSummaryWithoutABracketIsAllTitle() {
        let parsed = ICSFile.course(from: "Organic Chemistry")
        XCTAssertEqual(parsed.title, "Organic Chemistry")
        XCTAssertNil(parsed.code)
    }

    func testNormalizeCodeStripsSpacingAndCase() {
        XCTAssertEqual(ICSFile.normalizeCode(" chem 101 "), "CHEM101")
    }

    // MARK: - Courses

    func testRecurringEventBecomesOneClassWithOneMeetingBlock() {
        let courses = ICSFile.courses(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry [CHEM 201]\r
        DTSTART;TZID=America/New_York:20260901T100000\r
        DTEND;TZID=America/New_York:20260901T105000\r
        LOCATION:Tech Hall 204\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r
        END:VEVENT
        """), calendar: calendar)

        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].name, "Organic Chemistry")
        XCTAssertEqual(courses[0].code, "CHEM 201")
        XCTAssertEqual(courses[0].meetings,
                       [MeetingBlock(weekdays: [2, 4, 6], start: "10:00", end: "10:50",
                                     location: "Tech Hall 204")])
    }

    /// Plenty of exports spell every occurrence out instead of using RRULE. The class
    /// should still read as "MW", not as thirty separate classes.
    func testSpelledOutOccurrencesFoldIntoOneWeeklyBlock() {
        let courses = ICSFile.courses(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Linear Algebra [MATH 210]\r
        DTSTART;TZID=America/New_York:20260901T140000\r
        DTEND;TZID=America/New_York:20260901T151500\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Linear Algebra [MATH 210]\r
        DTSTART;TZID=America/New_York:20260903T140000\r
        DTEND;TZID=America/New_York:20260903T151500\r
        END:VEVENT
        """), calendar: calendar)

        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].meetings.count, 1)
        XCTAssertEqual(courses[0].meetings[0].weekdays, [3, 5])   // Tue 9/1, Thu 9/3 in 2026
    }

    /// Lecture and lab are the same class at two different times — two blocks, one class.
    func testTwoTimesUnderOneCodeBecomeTwoBlocks() {
        let courses = ICSFile.courses(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry [CHEM 201]\r
        DTSTART;TZID=America/New_York:20260901T100000\r
        DTEND;TZID=America/New_York:20260901T105000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry Lab [CHEM 201]\r
        DTSTART;TZID=America/New_York:20260903T130000\r
        DTEND;TZID=America/New_York:20260903T160000\r
        RRULE:FREQ=WEEKLY;BYDAY=TH\r
        END:VEVENT
        """), calendar: calendar)

        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].meetings.map(\.start), ["10:00", "13:00"])
        XCTAssertEqual(courses[0].meetings[1].weekdays, [5])
    }

    func testDifferentCoursesStaySeparateAndKeepFileOrder() {
        let courses = ICSFile.courses(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry [CHEM 201]\r
        DTSTART:20260901T100000\r
        DTEND:20260901T105000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Linear Algebra [MATH 210]\r
        DTSTART:20260901T140000\r
        DTEND:20260901T151500\r
        RRULE:FREQ=WEEKLY;BYDAY=TU,TH\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(courses.map(\.name), ["Organic Chemistry", "Linear Algebra"])
    }

    func testEmptyOrJunkInputYieldsNothing() {
        XCTAssertTrue(ICSFile.courses(in: "", calendar: calendar).isEmpty)
        XCTAssertTrue(ICSFile.courses(in: "not a calendar at all", calendar: calendar).isEmpty)
    }

    // MARK: - Classification
    //
    // Drew's real "Fall 2026 Schedule.ics" landed as thirteen "classes", among them
    // "Fall Semester Ends" and "General Psychology Final Exam". Only what repeats weekly
    // is a class; the rest is a Key Date or an event.

    /// A single non-recurring item is never a class, however course-shaped its title.
    func testOneOffIsNotAClass() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Career Fair\r
        DTSTART:20261005T160000\r
        DTEND:20261005T180000\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertTrue(found.courses.isEmpty)
        XCTAssertTrue(found.keyDates.isEmpty)
        XCTAssertEqual(found.exams.map(\.title), ["Career Fair"])
        XCTAssertFalse(found.exams[0].isExam)   // not exam-titled: an event, not an exam
    }

    func testTermBoundariesBecomeKeyDatesNotClasses() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Fall Semester Ends\r
        DTSTART;VALUE=DATE:20261218\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Winter Session Begins\r
        DTSTART;VALUE=DATE:20270104\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Thanksgiving Break Begins\r
        DTSTART;VALUE=DATE:20261123\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Reading Day\r
        DTSTART;VALUE=DATE:20261211\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertTrue(found.courses.isEmpty)
        XCTAssertEqual(found.keyDates.map(\.title),
                       ["Fall Semester Ends", "Winter Session Begins",
                        "Thanksgiving Break Begins", "Reading Day"])
    }

    func testKeyDateKindsFollowTheirWording() {
        XCTAssertEqual(ICSFile.keyDateKind("Fall Semester Ends"), .classesEnd)
        XCTAssertEqual(ICSFile.keyDateKind("Winter Session Begins"), .classesBegin)
        XCTAssertEqual(ICSFile.keyDateKind("Thanksgiving Break Begins"), .breakPeriod)
        XCTAssertEqual(ICSFile.keyDateKind("No Classes"), .holiday)
    }

    /// "Midterm" contains "term", but with no begins/ends it is not a boundary.
    func testExamTitleIsNotMistakenForATermBoundary() {
        XCTAssertFalse(ICSFile.isKeyDateTitle("Midterm Exam"))
        XCTAssertTrue(ICSFile.isExamTitle("Midterm Exam"))
    }

    /// The headline case: an exam is an event at its time, tied to the class it names —
    /// and the class itself stays one class, not two.
    func testExamIsAttributedToTheClassItNames() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:General Psychology\r
        DTSTART;TZID=America/New_York:20260901T090000\r
        DTEND;TZID=America/New_York:20260901T095000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:General Psychology Final Exam\r
        DTSTART;TZID=America/New_York:20261215T080000\r
        DTEND;TZID=America/New_York:20261215T100000\r
        END:VEVENT
        """), calendar: calendar)

        XCTAssertEqual(found.courses.map(\.name), ["General Psychology"])
        XCTAssertEqual(found.exams.count, 1)
        XCTAssertTrue(found.exams[0].isExam)
        XCTAssertEqual(found.exams[0].courseID, "General Psychology")
        XCTAssertEqual(calendar.component(.hour, from: found.exams[0].start), 8)
    }

    /// No class matched ⇒ the exam is still an event. It must never become a class.
    func testUnmatchedExamStaysUnassigned() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Calculus I Final Exam\r
        DTSTART:20261215T080000\r
        DTEND:20261215T100000\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertTrue(found.courses.isEmpty)
        XCTAssertEqual(found.exams.count, 1)
        XCTAssertNil(found.exams[0].courseID)
    }

    /// The longer name wins, so a final doesn't attach itself to a shorter class whose
    /// name happens to be a substring.
    func testLongestMatchingClassNameWins() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Psychology\r
        DTSTART:20260901T090000\r
        DTEND:20260901T095000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:General Psychology\r
        DTSTART:20260901T110000\r
        DTEND:20260901T115000\r
        RRULE:FREQ=WEEKLY;BYDAY=TU\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:General Psychology Final Exam\r
        DTSTART:20261215T080000\r
        DTEND:20261215T100000\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(found.exams.first?.courseID, "General Psychology")
    }

    /// Spelled-out occurrences still make a class — the recurrence test is "seen on more
    /// than one day", not "has an RRULE".
    func testSpelledOutOccurrencesStillCountAsRecurring() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Linear Algebra [MATH 210]\r
        DTSTART;TZID=America/New_York:20260901T140000\r
        DTEND;TZID=America/New_York:20260901T151500\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Linear Algebra [MATH 210]\r
        DTSTART;TZID=America/New_York:20260903T140000\r
        DTEND;TZID=America/New_York:20260903T151500\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(found.courses.count, 1)
        XCTAssertTrue(found.exams.isEmpty)
    }

    /// A class carries its first occurrence, so a row re-typed as an exam still knows when.
    func testCourseCarriesItsEarliestStart() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry [CHEM 201]\r
        DTSTART;TZID=America/New_York:20260903T100000\r
        DTEND;TZID=America/New_York:20260903T105000\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Organic Chemistry [CHEM 201]\r
        DTSTART;TZID=America/New_York:20260901T100000\r
        DTEND;TZID=America/New_York:20260901T105000\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: found.courses[0].start), 1)
    }

    /// An all-day break flag has no clock times to meet at: no meeting block, and it lands
    /// on the term as a Key Date rather than on the floor.
    func testAllDayBreakIsAKeyDateWithNoMeetingBlock() {
        let found = ICSFile.classify(in: ics("""
        BEGIN:VEVENT\r
        SUMMARY:Fall Break Begins\r
        DTSTART;VALUE=DATE:20261123\r
        DTEND;VALUE=DATE:20261128\r
        END:VEVENT
        """), calendar: calendar)
        XCTAssertTrue(found.courses.isEmpty)
        XCTAssertEqual(found.keyDates.count, 1)
    }
}
