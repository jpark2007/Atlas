import XCTest
@testable import AtlasCore

/// School framework, stage A: term selection + the jsonb shapes classes carry.
final class TermTests: XCTestCase {

    private func day(_ s: String) -> Date { TermDay.date(from: s)! }

    private func term(_ name: String, _ start: String?, _ end: String?) -> Term {
        Term(name: name,
             startsOn: start.map(day),
             endsOn: end.map(day))
    }

    // MARK: - TermSelection

    func testNoTermsHasNoActiveTerm() {
        XCTAssertNil(TermSelection.active(in: [], on: day("2026-09-01")))
    }

    func testTermContainingTodayWins() {
        let fall   = term("Fall 2026",   "2026-08-24", "2026-12-15")
        let spring = term("Spring 2027", "2027-01-12", "2027-05-05")
        let active = TermSelection.active(in: [spring, fall], on: day("2026-09-01"))
        XCTAssertEqual(active?.name, "Fall 2026")
    }

    func testBoundaryDaysCountAsInsideTheTerm() {
        let fall = term("Fall 2026", "2026-08-24", "2026-12-15")
        XCTAssertTrue(fall.contains(day("2026-08-24")))
        XCTAssertTrue(fall.contains(day("2026-12-15")))
        XCTAssertFalse(fall.contains(day("2026-12-16")))
    }

    func testBetweenTermsFallsBackToMostRecentBegun() {
        let spring = term("Spring 2026", "2026-01-12", "2026-05-05")
        let fall   = term("Fall 2026",   "2026-08-24", "2026-12-15")
        // Summer: nothing contains today; the most recently ended term shows.
        let active = TermSelection.active(in: [spring, fall], on: day("2026-06-20"))
        XCTAssertEqual(active?.name, "Spring 2026")
    }

    func testOnlyUpcomingTermsPicksTheSoonest() {
        let fall   = term("Fall 2026",   "2026-08-24", "2026-12-15")
        let spring = term("Spring 2027", "2027-01-12", "2027-05-05")
        let active = TermSelection.active(in: [spring, fall], on: day("2026-07-01"))
        XCTAssertEqual(active?.name, "Fall 2026")
    }

    func testUndatedTermIsNeverTreatedAsCurrentButStillSurfacesAlone() {
        let undated = term("My semester", nil, nil)
        let fall    = term("Fall 2026", "2026-08-24", "2026-12-15")
        // A dated, current term always beats an undated one…
        XCTAssertEqual(TermSelection.active(in: [undated, fall], on: day("2026-09-01"))?.name,
                       "Fall 2026")
        // …but an undated term is better than showing nothing.
        XCTAssertEqual(TermSelection.active(in: [undated], on: day("2026-09-01"))?.name,
                       "My semester")
    }

    // MARK: - jsonb coding

    func testMeetingBlockRoundTripsThroughJSON() throws {
        let block = MeetingBlock(weekdays: [2, 4, 6], start: "10:00", end: "10:50",
                                 location: "Tech Hall 204")
        let data = try JSONEncoder().encode([block])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.first?["start"] as? String, "10:00")
        XCTAssertEqual(json.first?["weekdays"] as? [Int], [2, 4, 6])
        XCTAssertEqual(try JSONDecoder().decode([MeetingBlock].self, from: data), [block])
    }

    /// The dated window round-trips, and a block that has none writes no keys at all —
    /// so a class created before this shape existed reads back identical to what it was.
    func testMeetingBlockRoundTripsItsDatesAndOmitsThemWhenAbsent() throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601

        let dated = MeetingBlock(weekdays: [2], start: "10:00", end: "10:50",
                                 firstDate: day("2026-09-01"), lastDate: day("2026-12-11"))
        XCTAssertEqual(try d.decode([MeetingBlock].self, from: e.encode([dated])), [dated])

        let undatedJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try e.encode([MeetingBlock(weekdays: [2], start: "10:00", end: "10:50")])
        ) as? [[String: Any]])
        XCTAssertNil(undatedJSON.first?["firstDate"])
        XCTAssertNil(undatedJSON.first?["lastDate"])
    }

    /// Backward compatibility: a stored block from before the dated window decodes with
    /// neither date — term-bounded, exactly as it always drew. No migration.
    func testMeetingBlockDecodesWithoutDates() throws {
        let json = #"[{"weekdays":[2,4,6],"start":"10:00","end":"10:50"}]"#.data(using: .utf8)!
        let blocks = try JSONDecoder().decode([MeetingBlock].self, from: json)
        XCTAssertNil(blocks.first?.firstDate)
        XCTAssertNil(blocks.first?.lastDate)
    }

    func testMeetingBlockDecodesWithoutLocation() throws {
        let json = #"[{"weekdays":[3],"start":"14:00","end":"15:15"}]"#.data(using: .utf8)!
        let blocks = try JSONDecoder().decode([MeetingBlock].self, from: json)
        XCTAssertEqual(blocks.first?.weekdays, [3])
        XCTAssertNil(blocks.first?.location)
    }

    /// Forward-compat: a block written by a later client (e.g. rotation timetables)
    /// carries keys this one doesn't know, and must still decode.
    func testMeetingBlockIgnoresUnknownKeys() throws {
        let json = #"[{"weekdays":[2],"start":"09:00","end":"09:50","rotation_day":"A"}]"#
            .data(using: .utf8)!
        let blocks = try JSONDecoder().decode([MeetingBlock].self, from: json)
        XCTAssertEqual(blocks.first?.start, "09:00")
    }

    func testKeyDateEncodesDayPrecisionAndRoundTrips() throws {
        let kd = TermKeyDate(label: "Add/drop deadline", date: day("2026-09-04"), kind: .addDrop)
        let data = try JSONEncoder().encode([kd])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.first?["date"] as? String, "2026-09-04")
        XCTAssertEqual(json.first?["kind"] as? String, "add_drop")
        XCTAssertEqual(try JSONDecoder().decode([TermKeyDate].self, from: data), [kd])
    }

    func testUnknownKeyDateKindDecodesAsOther() throws {
        let json = #"[{"label":"Convocation","date":"2026-08-23","kind":"pep_rally"}]"#
            .data(using: .utf8)!
        let dates = try JSONDecoder().decode([TermKeyDate].self, from: json)
        XCTAssertEqual(dates.first?.kind, .other)
    }

    func testClassInfoCardUsesSnakeCaseKeysAndToleratesMissingLists() throws {
        let card = ClassInfoCard(gradeWeights: ["Exams 50%"], policies: ["No late work"],
                                 officeHours: "T 2–4, Kemper 3021")
        let data = try JSONEncoder().encode(card)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["grade_weights"] as? [String], ["Exams 50%"])
        XCTAssertEqual(json["office_hours"] as? String, "T 2–4, Kemper 3021")
        XCTAssertEqual(try JSONDecoder().decode(ClassInfoCard.self, from: data), card)

        let sparse = try JSONDecoder().decode(
            ClassInfoCard.self, from: #"{"policies":["Attendance counts"]}"#.data(using: .utf8)!)
        XCTAssertEqual(sparse.gradeWeights, [])
        XCTAssertNil(sparse.officeHours)
    }
}
