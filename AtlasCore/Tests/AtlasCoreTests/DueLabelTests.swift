import XCTest
@testable import AtlasCore

/// Spec §3: stated times are sacred — the label shows them. Local midnight means
/// date-only, so no time is shown. (Literals assume an en-US 12-hour device
/// locale, matching the existing formatter usage in dueLabel.)
final class DueLabelTests: XCTestCase {

    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! }

    func test_todayWithTime_showsClock() {
        let due = cal.date(bySettingHour: 17, minute: 30, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today 5:30 PM")
    }

    func test_todayOnTheHour_dropsMinutes() {
        let due = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today 5 PM")
    }

    func test_localMidnight_isDateOnly() {
        let due = cal.startOfDay(for: now)
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today")
    }

    func test_tomorrowWithTime_showsClock() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let due = cal.date(bySettingHour: 9, minute: 15, second: 0, of: tomorrow)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Tomorrow 9:15 AM")
    }
}
