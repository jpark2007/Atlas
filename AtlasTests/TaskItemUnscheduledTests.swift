import XCTest
@testable import Atlas

/// Non-destructive "resurface after the slot passes" rule.
final class TaskItemUnscheduledTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func task(scheduledAt: Date?, durationMin: Int? = 60, done: Bool = false) -> TaskItem {
        var t = TaskItem(title: "T", dueLabel: "")
        t.scheduledAt = scheduledAt
        t.durationMin = durationMin
        t.done = done
        return t
    }

    func testNilSlotIsUnscheduled() {
        XCTAssertTrue(task(scheduledAt: nil).isEffectivelyUnscheduled(now: now))
    }

    func testFutureSlotIsScheduled() {
        let future = now.addingTimeInterval(2 * 3600)
        XCTAssertFalse(task(scheduledAt: future).isEffectivelyUnscheduled(now: now))
    }

    func testPastUncheckedResurfaces() {
        // Slot 2h ago, 30 min long → ended 1.5h ago, not done → resurfaces.
        let past = now.addingTimeInterval(-2 * 3600)
        XCTAssertTrue(task(scheduledAt: past, durationMin: 30).isEffectivelyUnscheduled(now: now))
    }

    func testPastButDoneStaysScheduled() {
        let past = now.addingTimeInterval(-2 * 3600)
        XCTAssertFalse(task(scheduledAt: past, durationMin: 30, done: true).isEffectivelyUnscheduled(now: now))
    }

    func testInProgressSlotStaysScheduled() {
        // Started 10 min ago, 60 min long → still running → not yet unscheduled.
        let started = now.addingTimeInterval(-10 * 60)
        XCTAssertFalse(task(scheduledAt: started, durationMin: 60).isEffectivelyUnscheduled(now: now))
    }

    func testNilDurationDefaultsToSixtyMinutes() {
        // Started 90 min ago with no explicit duration → default 60 → elapsed.
        let started = now.addingTimeInterval(-90 * 60)
        XCTAssertTrue(task(scheduledAt: started, durationMin: nil).isEffectivelyUnscheduled(now: now))
    }
}
