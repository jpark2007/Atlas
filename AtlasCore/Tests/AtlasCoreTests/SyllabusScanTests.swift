import XCTest
@testable import AtlasCore

/// Pure seams of the syllabus scan client: what goes on the wire, what comes back
/// (including sparse payloads a partial extraction produces), and the local caps
/// that stop an oversized upload before it's sent.
final class SyllabusScanTests: XCTestCase {

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Request encoding

    func testRequestBodyCarriesImagesTermWindowAndZone() throws {
        let image = SyllabusScanImage(bytes: Data([0xDE, 0xAD, 0xBE, 0xEF]), mediaType: "image/png")
        let body = try SyllabusScan.requestBody(images: [image],
                                                termStart: "2026-08-24",
                                                termEnd: "2026-12-12",
                                                timezone: "America/New_York")
        let obj = try json(body)
        XCTAssertEqual(obj["termStart"] as? String, "2026-08-24")
        XCTAssertEqual(obj["termEnd"] as? String, "2026-12-12")
        XCTAssertEqual(obj["timezone"] as? String, "America/New_York")

        let images = try XCTUnwrap(obj["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["mediaType"] as? String, "image/png")
        XCTAssertEqual(images[0]["data"] as? String, Data([0xDE, 0xAD, 0xBE, 0xEF]).base64EncodedString())
    }

    func testRequestBodyOmitsAbsentTermWindow() throws {
        let body = try SyllabusScan.requestBody(
            images: [SyllabusScanImage(base64: "AAAA", mediaType: "image/jpeg")],
            termStart: nil, termEnd: nil, timezone: "UTC")
        let obj = try json(body)
        XCTAssertNil(obj["termStart"])
        XCTAssertNil(obj["termEnd"])
        XCTAssertEqual(obj["timezone"] as? String, "UTC")
    }

    func testDayStringUsesTheGivenZone() {
        // 2026-08-25 01:30 UTC is still the 24th in New York.
        let date = Date(timeIntervalSince1970: 1_787_621_400)
        XCTAssertEqual(SyllabusScan.dayString(date, timeZone: TimeZone(identifier: "UTC")!), "2026-08-25")
        XCTAssertEqual(SyllabusScan.dayString(date, timeZone: TimeZone(identifier: "America/New_York")!),
                       "2026-08-24")
    }

    // MARK: - Size caps

    func testByteCountMatchesTheOriginalBytes() {
        for length in [1, 2, 3, 1000] {
            let bytes = Data(repeating: 0x41, count: length)
            XCTAssertEqual(SyllabusScanImage(bytes: bytes, mediaType: "image/png").byteCount, length)
        }
    }

    func testValidateAcceptsANormalScan() throws {
        let pages = (0..<3).map { _ in
            SyllabusScanImage(bytes: Data(repeating: 0x01, count: 200_000), mediaType: "image/png")
        }
        XCTAssertEqual(SyllabusScan.totalBytes(pages), 600_000)
        XCTAssertNoThrow(try SyllabusScan.validate(pages))
    }

    func testValidateRejectsEmptyTooManyAndTooLarge() {
        XCTAssertThrowsError(try SyllabusScan.validate([])) { error in
            XCTAssertEqual(error as? AtlasAIError, .noImages)
        }

        let tiny = SyllabusScanImage(base64: "AAAA", mediaType: "image/png")
        XCTAssertNoThrow(try SyllabusScan.validate(Array(repeating: tiny, count: SyllabusScan.maxImages)))
        XCTAssertThrowsError(
            try SyllabusScan.validate(Array(repeating: tiny, count: SyllabusScan.maxImages + 1))
        ) { error in
            XCTAssertEqual(error as? AtlasAIError, .imagesTooLarge)
        }

        let huge = SyllabusScanImage(bytes: Data(repeating: 0x02, count: SyllabusScan.maxTotalBytes + 1),
                                     mediaType: "image/jpeg")
        XCTAssertThrowsError(try SyllabusScan.validate([huge])) { error in
            XCTAssertEqual(error as? AtlasAIError, .imagesTooLarge)
        }
    }

    // MARK: - Response decoding

    func testDecodesAFullClass() throws {
        let payload = """
        {"classes":[{
          "code":"BIO 201","name":"Cell Biology",
          "meetingPattern":[{"weekdays":[2,4,6],"start":"10:00","end":"10:50","location":"Tech 204"}],
          "classInfo":{"grade_weights":["Exams 40%"],"policies":["No late work"],"office_hours":"Tue 2-4pm"},
          "items":[
            {"kind":"task","title":"Essay 1","dueISO":"2026-09-12T04:00:00Z","notes":"5 pages"},
            {"kind":"event","title":"Midterm","startISO":"2026-10-01T14:00:00Z"}
          ]
        }]}
        """
        let result = try SyllabusScan.decode(from: Data(payload.utf8))
        XCTAssertFalse(result.truncated)
        let cls = try XCTUnwrap(result.classes.first)
        XCTAssertEqual(cls.code, "BIO 201")
        XCTAssertEqual(cls.name, "Cell Biology")
        XCTAssertEqual(cls.meetingPattern,
                       [MeetingBlock(weekdays: [2, 4, 6], start: "10:00", end: "10:50", location: "Tech 204")])
        XCTAssertEqual(cls.classInfo, ClassInfoCard(gradeWeights: ["Exams 40%"],
                                                    policies: ["No late work"],
                                                    officeHours: "Tue 2-4pm"))
        XCTAssertEqual(cls.items.count, 2)
        XCTAssertEqual(cls.items[0].kind, "task")
        XCTAssertEqual(cls.items[0].dueISO, "2026-09-12T04:00:00Z")
        XCTAssertNil(cls.items[0].startISO)
        XCTAssertEqual(cls.items[1].title, "Midterm")
        XCTAssertEqual(cls.items[1].startISO, "2026-10-01T14:00:00Z")
        XCTAssertNil(cls.items[1].notes)
    }

    func testDecodesSparseClassAndUndatedItem() throws {
        let payload = """
        {"classes":[{"name":"Art History","items":[{"kind":"task","title":"Reading, week 3"}]},
                    {"code":"CS 1"}]}
        """
        let result = try SyllabusScan.decode(from: Data(payload.utf8))
        XCTAssertEqual(result.classes.count, 2)

        let art = result.classes[0]
        XCTAssertNil(art.code)
        XCTAssertNil(art.meetingPattern)
        XCTAssertNil(art.classInfo)
        XCTAssertEqual(art.items.count, 1)
        XCTAssertNil(art.items[0].dueISO, "an ungroundable date is omitted, the item is kept")

        // A class with no `items` key at all still decodes, with an empty list.
        XCTAssertEqual(result.classes[1].items, [])
    }

    func testDecodesEmptyAndTruncatedPayloads() throws {
        XCTAssertEqual(try SyllabusScan.decode(from: Data("{}".utf8)).classes, [])
        XCTAssertFalse(try SyllabusScan.decode(from: Data(#"{"classes":[]}"#.utf8)).truncated)
        XCTAssertTrue(try SyllabusScan.decode(from: Data(#"{"classes":[],"truncated":true}"#.utf8)).truncated)
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try SyllabusScan.decode(from: Data("not json".utf8)))
    }

    // MARK: - Status mapping

    func testServerCapsMapToTypedErrors() {
        XCTAssertEqual(AtlasAIError.from(status: 413), .tooLong)
        XCTAssertEqual(AtlasAIError.from(status: 429), .rateLimited)
        XCTAssertEqual(AtlasAIError.from(status: 502), .serverUnavailable)
    }
}
