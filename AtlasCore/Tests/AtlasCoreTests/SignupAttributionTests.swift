import XCTest
@testable import AtlasCore

/// The signup-attribution step's two moving parts: the raw strings that land in
/// `profiles.referral_source` (the admin dashboard groups on them, so they are a
/// contract) and the school type-ahead's ordering.
final class SignupAttributionTests: XCTestCase {

    // MARK: ReferralSource

    func testRawValuesAreTheStoredContract() {
        XCTAssertEqual(ReferralSource.friend.rawValue, "friend")
        XCTAssertEqual(ReferralSource.tiktok.rawValue, "tiktok")
        XCTAssertEqual(ReferralSource.instagram.rawValue, "instagram")
        XCTAssertEqual(ReferralSource.reddit.rawValue, "reddit")
        XCTAssertEqual(ReferralSource.googleSearch.rawValue, "google_search")
        XCTAssertEqual(ReferralSource.professor.rawValue, "professor")
        XCTAssertEqual(ReferralSource.other.rawValue, "other")
        XCTAssertEqual(ReferralSource.skipped.rawValue, "skipped")
    }

    func testRoundTripsThroughItsRawValue() {
        for source in ReferralSource.allCases {
            XCTAssertEqual(ReferralSource(rawValue: source.rawValue), source)
        }
        XCTAssertNil(ReferralSource(rawValue: "myspace"))
    }

    func testChipsAreEveryCaseButSkipped() {
        XCTAssertEqual(Set(ReferralSource.choices) , Set(ReferralSource.allCases).subtracting([.skipped]))
        XCTAssertEqual(ReferralSource.choices.first, .friend)
        XCTAssertEqual(ReferralSource.choices.last, .other)
    }

    // MARK: School search

    private let sample = [
        School(name: "Boston College", domain: "bc.edu"),
        School(name: "Boston University", domain: "bu.edu"),
        School(name: "College of Boston", domain: "cob.edu"),
        School(name: "Northeastern University", domain: "northeastern.edu"),
    ]

    func testPrefixMatchesRankAboveMidStringOnes() {
        let hits = USSchools.search("boston", in: sample)
        XCTAssertEqual(hits.map(\.name),
                       ["Boston College", "Boston University", "College of Boston"])
    }

    func testSearchIsCaseInsensitiveAndTrimsQuery() {
        XCTAssertEqual(USSchools.search("  NoRtHeAsT ", in: sample).map(\.name),
                       ["Northeastern University"])
    }

    func testEmptyQueryReturnsTheHeadOfTheList() {
        XCTAssertEqual(USSchools.search("", in: sample, limit: 2).map(\.name),
                       ["Boston College", "Boston University"])
    }

    func testLimitCapsResults() {
        XCTAssertEqual(USSchools.search("boston", in: sample, limit: 1).count, 1)
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(USSchools.search("zzz", in: sample).isEmpty)
    }

    // MARK: The bundled dataset

    func testBundledUSListLoadsAndIsSearchable() {
        XCTAssertGreaterThan(USSchools.all.count, 2000)
        let hits = USSchools.search("Northeastern Univ")
        XCTAssertTrue(hits.contains { $0.name == "Northeastern University" })
    }
}
