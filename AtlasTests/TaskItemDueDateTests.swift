import XCTest
import SwiftUI
@testable import Atlas

final class TaskItemDueDateTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func plus(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }

    func testNilDateIsEmptyLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: nil, now: now), "")
    }
    func testTodayLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: now, now: now), "Today")
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
    func testTaskItemCarriesDueDateAndDuration() {
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t = TaskItem(title: "Essay", dueLabel: "", dueDate: due, durationMin: 90)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 90)
    }
}
