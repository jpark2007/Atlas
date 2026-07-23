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

    // MARK: - Generic ICS feeds — FeedService.isValidICSURL (multi-ICS feeds)

    /// The permissive multi-feed check accepts any https .ics link AND the Canvas shapes
    /// (so the same field works for both), plus providers that don't end in `.ics`.
    func test_isValidICSURL_acceptsGenericAndCanvasShapes() {
        // A Canvas feed still passes.
        XCTAssertTrue(FeedService.isValidICSURL(
            "https://school.instructure.com/feeds/calendars/user_abc123.ics"))
        // A plain .ics export.
        XCTAssertTrue(FeedService.isValidICSURL("https://example.com/exports/mine.ICS"))
        // Schoology-style ICS feed with no .ics suffix but an "ical"/"feed" path.
        XCTAssertTrue(FeedService.isValidICSURL(
            "https://app.schoology.com/calendar/12345/feed"))
        // Outlook published calendar (no .ics suffix, "calendar" segment).
        XCTAssertTrue(FeedService.isValidICSURL(
            "https://outlook.office365.com/owa/calendar/abc/reachcalendar.html"))
    }

    func test_isValidICSURL_rejectsNonHTTPSAndMissingHost() {
        XCTAssertFalse(FeedService.isValidICSURL(
            "http://example.com/exports/mine.ics"))
        XCTAssertFalse(FeedService.isValidICSURL(
            "webcal://example.com/exports/mine.ics"))
        XCTAssertFalse(FeedService.isValidICSURL("https:///calendar/feed"))
    }

    func test_isValidICSURL_rejectsUnrelatedPath() {
        // https + host but no ics/calendar/feed hint.
        XCTAssertFalse(FeedService.isValidICSURL("https://example.com/about"))
    }

    func test_isValidICSURL_rejectsEmptyString() {
        XCTAssertFalse(FeedService.isValidICSURL(""))
    }
}
