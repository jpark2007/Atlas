import SwiftUI
import AtlasCore

/// Calendar-feature helpers on the shared store. METHODS ONLY (no stored
/// properties) so this stays additive and merge-safe. The event/task source of
/// truth lives on `AppState` itself (`events`, `events(on:)`, `unscheduledTasks`,
/// `schedule(taskId:at:)`); these are just lookups the Calendar UI needs.
extension AppState {

    /// Brand color for a space name, falling back to the accent.
    func calendarSpaceColor(named name: String) -> Color {
        spaces.first { $0.name == name }?.color ?? AtlasTheme.Colors.accent
    }

    // MARK: - Auto-find-a-slot

    /// Busy `[start, end)` intervals on `day`: the day's timed events plus any
    /// tasks already scheduled there (`scheduledAt` + `durationMin`, default 60).
    /// All-day events are ignored — they don't block a time slot. `excludingTask`
    /// drops one task's own block so a re-suggest doesn't collide with itself.
    func busyIntervals(on day: Date, excludingTask excluded: UUID? = nil) -> [DateInterval] {
        let cal = Calendar.current
        var intervals: [DateInterval] = []

        for ev in events(on: day) where !ev.isAllDay && ev.end > ev.start {
            intervals.append(DateInterval(start: ev.start, end: ev.end))
        }
        for task in tasks {
            guard task.id != excluded,
                  let at = task.scheduledAt,
                  cal.isDate(at, inSameDayAs: day) else { continue }
            let end = at.addingTimeInterval(TimeInterval((task.durationMin ?? 60) * 60))
            intervals.append(DateInterval(start: at, end: end))
        }
        return intervals
    }

    /// Suggests the first free slot on `day` that fits `task` (default 60 min),
    /// within the visible hours, snapped to 15 min, never in the past. nil if the
    /// day is full. The tray's "Suggest time" action feeds this into `schedule`.
    func suggestSlot(for task: TaskItem, on day: Date, now: Date = Date()) -> Date? {
        SlotFinder.firstFreeSlot(
            durationMin: task.durationMin ?? 60,
            on: day,
            busy: busyIntervals(on: day, excludingTask: task.id),
            now: now
        )
    }
}
