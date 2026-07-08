import XCTest
@testable import AtlasCore

final class AvailabilityMergeTests: XCTestCase {
    func testAllDayEventsAreNotBusy() {
        let allDay = CalendarEvent(title: "Holiday", subtitle: "", start: .now, end: .now.addingTimeInterval(86400),
                                   color: .blue, spaceName: "Personal", isAllDay: true)
        let blocks = AvailabilityDerivation.busyBlocks(from: [allDay], excludingDeadlines: true)
        XCTAssertTrue(blocks.isEmpty)
    }

    func testDeadlineMarkersAreNotBusy() {
        var deadline = CalendarEvent(title: "Essay due", subtitle: "", start: .now, end: .now.addingTimeInterval(3600),
                                     color: .blue, spaceName: "School")
        deadline.isDeadline = true
        let blocks = AvailabilityDerivation.busyBlocks(from: [deadline], excludingDeadlines: true)
        XCTAssertTrue(blocks.isEmpty)
    }

    func testTimedEventProducesABusyBlock() {
        let ev = CalendarEvent(title: "Standup", subtitle: "", start: .now, end: .now.addingTimeInterval(1800),
                               color: .blue, spaceName: "Work", source: .google)
        let blocks = AvailabilityDerivation.busyBlocks(from: [ev], excludingDeadlines: true)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].source, "google")
        XCTAssertEqual(blocks[0].startAt, ev.start)
        XCTAssertEqual(blocks[0].endAt, ev.end)
    }

    func testAtlasSourcedEventMapsToAtlasSourceString() {
        let ev = CalendarEvent(title: "Focus block", subtitle: "", start: .now, end: .now.addingTimeInterval(3600),
                               color: .blue, spaceName: "Work", source: .atlas)
        let blocks = AvailabilityDerivation.busyBlocks(from: [ev], excludingDeadlines: true)
        XCTAssertEqual(blocks[0].source, "atlas")
    }
}
