import XCTest
@testable import AtlasCore

/// Phase 2 List view: the agenda's four fixed buckets (Late / Due today / Tomorrow /
/// This week). Late is the bucket `AgendaBuilder.build` deliberately drops as "past",
/// so it gets the most coverage here.
final class AgendaBucketTests: XCTestCase {

    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! }

    private func day(_ offset: Int, hour: Int = 15) -> Date {
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    private func task(_ title: String, due: Date?, done: Bool = false) -> TaskItem {
        TaskItem(title: title, dueLabel: "", done: done, dueDate: due)
    }

    private func event(_ title: String, at start: Date) -> CalendarEvent {
        CalendarEvent(title: title, subtitle: "", start: start,
                      end: start.addingTimeInterval(3600), color: .blue, spaceName: "School")
    }

    func test_lateBucketComesFirstAndHoldsOverdueTasks() {
        let buckets = AgendaBuilder.buckets(
            events: [],
            tasks: [task("Overdue essay", due: day(-2)), task("Today's lab", due: day(0))],
            now: now, calendar: cal
        )
        XCTAssertEqual(buckets.first?.kind, .late)
        XCTAssertEqual(buckets.first?.items.map(\.title), ["Overdue essay"])
    }

    func test_completedOverdueTaskIsNotLate() {
        let buckets = AgendaBuilder.buckets(
            events: [], tasks: [task("Finished", due: day(-3), done: true)], now: now, calendar: cal
        )
        XCTAssertFalse(buckets.contains { $0.kind == .late })
    }

    /// A past EVENT is over, not late — only tasks can be late.
    func test_pastEventIsNotLate() {
        let buckets = AgendaBuilder.buckets(
            events: [event("Yesterday's lecture", at: day(-1))], tasks: [], now: now, calendar: cal
        )
        XCTAssertFalse(buckets.contains { $0.kind == .late })
    }

    func test_todayAndTomorrowSplitIntoTheirOwnBuckets() {
        let buckets = AgendaBuilder.buckets(
            events: [event("Lecture", at: day(0)), event("Seminar", at: day(1))],
            tasks: [], now: now, calendar: cal
        )
        let byKind = Dictionary(uniqueKeysWithValues: buckets.map { ($0.kind, $0.items.map(\.title)) })
        XCTAssertEqual(byKind[.dueToday], ["Lecture"])
        XCTAssertEqual(byKind[.tomorrow], ["Seminar"])
    }

    func test_emptyBucketsAreOmitted() {
        let buckets = AgendaBuilder.buckets(
            events: [], tasks: [task("Only late", due: day(-1))], now: now, calendar: cal
        )
        XCTAssertEqual(buckets.map(\.kind), [.late])
    }

    func test_bucketOrderIsAlwaysLateFirstThenChronological() {
        let buckets = AgendaBuilder.buckets(
            events: [event("Lecture", at: day(0)), event("Seminar", at: day(1))],
            tasks: [task("Overdue", due: day(-1))],
            now: now, calendar: cal
        )
        let kinds = buckets.map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(3)), [.late, .dueToday, .tomorrow])
    }
}
