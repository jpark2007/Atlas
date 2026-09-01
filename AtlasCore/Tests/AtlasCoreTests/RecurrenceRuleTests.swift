import XCTest
@testable import AtlasCore

/// Recurrence expansion — the semester-class cases the capture bar has to get right,
/// plus the ways an LLM can hand us a rule that must NOT produce a corrupt series.
final class RecurrenceRuleTests: XCTestCase {

    /// A fixed Gregorian calendar in a US zone, so weekday math and the November
    /// DST fallback are deterministic regardless of where the test runs.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let mon = 2, tue = 3, wed = 4, thu = 5, fri = 6

    // MARK: - The core case

    /// "MWF 10-10:50am, Sept 2 to Dec 12" — 2026-09-02 is a WEDNESDAY.
    func testSemesterMWFCoversWholeTermAtStatedTime() {
        let rule = RecurrenceRule(frequency: .weekly,
                                  weekdays: [mon, wed, fri],
                                  until: date(2026, 12, 12))
        let starts = rule.occurrences(startingAt: date(2026, 9, 2, 10, 0), calendar: cal)

        XCTAssertEqual(starts.first, date(2026, 9, 2, 10, 0))
        // Dec 12 2026 is a Saturday, so the last session is Friday Dec 11.
        XCTAssertEqual(starts.last, date(2026, 12, 11, 10, 0))
        // Every session is a Mon/Wed/Fri at 10:00 local.
        for start in starts {
            XCTAssertTrue([mon, wed, fri].contains(cal.component(.weekday, from: start)))
            XCTAssertEqual(cal.component(.hour, from: start), 10)
            XCTAssertEqual(cal.component(.minute, from: start), 0)
        }
        XCTAssertEqual(starts.count, 44)
    }

    /// The weekday set governs which days are sessions — a term that OPENS on a
    /// Tuesday must not manufacture a Tuesday lecture for an MWF class.
    func testStartDateThatIsNotAListedWeekdayIsNotAnOccurrence() {
        let sept1 = date(2026, 9, 1, 10, 0)          // a Tuesday
        XCTAssertEqual(cal.component(.weekday, from: sept1), tue)

        let rule = RecurrenceRule(frequency: .weekly,
                                  weekdays: [mon, wed, fri],
                                  until: date(2026, 9, 30))
        let starts = rule.occurrences(startingAt: sept1, calendar: cal)

        XCTAssertEqual(starts.first, date(2026, 9, 2, 10, 0))   // first class is Wednesday
        XCTAssertFalse(starts.contains(sept1))
    }

    /// `until` is INCLUSIVE — a session falling on the last day is kept.
    func testUntilIncludesItsOwnDay() {
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [fri], until: date(2026, 12, 11))
        let starts = rule.occurrences(startingAt: date(2026, 12, 4, 9, 0), calendar: cal)
        XCTAssertEqual(starts, [date(2026, 12, 4, 9, 0), date(2026, 12, 11, 9, 0)])
    }

    // MARK: - DST

    /// A US fall term crosses the November fallback. A 10 AM class must stay 10 AM —
    /// adding a fixed 7-day interval instead of re-applying wall-clock would slide it.
    func testWallClockTimeSurvivesDSTFallback() {
        // DST ends 2026-11-01 in America/Los_Angeles.
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [mon], until: date(2026, 11, 16))
        let starts = rule.occurrences(startingAt: date(2026, 10, 26, 10, 0), calendar: cal)

        XCTAssertEqual(starts.count, 4)
        for start in starts {
            XCTAssertEqual(cal.component(.hour, from: start), 10, "10 AM slid on \(start)")
        }
        // And the instants really do straddle the transition (offsets differ).
        XCTAssertNotEqual(cal.timeZone.secondsFromGMT(for: starts[0]),
                          cal.timeZone.secondsFromGMT(for: starts[3]))
    }

    // MARK: - Other frequencies + bounds

    func testEmptyWeekdaysUsesTheStartsOwnWeekday() {
        let rule = RecurrenceRule(frequency: .weekly, count: 3)
        let starts = rule.occurrences(startingAt: date(2026, 9, 1, 14, 30), calendar: cal)
        XCTAssertEqual(starts, [date(2026, 9, 1, 14, 30),
                                date(2026, 9, 8, 14, 30),
                                date(2026, 9, 15, 14, 30)])
    }

    func testBiweeklySkipsTheOffWeek() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [thu], count: 3)
        let starts = rule.occurrences(startingAt: date(2026, 9, 3, 16, 0), calendar: cal)
        XCTAssertEqual(starts, [date(2026, 9, 3, 16, 0),
                                date(2026, 9, 17, 16, 0),
                                date(2026, 10, 1, 16, 0)])
    }

    func testDailyRespectsIntervalAndCount() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3, count: 3)
        let starts = rule.occurrences(startingAt: date(2026, 9, 1, 8, 0), calendar: cal)
        XCTAssertEqual(starts, [date(2026, 9, 1, 8, 0),
                                date(2026, 9, 4, 8, 0),
                                date(2026, 9, 7, 8, 0)])
    }

    /// A month with no 31st is skipped, never clamped — a clamp would invent a
    /// session on a date the user never chose.
    func testMonthlySkipsShortMonthsRatherThanClamping() {
        let rule = RecurrenceRule(frequency: .monthly, until: date(2027, 3, 31))
        let starts = rule.occurrences(startingAt: date(2026, 12, 31, 9, 0), calendar: cal)
        let months = starts.map { cal.component(.month, from: $0) }
        XCTAssertEqual(months, [12, 1, 3])   // no February 31st
    }

    /// An unbounded rule stops at the horizon rather than running forever.
    func testUnboundedRuleStopsAtTheDefaultHorizon() {
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [mon])
        // Jan 5 2026 is a Monday and the horizon runs 365 days, through Jan 4 2027
        // — itself a Monday — so the year holds 53 of them.
        let starts = rule.occurrences(startingAt: date(2026, 1, 5, 9, 0), calendar: cal)
        XCTAssertEqual(starts.count, 53)
        XCTAssertEqual(starts.last, date(2027, 1, 4, 9, 0))
        XCTAssertLessThanOrEqual(starts.count, RecurrenceRule.maxOccurrences)
    }

    /// A daily rule with no end would be 365 rows — still under the hard backstop.
    func testDailyUnboundedStaysUnderTheBackstop() {
        let rule = RecurrenceRule(frequency: .daily)
        let starts = rule.occurrences(startingAt: date(2026, 1, 1, 9, 0), calendar: cal)
        XCTAssertLessThanOrEqual(starts.count, RecurrenceRule.maxOccurrences)
    }

    /// A rule whose window excludes everything still yields the original event —
    /// capture must never silently drop what the user typed.
    func testImpossibleWindowStillYieldsTheStart() {
        let start = date(2026, 9, 2, 10, 0)
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [mon], until: date(2026, 8, 1))
        XCTAssertEqual(rule.occurrences(startingAt: start, calendar: cal), [start])
    }

    // MARK: - RRULE text round-trip

    func testRRULERoundTrip() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2,
                                  weekdays: [mon, wed, fri], until: date(2026, 12, 12))
        XCTAssertEqual(rule.rruleText, "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20261212")

        let parsed = RecurrenceRule(rruleText: rule.rruleText)
        XCTAssertEqual(parsed?.frequency, .weekly)
        XCTAssertEqual(parsed?.interval, 2)
        XCTAssertEqual(parsed?.weekdays, [mon, wed, fri])
        XCTAssertEqual(parsed?.count, nil)
    }

    /// A stored string we can't read degrades to "no repeat" instead of throwing.
    func testUnparseableRRULEIsNil() {
        XCTAssertNil(RecurrenceRule(rruleText: "FREQ=HOURLY;INTERVAL=1"))
        XCTAssertNil(RecurrenceRule(rruleText: "garbage"))
        XCTAssertNil(RecurrenceRule(rruleText: ""))
    }

    // MARK: - Mapping the model's loose output

    func testCaptureMappingReadsWeekdayCodes() {
        let spec = CaptureRecurrence(freq: "weekly", byDay: ["MO", "we", " FR "],
                                     untilISO: "2026-12-12")
        let rule = RecurrenceRule(capture: spec)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.weekdays, [mon, wed, fri])
        XCTAssertNotNil(rule?.until)
    }

    /// Everything the model can garble is normalized or dropped here, so a confused
    /// parse degrades to one event rather than a corrupt series.
    func testCaptureMappingRejectsAndNormalizesBadInput() {
        XCTAssertNil(RecurrenceRule(capture: CaptureRecurrence(freq: "fortnightly")))
        XCTAssertNil(RecurrenceRule(capture: CaptureRecurrence(freq: "")))

        let junk = CaptureRecurrence(freq: "WEEKLY", interval: -4,
                                     byDay: ["MO", "XX", "🙂"], untilISO: "not-a-date")
        let rule = RecurrenceRule(capture: junk)
        XCTAssertEqual(rule?.interval, 1)          // clamped, never negative
        XCTAssertEqual(rule?.weekdays, [mon])      // junk codes dropped
        XCTAssertNil(rule?.until)                  // unparseable bound ignored
    }

    // MARK: - Display

    func testSummaryReadsAsEnglish() {
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [mon, wed, fri],
                                      until: date(2026, 12, 12)).summary,
                       "Every Mon, Wed & Fri until Dec 12")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: Set(2...6)).summary,
                       "Every weekday")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [tue]).summary,
                       "Every 2 weeks on Tue")
        XCTAssertEqual(RecurrenceRule(frequency: .daily, count: 5).summary,
                       "Every day, 5 times")
    }
}
