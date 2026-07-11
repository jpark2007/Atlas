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
}
