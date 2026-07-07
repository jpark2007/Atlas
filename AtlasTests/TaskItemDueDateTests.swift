import XCTest
import SwiftUI
@testable import AtlasCore
@testable import Atlas

final class TaskItemDueDateTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Local midnight `days` from now — dueLabel shows a bare day label only for
    /// date-only (midnight) deadlines; any other time is appended ("Today 5 PM").
    private func plus(_ days: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: days, to: now)!)
    }

    func testNilDateIsEmptyLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: nil, now: now), "")
    }
    func testTodayLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: plus(0), now: now), "Today")
    }
    func testTomorrowLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: plus(1), now: now), "Tomorrow")
    }
    func testWithinWeekUsesWeekday() {
        let d = plus(3)
        let f = DateFormatter(); f.dateFormat = "EEE"
        XCTAssertEqual(TaskItem.dueLabel(for: d, now: now), f.string(from: d))
    }
    func testBeyondWeekUsesMonthDay() {
        let d = plus(20)
        let f = DateFormatter(); f.dateFormat = "MMM d"
        XCTAssertEqual(TaskItem.dueLabel(for: d, now: now), f.string(from: d))
    }
    func testNonMidnightDeadlineAppendsTime() {
        let d = plus(0).addingTimeInterval(17 * 3600)   // today 5:00 PM
        XCTAssertEqual(TaskItem.dueLabel(for: d, now: now), "Today 5 PM")
    }
    func testTaskItemCarriesDueDateAndDuration() {
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t = TaskItem(title: "Essay", dueLabel: "", dueDate: due, durationMin: 90)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 90)
    }
}
