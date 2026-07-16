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

    // MARK: - Per-project day-grid colors (Option B)

    /// The color a DAY/WEEK-GRID tile should wear: the tile's project color when
    /// that project set its own `colorToken`, else the space color already on the
    /// event. Applied ONLY to grid tiles — month dots, chips, sidebar and routing
    /// keep the space color untouched.
    ///
    /// Association: work-blocks (id == task.id) resolve through the backing task's
    /// project (name + space); other events resolve through `projectID`. An event
    /// with no project link, or whose project has no custom token, is returned
    /// unchanged (space color) — today's exact behavior.
    func gridColored(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.map { ev in
            guard let token = projectColorToken(for: ev) else { return ev }
            var e = ev
            e.color = ColorToken.color(for: token)
            return e
        }
    }

    /// The custom color token of the project a grid tile belongs to, or `nil` when
    /// the tile has no project link / the project inherits the space color.
    private func projectColorToken(for event: CalendarEvent) -> String? {
        if event.isWorkBlock, let task = tasks.first(where: { $0.id == event.id }) {
            return projectColorToken(spaceName: task.spaceName, projectName: task.projectName)
        }
        if let pid = event.projectID,
           let project = spaces.flatMap(\.projects).first(where: { $0.id == pid }) {
            return project.colorToken
        }
        return nil
    }

    /// The custom color token of the project matching `projectName` inside `spaceName`
    /// (empty name ⇒ no project). `nil` when nothing matches or the project inherits.
    private func projectColorToken(spaceName: String, projectName: String) -> String? {
        guard !projectName.isEmpty else { return nil }
        return spaces.flatMap(\.projects)
            .first { $0.name == projectName && $0.spaceName == spaceName }?
            .colorToken
    }

    /// Resolve a space name to its id for dual-writing `spaceID` alongside
    /// `spaceName` (collab phase 1). Nil when no space matches — the row then
    /// relies on the name fallback exactly as before.
    func spaceID(named name: String) -> UUID? {
        spaces.first { $0.name == name }?.id
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
