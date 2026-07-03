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
}
