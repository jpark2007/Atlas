import XCTest
@testable import AtlasCore

/// The scan → review → commit mapping: what a response becomes as draft rows, and what
/// day those rows land on in the student's own zone.
final class SyllabusDraftTests: XCTestCase {

    private let ny = TimeZone(identifier: "America/New_York")!

    private func response(_ json: String) throws -> SyllabusScanResponse {
        try SyllabusScan.decode(from: Data(json.utf8))
    }

    // MARK: - Date parsing

    func testFullTimestampIsAbsolute() throws {
        let d = try XCTUnwrap(SyllabusDraft.date(from: "2026-09-15T23:59:00Z", timeZone: ny))
        XCTAssertEqual(d.timeIntervalSince1970, 1_789_516_740, accuracy: 1)  // 2026-09-15 23:59 UTC
    }

    func testFractionalSecondsParse() {
        XCTAssertNotNil(SyllabusDraft.date(from: "2026-09-15T23:59:00.250Z", timeZone: ny))
    }

    func testDateOnlyIsTheLocalDay() throws {
        // "Sept 15" is the 15th where the student is — midnight in their zone, which is
        // 04:00 UTC in New York, not 00:00 UTC.
        let d = try XCTUnwrap(SyllabusDraft.date(from: "2026-09-15", timeZone: ny))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ny
        XCTAssertEqual(cal.component(.day, from: d), 15)
        XCTAssertEqual(cal.component(.hour, from: d), 0)

        let utc = try XCTUnwrap(SyllabusDraft.date(from: "2026-09-15", timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertEqual(utc.timeIntervalSince(d), -4 * 3600, accuracy: 1)
    }

    func testZonelessWallClockIsTheLocalClock() throws {
        let d = try XCTUnwrap(SyllabusDraft.date(from: "2026-09-15T14:30:00", timeZone: ny))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ny
        XCTAssertEqual(cal.component(.hour, from: d), 14)
        XCTAssertEqual(cal.component(.minute, from: d), 30)
    }

    func testUnparseableAndEmptyDatesStayNil() {
        XCTAssertNil(SyllabusDraft.date(from: nil, timeZone: ny))
        XCTAssertNil(SyllabusDraft.date(from: "   ", timeZone: ny))
        XCTAssertNil(SyllabusDraft.date(from: "Week 3", timeZone: ny))
    }

    // MARK: - Item mapping

    func testTaskTakesTheDueDateAndEventTakesTheStart() throws {
        let scanned = try response("""
        {"classes":[{"items":[
          {"kind":"task","title":"Problem set 1","dueISO":"2026-09-15","startISO":null,"notes":"pp. 40-52"},
          {"kind":"event","title":"Midterm","dueISO":null,"startISO":"2026-10-08T13:00:00Z","notes":null}
        ]}]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        XCTAssertEqual(group.items.count, 2)

        XCTAssertEqual(group.items[0].kind, .task)
        XCTAssertEqual(group.items[0].notes, "pp. 40-52")
        XCTAssertEqual(group.items[0].date, SyllabusDraft.date(from: "2026-09-15", timeZone: ny))

        XCTAssertEqual(group.items[1].kind, .event)
        XCTAssertNil(group.items[1].notes)
        XCTAssertEqual(group.items[1].date, SyllabusDraft.date(from: "2026-10-08T13:00:00Z", timeZone: ny))
    }

    func testItemFallsBackToTheOtherDateField() throws {
        // The model sometimes fills only `startISO` on a task (and vice versa) — the row
        // must keep its date rather than arriving blank.
        let scanned = try response("""
        {"classes":[{"items":[
          {"kind":"task","title":"Essay","dueISO":null,"startISO":"2026-11-02"},
          {"kind":"event","title":"Lab","dueISO":"2026-11-03","startISO":null}
        ]}]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        XCTAssertEqual(group.items[0].date, SyllabusDraft.date(from: "2026-11-02", timeZone: ny))
        XCTAssertEqual(group.items[1].date, SyllabusDraft.date(from: "2026-11-03", timeZone: ny))
    }

    func testUnknownKindBecomesATaskAndBlankTitlesAreDropped() throws {
        let scanned = try response("""
        {"classes":[{"items":[
          {"kind":"quiz","title":"Quiz 2","dueISO":"2026-09-20"},
          {"kind":"task","title":"   ","dueISO":"2026-09-21"}
        ]}]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        XCTAssertEqual(group.items.count, 1)
        XCTAssertEqual(group.items[0].kind, .task)
        XCTAssertEqual(group.items[0].title, "Quiz 2")
    }

    func testUndatedItemsSurviveWithNoDate() throws {
        let scanned = try response("""
        {"classes":[{"items":[{"kind":"task","title":"Reading response","dueISO":"Week 3"}]}]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        XCTAssertEqual(group.items.count, 1)
        XCTAssertNil(group.items[0].date)
        XCTAssertTrue(group.items[0].include)
    }

    // MARK: - Group mapping

    func testEverythingIsAcceptedByDefaultAndPointedAtTheLaunchingClass() throws {
        let target = UUID()
        let scanned = try response("""
        {"classes":[{
          "code":" CS 201 ","name":"Data Structures",
          "meetingPattern":[{"weekdays":[2,4,6],"start":"10:00","end":"10:50","location":"Tech 204"}],
          "classInfo":{"grade_weights":["Exams 40%"],"policies":[],"office_hours":"Tu 2-4"},
          "items":[{"kind":"task","title":"PS1","dueISO":"2026-09-15"}]
        }]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: target, timeZone: ny).first)

        XCTAssertEqual(group.targetClassID, target)
        XCTAssertEqual(group.code, "CS 201")            // trimmed
        XCTAssertEqual(group.detectedLabel, "CS 201 · Data Structures")
        XCTAssertTrue(group.includeMeetingPattern)
        XCTAssertTrue(group.includeClassInfo)
        XCTAssertTrue(group.items.allSatisfy(\.include))
        XCTAssertEqual(group.includedItems.count, 1)
        XCTAssertTrue(group.writesAnything)
    }

    func testAbsentAndEmptyPiecesAreNotOfferedForAcceptance() throws {
        let scanned = try response("""
        {"classes":[{
          "name":"Seminar",
          "classInfo":{"grade_weights":[],"policies":[],"office_hours":""},
          "items":[]
        }]}
        """)
        let group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        XCTAssertNil(group.code)
        XCTAssertEqual(group.detectedLabel, "Seminar")
        XCTAssertTrue(group.meetingPattern.isEmpty)
        XCTAssertFalse(group.includeMeetingPattern)
        XCTAssertNil(group.classInfo)               // an empty card is not a card
        XCTAssertFalse(group.includeClassInfo)
        XCTAssertFalse(group.writesAnything)        // committing this would write nothing
    }

    func testMultipleClassesEachKeepTheirOwnContent() throws {
        let target = UUID()
        let scanned = try response("""
        {"classes":[
          {"code":"CS 201","items":[{"kind":"task","title":"PS1","dueISO":"2026-09-15"}]},
          {"code":"MATH 250","items":[{"kind":"event","title":"Exam","startISO":"2026-10-01T09:00:00Z"}]}
        ],"truncated":true}
        """)
        let groups = SyllabusDraft.groups(from: scanned, defaultTarget: target, timeZone: ny)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.code), ["CS 201", "MATH 250"])
        // Both default to the class the scan was launched from; retargeting is per group.
        XCTAssertEqual(groups.map(\.targetClassID), [target, target])
        XCTAssertTrue(scanned.truncated)
    }

    func testUncheckedAndBlankRowsAreExcludedFromTheCommitSet() throws {
        let scanned = try response("""
        {"classes":[{"items":[
          {"kind":"task","title":"Keep","dueISO":"2026-09-15"},
          {"kind":"task","title":"Drop","dueISO":"2026-09-16"}
        ]}]}
        """)
        var group = try XCTUnwrap(SyllabusDraft.groups(from: scanned, defaultTarget: nil, timeZone: ny).first)
        group.items[1].include = false
        XCTAssertEqual(group.includedItems.map(\.title), ["Keep"])

        // A row the user blanked out is nothing to commit either.
        group.items[0].title = "  "
        XCTAssertTrue(group.includedItems.isEmpty)
    }

    // MARK: - Section picking (§C1)

    /// The real Math 135 shape: one lecture everybody attends, three recitations of which
    /// the student is in exactly one.
    private func sectionedGroup() -> SyllabusDraftGroup {
        SyllabusDraftGroup(meetingPattern: [
            MeetingBlock(weekdays: [2, 4], start: "14:00", end: "15:20", location: "PH-115",
                         sectionLabel: "Sec. 37–39", kind: "lecture"),
            MeetingBlock(weekdays: [3], start: "14:00", end: "15:20", location: "SEC-217",
                         sectionLabel: "Section 37", kind: "recitation"),
            MeetingBlock(weekdays: [3], start: "15:50", end: "17:10", location: "SEC-217",
                         sectionLabel: "Section 38", kind: "recitation"),
            MeetingBlock(weekdays: [3], start: "17:40", end: "19:00", location: "SEC-217",
                         sectionLabel: "Section 39", kind: "recitation"),
        ])
    }

    func testSectionChoicesSkipTheSharedLecture() {
        XCTAssertEqual(sectionedGroup().sectionChoices,
                       ["Section 37", "Section 38", "Section 39"])
    }

    func testChoosingASectionKeepsItAndTheLecture() {
        var group = sectionedGroup()
        group.chooseSection("Section 38")
        XCTAssertEqual(group.meetingIncluded, [true, false, true, false])
        XCTAssertEqual(group.includedMeetings.map(\.sectionLabel), ["Sec. 37–39", "Section 38"])

        // Backing out keeps everything — nothing is dropped without being asked for.
        group.chooseSection(nil)
        XCTAssertEqual(group.includedMeetings.count, 4)
    }

    func testAnUnpickedMeetingRowDoesNotCount() {
        var group = sectionedGroup()
        group.meetingIncluded = [false, false, false, false]
        XCTAssertTrue(group.includedMeetings.isEmpty)
        XCTAssertFalse(group.writesAnything)
    }

    // MARK: - Review shaping

    func testMonthBucketsGroupByMonthAndPutUndatedLast() {
        func day(_ iso: String) -> Date { SyllabusDraft.date(from: iso, timeZone: ny)! }
        let items = [
            SyllabusDraftItem(kind: .task, title: "October one", date: day("2026-10-06")),
            SyllabusDraftItem(kind: .task, title: "September two", date: day("2026-09-10")),
            SyllabusDraftItem(kind: .task, title: "Week 3 reading", date: nil),
            SyllabusDraftItem(kind: .task, title: "September one", date: day("2026-09-03")),
        ]
        let buckets = SyllabusReview.monthBuckets(items)
        XCTAssertEqual(buckets.map(\.title).last, "No date yet")
        XCTAssertEqual(buckets.count, 3)
        // Within a month, indices come back in date order, pointing at the original rows.
        XCTAssertEqual(buckets[0].indices.map { items[$0].title }, ["September one", "September two"])
        XCTAssertEqual(buckets[1].indices.map { items[$0].title }, ["October one"])
        XCTAssertEqual(buckets[2].indices.map { items[$0].title }, ["Week 3 reading"])
    }

    func testWeightChipSplitsThePercentageOffTheLabel() {
        XCTAssertEqual(SyllabusReview.weightChip("Exams 40%").label, "Exams")
        XCTAssertEqual(SyllabusReview.weightChip("Exams 40%").percent, "40%")
        XCTAssertEqual(SyllabusReview.weightChip("Homework — 4 %").percent, "4%")
        // No percentage stated: the syllabus's own words survive whole.
        XCTAssertEqual(SyllabusReview.weightChip("Participation counts").label, "Participation counts")
        XCTAssertNil(SyllabusReview.weightChip("Participation counts").percent)
    }

    // MARK: - Commit shapes

    func testAnExtractedEventGetsADefaultHour() {
        let start = Date(timeIntervalSince1970: 1_789_430_400)
        XCTAssertEqual(SyllabusDraft.eventEnd(for: start).timeIntervalSince(start), 3600)
    }

    // MARK: - Date-only events commit as all-day (Drew 09-01: "12 AM · 1h")

    private var eastern: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func testABareDaySyllabusRowIsMarkedDateOnly() {
        XCTAssertTrue(SyllabusDraft.isDateOnly("2026-09-24"))
        XCTAssertFalse(SyllabusDraft.isDateOnly("2026-09-24T14:00:00Z"))
        XCTAssertFalse(SyllabusDraft.isDateOnly("2026-09-24T14:00"))
        XCTAssertFalse(SyllabusDraft.isDateOnly(nil))
    }

    func testTheServersDateOnlyFlagBeatsTheShapeOfTheISOString() throws {
        // The wire carries instants, so a date-only exam arrives as a full UTC timestamp;
        // only the server's own flag still says "the document named a day, not an hour".
        let scanned = SyllabusScanItem(kind: "event", title: "Midterm 1",
                                       dueISO: nil, startISO: "2026-10-09T04:00:00.000Z",
                                       notes: nil, dateOnly: true)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned,
                                                    timeZone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(item.isDateOnly)
        XCTAssertFalse(item.dateApproximate)
        XCTAssertTrue(try XCTUnwrap(SyllabusDraft.eventInterval(for: item, calendar: eastern)).isAllDay)
    }

    func testAWeekRangeRowArrivesFlaggedApproximate() throws {
        // A schedule document's "Sept 28-Oct 2 · DBQ Module 5 due" row: dated on the last
        // day of the range, and marked so the review list can say the date was inferred.
        let scanned = SyllabusScanItem(kind: "task", title: "DBQ Module 5",
                                       dueISO: "2026-10-03T03:59:00.000Z", startISO: nil,
                                       notes: "Week 5 · Sept 28-Oct 2",
                                       dateOnly: true, dateApproximate: true)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned,
                                                    timeZone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(item.dateApproximate)
        XCTAssertEqual(item.notes, "Week 5 · Sept 28-Oct 2")
    }

    func testAnOlderServerWithoutTheFlagsStillReadsTheISOString() throws {
        let scanned = SyllabusScanItem(kind: "event", title: "Quiz 3",
                                       dueISO: nil, startISO: "2026-09-24", notes: nil)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned))
        XCTAssertTrue(item.isDateOnly)
        XCTAssertFalse(item.dateApproximate)
    }

    func testAnEventWithNoStatedTimeCommitsAllDayOnItsOwnDay() throws {
        let scanned = SyllabusScanItem(kind: "event", title: "Quiz 3",
                                       dueISO: nil, startISO: "2026-09-24", notes: nil)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned,
                                                    timeZone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(item.isDateOnly)

        let when = try XCTUnwrap(SyllabusDraft.eventInterval(for: item, calendar: eastern))
        XCTAssertTrue(when.isAllDay)
        // Canonical all-day anchor: UTC midnight of Sep 24 — never local midnight, which
        // would dedupe against nothing and bucket a day early.
        XCTAssertEqual(when.start, AllDayDate.utc.date(from: DateComponents(year: 2026, month: 9, day: 24)))
        XCTAssertEqual(when.start, when.end)
        // And it still reads as Sep 24 in the student's own zone.
        XCTAssertEqual(eastern.dateComponents([.month, .day],
                                              from: AllDayDate.localDay(of: when.start, calendar: eastern)),
                       DateComponents(month: 9, day: 24))
    }

    func testABareDateTaskCommitsAllDayAndIsDueAtTheEndOfThatDay() throws {
        let scanned = SyllabusScanItem(kind: "task", title: "Problem Set 4",
                                       dueISO: "2026-09-24", startISO: nil, notes: nil)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned,
                                                    timeZone: TimeZone(identifier: "America/New_York")!))
        XCTAssertTrue(item.isDateOnly)

        let due = SyllabusDraft.taskDue(for: item, calendar: eastern)
        XCTAssertTrue(due.allDay)
        // Canonical all-day encoding — UTC midnight of Sep 24, same as Canvas writes.
        XCTAssertEqual(due.dueDate, AllDayDate.utc.date(from: DateComponents(year: 2026, month: 9, day: 24)))

        // And what the domain unpacks it to: due by the END of Sep 24 locally, so the
        // task doesn't go late the evening before.
        var task = TaskItem(title: item.title, dueLabel: "", dueDate: due.dueDate)
        task.allDay = due.allDay
        XCTAssertEqual(eastern.dateComponents([.month, .day, .hour],
                                              from: try XCTUnwrap(task.effectiveDueDate(calendar: eastern))),
                       DateComponents(month: 9, day: 24, hour: 23))
    }

    func testATaskThatStatedATimeStaysTimed() throws {
        let scanned = SyllabusScanItem(kind: "task", title: "Essay 1",
                                       dueISO: "2026-10-14T19:00:00Z", startISO: nil, notes: nil)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned))
        XCTAssertFalse(item.isDateOnly)

        let due = SyllabusDraft.taskDue(for: item, calendar: eastern)
        XCTAssertFalse(due.allDay)
        XCTAssertEqual(due.dueDate, item.date)
    }

    func testATaskWithNoDateCommitsUndatedAndTimed() {
        let item = SyllabusDraftItem(kind: .task, title: "Reading", date: nil, isDateOnly: true)
        let due = SyllabusDraft.taskDue(for: item, calendar: eastern)
        XCTAssertNil(due.dueDate)
        XCTAssertFalse(due.allDay)
    }

    func testAnEventThatStatedATimeKeepsIt() throws {
        let scanned = SyllabusScanItem(kind: "event", title: "Midterm",
                                       dueISO: nil, startISO: "2026-10-14T19:00:00Z", notes: nil)
        let item = try XCTUnwrap(SyllabusDraft.item(from: scanned))
        XCTAssertFalse(item.isDateOnly)

        let when = try XCTUnwrap(SyllabusDraft.eventInterval(for: item, calendar: eastern))
        XCTAssertFalse(when.isAllDay)
        XCTAssertEqual(when.start, item.date)
        XCTAssertEqual(when.end.timeIntervalSince(when.start), 3600)
    }

    /// The review sheet's date picker offers a clock time. Typing one in means the student
    /// knows when the exam is — the row stops being all-day.
    func testGivingADateOnlyRowAClockTimeMakesItTimed() throws {
        var item = SyllabusDraftItem(kind: .event, title: "Quiz 3",
                                     date: eastern.date(from: DateComponents(year: 2026, month: 9, day: 24)),
                                     isDateOnly: true)
        XCTAssertTrue(item.commitsAllDay(calendar: eastern))

        item.date = eastern.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14))
        XCTAssertFalse(item.commitsAllDay(calendar: eastern))
        let when = try XCTUnwrap(SyllabusDraft.eventInterval(for: item, calendar: eastern))
        XCTAssertFalse(when.isAllDay)
    }

    func testARowWithNoDateAtAllPlacesNoEvent() {
        let item = SyllabusDraftItem(kind: .event, title: "Final exam", date: nil)
        XCTAssertNil(SyllabusDraft.eventInterval(for: item, calendar: eastern))
    }

    // MARK: - Re-scanning a class that already has a card or a schedule

    private var savedInfo: ClassInfoCard {
        ClassInfoCard(gradeWeights: ["Exams 40%", "Homework 30%", "Final 30%"],
                      policies: ["No late work"],
                      officeHours: "Tu 2–4")
    }

    private var savedMeetings: [MeetingBlock] {
        [MeetingBlock(weekdays: [2, 5], start: "08:30", end: "09:50")]
    }

    func testSummariesNameWhatWouldBeReplaced() {
        XCTAssertEqual(SyllabusRescan.classInfoSummary(savedInfo), "3 weights, 1 policy, office hours")
        XCTAssertEqual(SyllabusRescan.meetingSummary(savedMeetings), "MTh · 8:30 AM–9:50 AM")
    }

    /// Nothing saved ⇒ nothing to warn about; the sheet keeps its current behavior.
    func testAnEmptyCardIsNothingToReplace() {
        XCTAssertNil(SyllabusRescan.classInfoSummary(nil))
        XCTAssertNil(SyllabusRescan.classInfoSummary(ClassInfoCard()))
        XCTAssertNil(SyllabusRescan.meetingSummary([]))
    }

    func testARescanStartsAtKeepExistingForEverySectionTheClassAlreadyHas() {
        let group = SyllabusDraftGroup(meetingPattern: savedMeetings,
                                       classInfo: ClassInfoCard(gradeWeights: ["Exams 50%"]))
        let kept = SyllabusRescan.keepingExisting(group, info: savedInfo, meetings: savedMeetings)
        XCTAssertFalse(kept.includeClassInfo)
        XCTAssertFalse(kept.includeMeetingPattern)
    }

    /// A first scan writes as it always did — the choice only exists where there's a clash.
    func testAFirstScanStillCommitsBothSections() {
        let group = SyllabusDraftGroup(meetingPattern: savedMeetings,
                                       classInfo: ClassInfoCard(gradeWeights: ["Exams 50%"]))
        let kept = SyllabusRescan.keepingExisting(group, info: nil, meetings: [])
        XCTAssertTrue(kept.includeClassInfo)
        XCTAssertTrue(kept.includeMeetingPattern)
    }

    /// One section clashing must not turn the other one off.
    func testOnlyTheClashingSectionIsHeldBack() {
        let group = SyllabusDraftGroup(meetingPattern: savedMeetings,
                                       classInfo: ClassInfoCard(gradeWeights: ["Exams 50%"]))
        let kept = SyllabusRescan.keepingExisting(group, info: savedInfo, meetings: [])
        XCTAssertFalse(kept.includeClassInfo)
        XCTAssertTrue(kept.includeMeetingPattern)
    }

    /// Retargeting from a class that already has a pattern (flag held back) onto one with
    /// nothing saved must re-enable the write — otherwise the pattern the scan found is
    /// silently dropped on commit, with no control left in the sheet to turn it back on.
    func testRetargetingFromHasPatternToNoPatternReEnablesTheFlag() {
        let group = SyllabusDraftGroup(meetingPattern: savedMeetings,
                                       classInfo: ClassInfoCard(gradeWeights: ["Exams 50%"]))
        let heldBack = SyllabusRescan.keepingExisting(group, info: savedInfo, meetings: savedMeetings)
        XCTAssertFalse(heldBack.includeMeetingPattern)
        XCTAssertFalse(heldBack.includeClassInfo)

        let retargeted = SyllabusRescan.keepingExisting(heldBack, info: nil, meetings: [])
        XCTAssertTrue(retargeted.includeMeetingPattern)
        XCTAssertTrue(retargeted.includeClassInfo)
    }

    /// Retargeting the other way — onto a class that already has its own pattern — must
    /// hold the flag back even if it started on "commit" for the previous, empty target.
    func testRetargetingFromNoPatternToHasPatternDisablesTheFlag() {
        let group = SyllabusDraftGroup(meetingPattern: savedMeetings,
                                       classInfo: ClassInfoCard(gradeWeights: ["Exams 50%"]))
        let committing = SyllabusRescan.keepingExisting(group, info: nil, meetings: [])
        XCTAssertTrue(committing.includeMeetingPattern)
        XCTAssertTrue(committing.includeClassInfo)

        let retargeted = SyllabusRescan.keepingExisting(committing, info: savedInfo, meetings: savedMeetings)
        XCTAssertFalse(retargeted.includeMeetingPattern)
        XCTAssertFalse(retargeted.includeClassInfo)
    }
}
