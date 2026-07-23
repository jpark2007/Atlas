import XCTest
import SwiftUI
@testable import AtlasCore

/// Spec §2: source is derived at ingest — a row carrying a googleEventId came
/// from Google; everything else is Atlas-native. Never a hardcoded label.
final class EventRowSourceTests: XCTestCase {

    private func event(googleEventId: String?) -> CalendarEvent {
        CalendarEvent(title: "Standup", subtitle: "",
                      start: Date(), end: Date().addingTimeInterval(3600),
                      color: .red, spaceName: "Work",
                      googleEventId: googleEventId)
    }

    func test_toDomain_withGoogleEventId_derivesGoogleSource() {
        let row = EventRow(domain: event(googleEventId: "abc123"))
        XCTAssertEqual(row.toDomain().source, .google)
    }

    func test_toDomain_withoutGoogleEventId_staysAtlas() {
        let row = EventRow(domain: event(googleEventId: nil))
        XCTAssertEqual(row.toDomain().source, .atlas)
    }

    // MARK: - Canvas source (rule 5) — Task 4

    /// A row carrying a `canvas_uid` is a Canvas ICS event: server-owned, so it
    /// derives `.canvas` and is read-only in Atlas.
    func test_toDomain_withCanvasUid_derivesCanvasSourceAndReadOnly() {
        var row = EventRow(domain: event(googleEventId: nil))
        row.canvasUid = "canvas-assign-42"
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .canvas)
        XCTAssertTrue(ev.isReadOnly, "Canvas events are server-owned → read-only")
    }

    /// canvas-sync stamps its events with a Google id too (google_origin), so a row
    /// with BOTH must resolve to `.canvas` — canvas takes precedence over google.
    func test_toDomain_canvasBeatsGoogle() {
        var row = EventRow(domain: event(googleEventId: "g-1"))
        row.canvasUid = "canvas-1"
        XCTAssertEqual(row.toDomain().source, .canvas)
    }

    /// A plain Google row (no canvas_uid) stays `.google` and is not forced read-only.
    func test_toDomain_googleWithoutCanvas_staysGoogleAndWritable() {
        let row = EventRow(domain: event(googleEventId: "g-2"))
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .google)
        XCTAssertFalse(ev.isReadOnly)
    }

    // MARK: - Multi-ICS calendar feeds — feed_type precedence (Phase 3)

    /// `feed_type = "ics"` derives a named generic-feed source (rule 5: a Schoology feed
    /// labels as ITSELF, never "Canvas") and is read-only (any feed row is server-owned).
    func test_toDomain_icsFeedType_derivesNamedIcsSourceAndReadOnly() {
        let feedID = UUID()
        var row = EventRow(domain: event(googleEventId: nil))
        row.feedId = feedID
        row.feedType = "ics"
        let ev = row.toDomain(feedNames: [feedID: "Schoology"])
        XCTAssertEqual(ev.source, .icsFeed(name: "Schoology"))
        XCTAssertEqual(ev.source.displayName, "Schoology")
        XCTAssertNotEqual(ev.source, .canvas, "an ICS feed must never resolve to Canvas")
        XCTAssertTrue(ev.isReadOnly, "feed rows are server-owned → read-only")
    }

    /// An `ics` row whose feed id isn't in the name map falls back to "Calendar" rather
    /// than mislabeling the source.
    func test_toDomain_icsFeedType_unresolvedName_fallsBackToCalendar() {
        var row = EventRow(domain: event(googleEventId: nil))
        row.feedId = UUID()
        row.feedType = "ics"
        XCTAssertEqual(row.toDomain().source, .icsFeed(name: "Calendar"))
    }

    /// `feed_type = "canvas"` derives `.canvas` (the display name stays "Canvas").
    func test_toDomain_canvasFeedType_derivesCanvasSource() {
        var row = EventRow(domain: event(googleEventId: nil))
        row.feedId = UUID()
        row.feedType = "canvas"
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .canvas)
        XCTAssertTrue(ev.isReadOnly)
    }

    /// Feed rows also carry a google id (google_origin), so `feed_type` MUST win over
    /// google — an "ics" feed event with a googleEventId still resolves to the ICS feed.
    func test_toDomain_icsFeedTypeBeatsGoogle() {
        let feedID = UUID()
        var row = EventRow(domain: event(googleEventId: "g-9"))
        row.feedId = feedID
        row.feedType = "ics"
        XCTAssertEqual(row.toDomain(feedNames: [feedID: "Outlook"]).source,
                       .icsFeed(name: "Outlook"))
    }

    /// Migration-window fallback: a row with a null `feed_type` but a `canvas_uid` (not yet
    /// backfilled) still derives `.canvas`.
    func test_toDomain_nullFeedTypeWithCanvasUid_fallsBackToCanvas() {
        var row = EventRow(domain: event(googleEventId: "g-3"))
        row.canvasUid = "canvas-legacy"
        // feedType stays nil (pre-migration row)
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .canvas)
        XCTAssertTrue(ev.isReadOnly)
    }

    /// The wire mapping: PostgREST returns `canvas_uid` as a plain column; decoding
    /// must surface it (silent-drop guard — the bug being fixed). Unknown extra
    /// columns like `google_origin` are tolerated/ignored.
    func test_toDomain_decodesCanvasUidFromServerJSON() throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let json = """
        {"id":"\(UUID().uuidString)","space_name":"School","title":"HW 3 due","subtitle":"",\
        "start_at":"2026-07-11T17:00:00Z","end_at":"2026-07-11T18:00:00Z","is_all_day":false,\
        "canvas_uid":"canvas-assign-99","google_origin":true}
        """
        let row = try dec.decode(EventRow.self, from: Data(json.utf8))
        XCTAssertEqual(row.canvasUid, "canvas-assign-99")
        let ev = row.toDomain()
        XCTAssertEqual(ev.source, .canvas)
        XCTAssertTrue(ev.isReadOnly)
    }

    /// The wire mapping for the multi-ICS columns: `feed_id` / `feed_type` decode as
    /// plain snake_case columns and drive the named source through the feeds lookup.
    func test_toDomain_decodesFeedColumnsFromServerJSON() throws {
        let feedID = UUID()
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let json = """
        {"id":"\(UUID().uuidString)","space_name":"School","title":"Chorus","subtitle":"",\
        "start_at":"2026-07-11T17:00:00Z","end_at":"2026-07-11T18:00:00Z","is_all_day":false,\
        "canvas_uid":"ics-uid-7","feed_id":"\(feedID.uuidString)","feed_type":"ics",\
        "google_origin":true}
        """
        let row = try dec.decode(EventRow.self, from: Data(json.utf8))
        XCTAssertEqual(row.feedId, feedID)
        XCTAssertEqual(row.feedType, "ics")
        let ev = row.toDomain(feedNames: [feedID: "Schoology"])
        XCTAssertEqual(ev.source, .icsFeed(name: "Schoology"))
        XCTAssertTrue(ev.isReadOnly)
    }

    /// Rows predating the migration have no `feed_id` / `feed_type` columns at all — the
    /// decode must not break (optional columns → nil) and derivation falls back to the
    /// legacy rules.
    func test_toDomain_decodesWithoutFeedColumns() throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let json = """
        {"id":"\(UUID().uuidString)","space_name":"Work","title":"Standup","subtitle":"",\
        "start_at":"2026-07-11T17:00:00Z","end_at":"2026-07-11T18:00:00Z","is_all_day":false,\
        "google_event_id":"g-x"}
        """
        let row = try dec.decode(EventRow.self, from: Data(json.utf8))
        XCTAssertNil(row.feedId)
        XCTAssertNil(row.feedType)
        XCTAssertEqual(row.toDomain().source, .google)
    }
}
