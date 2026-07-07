import XCTest
@testable import AtlasCore
@testable import Atlas

/// The "passed vs overdue" model:
/// - `isEffectivelyUnscheduled` means ONLY never-scheduled (`scheduledAt == nil`).
/// - A task whose slot has elapsed stays on the grid (dimmed) — it does NOT resurface
///   to the tray on its own.
/// - `needsReplan` (overdue AND the scheduled slot has elapsed) is what returns a
///   work-block to the Unscheduled tray; `isOverdue` keys off `dueDate`, not the slot.
final class TaskItemUnscheduledTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func task(scheduledAt: Date? = nil, dueDate: Date? = nil,
                      durationMin: Int? = 60, done: Bool = false) -> TaskItem {
        var t = TaskItem(title: "T", dueLabel: "")
        t.scheduledAt = scheduledAt
        t.dueDate = dueDate
        t.durationMin = durationMin
        t.done = done
        return t
    }

    // MARK: isEffectivelyUnscheduled — now means ONLY scheduledAt == nil

    func testNilSlotIsUnscheduled() {
        XCTAssertTrue(task(scheduledAt: nil).isEffectivelyUnscheduled)
    }

    func testFutureSlotIsScheduled() {
        let future = now.addingTimeInterval(2 * 3600)
        XCTAssertFalse(task(scheduledAt: future).isEffectivelyUnscheduled)
    }

    func testPastSlotStaysScheduled() {
        // Slot ended 1.5h ago, not done → stays on the grid (dimmed), NOT unscheduled.
        let past = now.addingTimeInterval(-2 * 3600)
        XCTAssertFalse(task(scheduledAt: past, durationMin: 30).isEffectivelyUnscheduled)
    }

    // MARK: isOverdue — dueDate in the past and not done

    func testOverdueWhenDuePassedAndNotDone() {
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertTrue(task(dueDate: pastDue).isOverdue(now: now))
    }

    func testNotOverdueWhenDueInFuture() {
        let futureDue = now.addingTimeInterval(3600)
        XCTAssertFalse(task(dueDate: futureDue).isOverdue(now: now))
    }

    func testNotOverdueWhenNoDueDate() {
        XCTAssertFalse(task(dueDate: nil).isOverdue(now: now))
    }

    func testNotOverdueWhenDoneEvenIfDuePassed() {
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertFalse(task(dueDate: pastDue, done: true).isOverdue(now: now))
    }

    // MARK: needsReplan — overdue AND its scheduled slot has elapsed → back to tray

    func testNeedsReplanWhenOverdueAndSlotElapsed() {
        let past = now.addingTimeInterval(-2 * 3600)
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertTrue(task(scheduledAt: past, dueDate: pastDue, durationMin: 30).needsReplan(now: now))
    }

    func testNoReplanWhenOverdueButRescheduledToFuture() {
        // Re-dragged to a future slot — stays on the grid even though the due date passed.
        let future = now.addingTimeInterval(2 * 3600)
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertFalse(task(scheduledAt: future, dueDate: pastDue).needsReplan(now: now))
    }

    func testNoReplanWhenSlotElapsedButNotOverdue() {
        // Past slot but the due date is still in the future → dimmed on the grid, no replan.
        let past = now.addingTimeInterval(-2 * 3600)
        let futureDue = now.addingTimeInterval(3600)
        XCTAssertFalse(task(scheduledAt: past, dueDate: futureDue, durationMin: 30).needsReplan(now: now))
    }

    func testNoReplanWhenDone() {
        let past = now.addingTimeInterval(-2 * 3600)
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertFalse(task(scheduledAt: past, dueDate: pastDue, durationMin: 30, done: true).needsReplan(now: now))
    }

    func testNilDurationDefaultsToSixtyMinutes() {
        // Started 90 min ago with no explicit duration → default 60 → slot elapsed;
        // with a past due date → needs replan.
        let started = now.addingTimeInterval(-90 * 60)
        let pastDue = now.addingTimeInterval(-3600)
        XCTAssertTrue(task(scheduledAt: started, dueDate: pastDue, durationMin: nil).needsReplan(now: now))
    }
}
