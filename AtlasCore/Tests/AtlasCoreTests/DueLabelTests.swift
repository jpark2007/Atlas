import XCTest
@testable import AtlasCore

/// Spec §3: stated times are sacred — the label shows them. Local midnight means
/// date-only, so no time is shown. The clock suffix is compared via `expectedClock`
/// (the same "h a"/"h:mm a" DateFormatter the product uses) so assertions stay exact
/// on every locale, including 24-hour runners, while still catching a wrong suffix.
final class DueLabelTests: XCTestCase {

    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! }

    /// Clock suffix `dueLabel` appends, built with the product's exact pattern.
    private func expectedClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = cal.dateComponents([.minute], from: date).minute == 0 ? "h a" : "h:mm a"
        return f.string(from: date)
    }

    func test_todayWithTime_showsClock() {
        let due = cal.date(bySettingHour: 17, minute: 30, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today " + expectedClock(due))
    }

    func test_todayOnTheHour_dropsMinutes() {
        let due = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today " + expectedClock(due))
    }

    func test_localMidnight_isDateOnly() {
        let due = cal.startOfDay(for: now)
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today")
    }

    func test_tomorrowWithTime_showsClock() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let due = cal.date(bySettingHour: 9, minute: 15, second: 0, of: tomorrow)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Tomorrow " + expectedClock(due))
    }
}
