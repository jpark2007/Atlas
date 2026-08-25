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

    // MARK: - Commit shapes

    func testAnExtractedEventGetsADefaultHour() {
        let start = Date(timeIntervalSince1970: 1_789_430_400)
        XCTAssertEqual(SyllabusDraft.eventEnd(for: start).timeIntervalSince(start), 3600)
    }
}
