import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

/// WS-5 — pure Google Calendar ⇄ Atlas mapping. Dates are compared to formatter
/// output (never hardcoded locale strings), so the suite is locale-independent.
final class GoogleCalendarMapperTests: XCTestCase {

    // MARK: - Decode (timed)

    func testDecodeTimedEvent() throws {
        let startISO = "2026-06-28T14:00:00Z"
        let endISO = "2026-06-28T15:30:00Z"
        let json = """
        { "items": [
          { "id": "evt-1", "summary": "Study session", "description": "Bring laptop",
            "start": { "dateTime": "\(startISO)" }, "end": { "dateTime": "\(endISO)" } }
        ] }
        """.data(using: .utf8)!

        let events = try GoogleCalendarMapper.decodeEvents(
            from: json, defaultSpaceName: "School", color: .blue)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.title, "Study session")
        XCTAssertEqual(event.notes, "Bring laptop")
        XCTAssertEqual(event.spaceName, "School")
        XCTAssertFalse(event.isAllDay)
        // A one-off (non-recurring) Google event is now editable two-way, not read-only.
        XCTAssertFalse(event.isReadOnly)
        XCTAssertFalse(event.isRecurring)
        XCTAssertEqual(event.start, GoogleCalendarMapper.rfc3339.date(from: startISO))
        XCTAssertEqual(event.end, GoogleCalendarMapper.rfc3339.date(from: endISO))
    }

    // MARK: - Decode (all-day)

    func testDecodeAllDayEvent() throws {
        let json = """
        { "items": [
          { "id": "evt-2", "summary": "Conference",
            "start": { "date": "2026-07-01" }, "end": { "date": "2026-07-02" } }
        ] }
        """.data(using: .utf8)!

        let events = try GoogleCalendarMapper.decodeEvents(
            from: json, defaultSpaceName: "Work", color: .green)

        let event = try XCTUnwrap(events.first)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.title, "Conference")
        XCTAssertEqual(event.start, GoogleCalendarMapper.allDayFormatter.date(from: "2026-07-01"))
        XCTAssertEqual(event.end, GoogleCalendarMapper.allDayFormatter.date(from: "2026-07-02"))
    }

    // MARK: - Decode (recurring instance stays read-only until Phase 3)

    func testDecodeRecurringInstanceIsReadOnlyAndFlagged() throws {
        let json = """
        { "items": [
          { "id": "evt-r_20260629", "summary": "CS 101 Lecture",
            "recurringEventId": "evt-r",
            "start": { "dateTime": "2026-06-29T09:00:00Z" },
            "end": { "dateTime": "2026-06-29T10:00:00Z" } }
        ] }
        """.data(using: .utf8)!

        let events = try GoogleCalendarMapper.decodeEvents(
            from: json, defaultSpaceName: "School", color: .blue)

        let event = try XCTUnwrap(events.first)
        XCTAssertTrue(event.isRecurring)
        XCTAssertTrue(event.isReadOnly)   // can't edit a recurring instance in Atlas yet
    }

    // MARK: - Decode tolerance

    func testDecodeSkipsEventsWithoutUsableTime() throws {
        let json = """
        { "items": [
          { "id": "ok", "summary": "Good", "start": { "dateTime": "2026-06-28T14:00:00Z" },
            "end": { "dateTime": "2026-06-28T15:00:00Z" } },
          { "id": "bad", "summary": "No times" }
        ] }
        """.data(using: .utf8)!

        let events = try GoogleCalendarMapper.decodeEvents(
            from: json, defaultSpaceName: "School", color: .blue)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Good")
    }

    func testDecodeEmptyItems() throws {
        let json = "{}".data(using: .utf8)!
        let events = try GoogleCalendarMapper.decodeEvents(
            from: json, defaultSpaceName: "School", color: .blue)
        XCTAssertTrue(events.isEmpty)
    }

    func testStableUUIDIsDeterministic() {
        XCTAssertEqual(GoogleCalendarMapper.stableUUID(from: "evt-1"),
                       GoogleCalendarMapper.stableUUID(from: "evt-1"))
        XCTAssertNotEqual(GoogleCalendarMapper.stableUUID(from: "evt-1"),
                          GoogleCalendarMapper.stableUUID(from: "evt-2"))
    }

    // MARK: - Write body (timed)

    func testEventBodyForTimedEvent() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(3600)
        let event = CalendarEvent(
            title: "Sync", subtitle: "", start: start, end: end,
            color: .blue, spaceName: "Work", notes: "agenda")

        let data = GoogleCalendarMapper.eventBody(for: event)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["summary"] as? String, "Sync")
        XCTAssertEqual(object["description"] as? String, "agenda")

        let startObj = try XCTUnwrap(object["start"] as? [String: Any])
        XCTAssertEqual(startObj["dateTime"] as? String,
                       GoogleCalendarMapper.rfc3339.string(from: start))
        XCTAssertNil(startObj["date"])

        let endObj = try XCTUnwrap(object["end"] as? [String: Any])
        XCTAssertEqual(endObj["dateTime"] as? String,
                       GoogleCalendarMapper.rfc3339.string(from: end))
    }

    // MARK: - Write body (all-day)

    func testEventBodyForAllDayEvent() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(86_400)
        let event = CalendarEvent(
            title: "Holiday", subtitle: "", start: start, end: end,
            color: .green, spaceName: "Personal", notes: nil, isAllDay: true)

        let data = GoogleCalendarMapper.eventBody(for: event)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["summary"] as? String, "Holiday")
        XCTAssertNil(object["description"])  // nil notes omitted

        let startObj = try XCTUnwrap(object["start"] as? [String: Any])
        XCTAssertEqual(startObj["date"] as? String,
                       GoogleCalendarMapper.allDayFormatter.string(from: start))
        XCTAssertNil(startObj["dateTime"])
    }

    // MARK: - Round-trip: write body decodes back to the same instant

    func testTimedWriteBodyDecodesBackToSameStart() throws {
        let start = Date(timeIntervalSince1970: 1_781_234_567)
        let end = start.addingTimeInterval(1800)
        let event = CalendarEvent(
            title: "RT", subtitle: "", start: start, end: end,
            color: .blue, spaceName: "Work")

        let body = GoogleCalendarMapper.eventBody(for: event)
        // Wrap as a one-item list and decode through the read path.
        let listJSON = "{\"items\":[\(String(data: body, encoding: .utf8)!)]}".data(using: .utf8)!
        let decoded = try GoogleCalendarMapper.decodeEvents(
            from: listJSON, defaultSpaceName: "Work", color: .blue)

        // RFC3339 with .withInternetDateTime drops sub-second precision, so compare
        // at whole-second granularity via the formatter round-trip.
        let expected = GoogleCalendarMapper.rfc3339.date(from:
            GoogleCalendarMapper.rfc3339.string(from: start))
        XCTAssertEqual(decoded.first?.start, expected)
    }
}
