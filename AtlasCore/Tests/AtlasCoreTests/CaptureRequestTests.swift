import XCTest
@testable import AtlasCore

/// Spec §3: the phone sends its IANA timezone so the model can resolve "5:30"
/// and "next Friday" in the user's local time. Optional → old clients/deploys
/// keep working (synthesized Codable omits nil).
final class CaptureRequestTests: XCTestCase {

    func test_requestBody_includesTimezone() throws {
        let data = try AtlasAI.requestBody(text: "x", spaces: [],
                                           timezone: "America/Los_Angeles")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["timezone"] as? String, "America/Los_Angeles")
    }

    func test_requestBody_omitsNilTimezone() throws {
        let data = try AtlasAI.requestBody(text: "x", spaces: [])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["timezone"])
    }

    // The event schema gained optional `endISO` + `isAllDay`; decoding must read
    // them when present and tolerate their absence (missing keys → nil).
    func test_decodeResults_readsEndISOAndAllDay() throws {
        let json = Data("""
        [{"kind":"event","title":"Game","spaceName":"Personal",
          "startISO":"2026-07-05T00:00:00Z","endISO":"2026-07-05T02:00:00Z","isAllDay":true}]
        """.utf8)
        let results = try AtlasAI.decodeResults(from: json)
        XCTAssertEqual(results.first?.endISO, "2026-07-05T02:00:00Z")
        XCTAssertEqual(results.first?.isAllDay, true)
    }

    func test_decodeResults_toleratesMissingNewFields() throws {
        let json = Data("""
        [{"kind":"task","title":"Call","spaceName":"Personal"}]
        """.utf8)
        let results = try AtlasAI.decodeResults(from: json)
        XCTAssertNil(results.first?.endISO)
        XCTAssertNil(results.first?.isAllDay)
    }
}
