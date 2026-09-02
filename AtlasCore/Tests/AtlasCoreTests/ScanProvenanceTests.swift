import XCTest
@testable import AtlasCore

/// Scan provenance (migration 0046): the receipt an imported task or event points at.
/// The rules under test are the ones a mislabeled source would break — an id must
/// survive a save/load, and an item with no scan must never acquire one.
final class ScanProvenanceTests: XCTestCase {

    // MARK: Row round-trips

    func testTaskRowRoundTripsScanID() {
        let scan = UUID()
        var t = TaskItem(title: "Problem set 3", dueLabel: "")
        t.scanID = scan
        XCTAssertEqual(TaskRow(domain: t).toDomain().scanID, scan)
    }

    /// A hand-typed task came from nowhere but the user: it must stay sourceless.
    func testTaskRowNilScanIDStaysNil() {
        let t = TaskItem(title: "Buy milk", dueLabel: "")
        XCTAssertNil(TaskRow(domain: t).toDomain().scanID)
    }

    /// Unlike the feed columns, `scan_id` round-trips FROM the domain: a scanned event is
    /// Atlas-native and gets upserted back, so dropping it would erase the origin on the
    /// first edit.
    func testEventRowRoundTripsScanID() {
        let scan = UUID()
        var e = CalendarEvent(title: "Midterm", subtitle: "BIO 101", start: .now,
                              end: .now.addingTimeInterval(3600),
                              color: .blue, spaceName: "School")
        e.scanID = scan
        XCTAssertEqual(EventRow(domain: e).toDomain().scanID, scan)
    }

    func testEventRowNilScanIDStaysNil() {
        let e = CalendarEvent(title: "Coffee", subtitle: "", start: .now,
                              end: .now.addingTimeInterval(1800),
                              color: .blue, spaceName: "Personal")
        XCTAssertNil(EventRow(domain: e).toDomain().scanID)
    }

    /// Stamping a scan must not invent a Canvas origin — the two are independent, and a
    /// scanned item is not a synced one.
    func testScanIDDoesNotImplyCanvas() {
        var t = TaskItem(title: "Essay draft", dueLabel: "")
        t.scanID = UUID()
        let back = TaskRow(domain: t).toDomain()
        XCTAssertNil(back.canvasUID)
        XCTAssertNil(back.canvasCourse)
    }

    // MARK: ScanRow

    func testScanRowRoundTripsRecord() {
        let scan = ScanRecord(projectID: UUID(),
                              fileName: "BIO 101 syllabus.pdf",
                              kind: ScanRecord.Kind.syllabus)
        let back = ScanRow(domain: scan).toDomain()
        XCTAssertEqual(back.id, scan.id)
        XCTAssertEqual(back.projectID, scan.projectID)
        XCTAssertEqual(back.fileName, "BIO 101 syllabus.pdf")
        XCTAssertEqual(back.kind, "syllabus")
    }

    /// `created_at` is server-defaulted, so the client never sends it — encoding a fresh
    /// receipt must leave the column out rather than stamp a client clock on it.
    func testScanRowOmitsCreatedAtOnEncode() throws {
        let row = ScanRow(domain: ScanRecord(fileName: ScanRecord.pastedFileName,
                                             kind: ScanRecord.Kind.paste))
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(row))
        let dict = try XCTUnwrap(json as? [String: Any])
        XCTAssertNil(dict["created_at"])
        XCTAssertEqual(dict["file_name"] as? String, "Pasted text")
        XCTAssertEqual(dict["kind"] as? String, "paste")
    }

    /// A row from a DB that predates 0046 has no `scan_id` key at all; decoding must
    /// yield no source rather than fail the whole snapshot load.
    func testTaskRowDecodesWithoutScanIDColumn() throws {
        let json = """
        {"id":"\(UUID().uuidString)","space_name":"School","title":"Read ch. 4",
         "status":"open","done":false,"is_all_day":false}
        """
        let row = try JSONDecoder().decode(TaskRow.self, from: Data(json.utf8))
        XCTAssertNil(row.toDomain().scanID)
    }
}
