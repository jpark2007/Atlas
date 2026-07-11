import XCTest
@testable import AtlasCore

/// The shared client-side shape check for a Canvas Calendar Feed URL
/// (`CanvasService.isValidFeedURL`). Both Mac and iOS gate the paste field with
/// this before bothering the server: https scheme, a host, and either a `.ics`
/// suffix or a `/feeds/calendars` path.
final class CanvasFeedURLTests: XCTestCase {

    func test_validFeedURLs() {
        XCTAssertTrue(CanvasService.isValidFeedURL(
            "https://school.instructure.com/feeds/calendars/user_abc123.ics"))
        // No .ics suffix but the Canvas feed path — still valid.
        XCTAssertTrue(CanvasService.isValidFeedURL(
            "https://canvas.university.edu/feeds/calendars/user_xyz"))
        // Any https .ics link passes the shape check.
        XCTAssertTrue(CanvasService.isValidFeedURL(
            "https://example.com/exports/mine.ICS"))
    }

    func test_rejectsNonHTTPSScheme() {
        XCTAssertFalse(CanvasService.isValidFeedURL(
            "http://school.instructure.com/feeds/calendars/user.ics"))
        XCTAssertFalse(CanvasService.isValidFeedURL(
            "webcal://school.instructure.com/feeds/calendars/user.ics"))
    }

    func test_rejectsMissingHost() {
        XCTAssertFalse(CanvasService.isValidFeedURL("https:///feeds/calendars/user.ics"))
    }

    func test_rejectsWrongPath() {
        // https + host, but neither .ics nor /feeds/calendars.
        XCTAssertFalse(CanvasService.isValidFeedURL("https://school.instructure.com/calendar"))
    }

    func test_rejectsEmptyString() {
        XCTAssertFalse(CanvasService.isValidFeedURL(""))
    }
}
