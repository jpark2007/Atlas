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
}
