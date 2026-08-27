import XCTest
import SwiftUI
@testable import AtlasCore

/// v1.1 Phase 1 — all-day events are floating dates, timed events are absolute instants.
///
/// The canonical encoding is **UTC midnight of the intended calendar date**: `2026-09-07T00:00:00Z`
/// means "Sept 7", everywhere, forever. Every assertion here is deliberately pinned to
/// `America/Los_Angeles` (via injected `Calendar`s, never by mutating process state) because
/// the bug this file exists for is *invisible* under UTC — a UTC-midnight instant reads as the
/// previous day anywhere west of Greenwich.
final class AllDayTimezoneTests: XCTestCase {

    private static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private let la = calendar("America/Los_Angeles")
    private let utc = calendar("UTC")

    /// The canonical all-day instant for a calendar date.
    private func allDayInstant(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func event(_ title: String,
                       _ source: EventSource,
                       start: Date,
                       minutes: Int = 0,
                       isAllDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: title,
                      subtitle: "",
                      start: start,
                      end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                      color: .red,
                      spaceName: "School",
                      isAllDay: isAllDay,
                      source: source)
    }

    // MARK: - hasSpecificTime

    func test_allDayEvent_hasNoSpecificTime_westOfGreenwich() {
        let labourDay = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        // The trap this guards: read locally, the canonical instant is 5 PM on Sept 6 in LA.
        XCTAssertEqual(la.component(.day, from: labourDay.start), 6)
        XCTAssertEqual(la.component(.hour, from: labourDay.start), 17)
        // ...and yet it is an all-day flag, so it must never claim a clock time.
        XCTAssertFalse(labourDay.hasSpecificTime)
    }

    func test_allDayEvent_hasNoSpecificTime_eastOfGreenwich() {
        // Tokyo reads the same instant as 9 AM on Sept 7 — the other side of the same bug.
        let tokyo = Self.calendar("Asia/Tokyo")
        let labourDay = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        XCTAssertEqual(tokyo.component(.hour, from: labourDay.start), 9)
        XCTAssertFalse(labourDay.hasSpecificTime)
    }

    func test_timedEvent_hasSpecificTime() {
        let threePM = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0,
                                            of: Date(timeIntervalSince1970: 1_770_000_000))!
        XCTAssertTrue(event("Advising", .atlas, start: threePM, minutes: 60).hasSpecificTime)
    }

    func test_timedEventAtLocalMidnight_hasNoSpecificTime() {
        // Unchanged legacy behaviour: a bare-date deadline that was never flagged all-day
        // still reads as date-only rather than "12:00 AM".
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        XCTAssertFalse(event("Essay due", .atlas, start: midnight).hasSpecificTime)
    }

    // MARK: - Dedup

    func test_appleAndGoogleAllDayCopies_ofSameDate_collapseToOne() {
        // Post-normalization both sources hand us the canonical UTC-midnight instant.
        let pool = [event("Labor Day", .apple, start: allDayInstant(2026, 9, 7), isAllDay: true),
                    event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)]
        let out = CalendarSync.collapsingDuplicates(pool, calendar: la)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].source, .google)          // writable copy wins
        XCTAssertEqual(out[0].duplicateSources, [.apple])
    }

    func test_allDayCopiesOnDifferentDates_doNotCollapse() {
        let pool = [event("Reading Day", .apple, start: allDayInstant(2026, 9, 7), isAllDay: true),
                    event("Reading Day", .google, start: allDayInstant(2026, 9, 8), isAllDay: true)]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(pool, calendar: la).count, 2)
    }

    func test_allDayFlagAndTimedEvent_neverCollapse() {
        // "Labor Day" the flag and a meeting named "Labor Day" are different things — even
        // though the flag spans the whole day, so the timed block sits entirely inside it and
        // clears the overlap threshold that decides duplicates for two *timed* events.
        let flag = event("Labor Day", .google, start: allDayInstant(2026, 9, 7),
                         minutes: 24 * 60, isAllDay: true)
        let meeting = event("Labor Day", .apple,
                            start: allDayInstant(2026, 9, 7).addingTimeInterval(9 * 3600),
                            minutes: 60)
        XCTAssertEqual(CalendarSync.collapsingDuplicates([flag, meeting], calendar: la).count, 2)
    }

    func test_timedEvents_keepTheSixtySecondTolerance() {
        let base = allDayInstant(2026, 9, 7).addingTimeInterval(9 * 3600)
        let close = [event("BIO 201 Lecture", .google, start: base, minutes: 60),
                     event("BIO 201 Lecture", .apple, start: base.addingTimeInterval(30), minutes: 60)]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(close, calendar: la).count, 1)

        // Two hours apart, no overlap — still two blocks.
        let apart = [event("BIO 201 Lecture", .google, start: base, minutes: 60),
                     event("BIO 201 Lecture", .apple, start: base.addingTimeInterval(7200), minutes: 60)]
        XCTAssertEqual(CalendarSync.collapsingDuplicates(apart, calendar: la).count, 2)
    }

    // MARK: - School Key Date flags

    /// A Key Date arrives as a `YYYY-MM-DD` string parsed at LOCAL midnight (`TermDay`) — that
    /// stays the School framework's internal convention. But the moment it is synthesized into a
    /// `CalendarEvent`, it is an all-day event like any other and must wear the canonical anchor,
    /// or "Labor Day" from the registrar can never dedupe with "Labor Day" from Google.
    ///
    /// Asserted in BOTH hemispheres deliberately: west of Greenwich local midnight happens to
    /// land on the right UTC date anyway, so Los Angeles alone would not catch the bug.
    private func assertKeyDateFlagIsCanonical(in calendar: Calendar,
                                              file: StaticString = #filePath,
                                              line: UInt = #line) {
        let sept7 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let term = Term(name: "Fall 2026",
                        startsOn: calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)),
                        endsOn: calendar.date(from: DateComponents(year: 2026, month: 12, day: 18)),
                        keyDates: [TermKeyDate(label: "Labor Day", date: sept7, kind: .holiday)])

        let flags = SchoolCalendar.keyDateFlagEvents(on: sept7, in: term,
                                                     spaceName: "School", calendar: calendar)
        XCTAssertEqual(flags.count, 1, file: file, line: line)
        XCTAssertTrue(flags[0].isAllDay, file: file, line: line)
        XCTAssertEqual(AllDayDate.utcDay(of: flags[0].start), allDayInstant(2026, 9, 7),
                       file: file, line: line)
        XCTAssertFalse(flags[0].hasSpecificTime, file: file, line: line)

        // ...and therefore it collapses with the Google copy of the same holiday.
        let google = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        let out = CalendarSync.collapsingDuplicates(flags + [google], calendar: calendar)
        XCTAssertEqual(out.count, 1, file: file, line: line)
        XCTAssertEqual(out[0].source, .atlas, file: file, line: line)   // synthesized copy wins
        XCTAssertEqual(out[0].duplicateSources, [.google], file: file, line: line)
    }

    func test_keyDateFlag_isCanonicallyAnchored_westOfGreenwich() {
        assertKeyDateFlagIsCanonical(in: la)
    }

    func test_keyDateFlag_isCanonicallyAnchored_eastOfGreenwich() {
        assertKeyDateFlagIsCanonical(in: Self.calendar("Asia/Tokyo"))
    }

    func test_keyDateFlag_stillRendersOnItsOwnDay() {
        // The anchor moved; the day it draws on must not.
        let tokyo = Self.calendar("Asia/Tokyo")
        let sept7 = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let term = Term(name: "Fall 2026",
                        startsOn: tokyo.date(from: DateComponents(year: 2026, month: 8, day: 24)),
                        endsOn: tokyo.date(from: DateComponents(year: 2026, month: 12, day: 18)),
                        keyDates: [TermKeyDate(label: "Labor Day", date: sept7, kind: .holiday)])
        let flag = SchoolCalendar.keyDateFlagEvents(on: sept7, in: term,
                                                    spaceName: "School", calendar: tokyo)[0]
        XCTAssertEqual(flag.bucketDate(in: tokyo), sept7)
    }

    // MARK: - Agenda bucketing

    func test_allDayEvent_bucketsOnItsOwnDate_inALosAngelesAgenda() {
        let labourDay = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        let sections = AgendaBuilder.build(events: [labourDay],
                                           tasks: [],
                                           from: la.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                                           calendar: la)
        let expected = la.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        XCTAssertEqual(sections.filter { $0.day == expected }.flatMap(\.items).map(\.title), ["Labor Day"])
        // And nothing landed on the 6th.
        XCTAssertTrue(sections.filter { $0.day < expected }.flatMap(\.items).isEmpty)
    }

    func test_allDayEventToday_isNotDroppedAsPast_inALosAngelesAgenda() {
        // The canonical instant for "today" is 5 PM *yesterday* locally, so a naive
        // `start >= startOfDay` past-filter silently eats today's holiday.
        let today = la.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let labourDay = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        let sections = AgendaBuilder.build(events: [labourDay], tasks: [], from: today, calendar: la)
        XCTAssertEqual(sections.flatMap(\.items).map(\.title), ["Labor Day"])
    }

    func test_allDayEvent_countsTowardItsOwnDay_inTheMetricsTile() {
        let sept7 = la.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10))!
        let labourDay = event("Labor Day", .google, start: allDayInstant(2026, 9, 7), isAllDay: true)
        let m = AtlasMetrics.compute(tasks: [], events: [labourDay], goals: [], spaces: [], notes: [],
                                     calendar: la, referenceDate: sept7)
        XCTAssertEqual(m.eventsToday, 1)

        // ...and not toward the day before.
        let sept6 = la.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 10))!
        let previous = AtlasMetrics.compute(tasks: [], events: [labourDay], goals: [], spaces: [], notes: [],
                                            calendar: la, referenceDate: sept6)
        XCTAssertEqual(previous.eventsToday, 0)
    }

    func test_timedEventKeepsItsInstant_andBucketsLocally() {
        // 9 AM UTC on Sept 7 is 2 AM Sept 7 in LA — a timed event travels with the reader.
        let start = allDayInstant(2026, 9, 7).addingTimeInterval(9 * 3600)
        let sections = AgendaBuilder.build(events: [event("Standup", .google, start: start, minutes: 30)],
                                           tasks: [],
                                           from: la.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                                           calendar: la)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].day, la.date(from: DateComponents(year: 2026, month: 9, day: 7))!)
        XCTAssertEqual(sections[0].items[0].date, start)   // instant preserved, not rounded
    }
}
