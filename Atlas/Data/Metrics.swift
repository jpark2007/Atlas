import SwiftUI
import AtlasCore

// TODO: richer time-bucketed metrics once tasks carry completedAt
//       (e.g. completedToday, completedThisWeek, streaks)

// MARK: - Supporting types

/// Per-space task distribution used for the space-load bars.
struct SpaceLoad: Identifiable {
    let id: UUID
    let spaceName: String
    let color: Color
    let openCount: Int
    let totalCount: Int
}

// MARK: - AtlasMetrics

/// A snapshot of Atlas activity derived purely from AppState.
/// No metrics are fabricated: only values directly computable from the
/// current data model are included. Focus-session history is NOT persisted
/// through AppState (FocusViewModel is in-memory only), so no focus metrics
/// are included here.
struct AtlasMetrics {
    let totalTasks: Int
    /// Tasks where `done == false`.
    let openTasks: Int
    /// Tasks where `done == true`.
    let doneTasks: Int
    /// Tasks where `scheduledAt != nil`.
    let scheduledTasks: Int
    /// Events whose `start` falls on today (per the reference date's calendar day).
    let eventsToday: Int
    /// Events whose `start` falls within the current calendar week.
    let eventsThisWeek: Int
    /// Per-space task distribution, sorted by spaceName.
    let perSpace: [SpaceLoad]
    /// Mean of `goals.progress`; 0 when there are no goals.
    let goalAvgProgress: Double
    let noteCount: Int
    /// `doneTasks / max(1, totalTasks)` — never NaN.
    let completionRate: Double

    // MARK: AppState convenience entry-point

    @MainActor
    static func compute(from state: AppState) -> AtlasMetrics {
        compute(
            tasks:  state.tasks,
            events: state.events,
            goals:  state.goals,
            spaces: state.spaces,
            notes:  state.notes
        )
    }

    // MARK: Pure compute (array-based, testable without AppState)

    /// Primary computation.  All parameters have sensible defaults so callers
    /// (and tests) only need to supply the data they care about.
    ///
    /// - Parameters:
    ///   - calendar: Calendar used for day/week bucketing (default: `.current`).
    ///   - referenceDate: The "now" anchor (default: `Date()`).  Injected in
    ///     tests to avoid week-boundary flakiness.
    static func compute(
        tasks:         [TaskItem],
        events:        [CalendarEvent],
        goals:         [Goal],
        spaces:        [Space],
        notes:         [Note],
        calendar:      Calendar = .current,
        referenceDate: Date     = Date()
    ) -> AtlasMetrics {
        let now = referenceDate

        // Current-week DateInterval; fall back to a 7-day window on failure.
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)

        // ── Tasks ──────────────────────────────────────────────────────────
        let totalTasks    = tasks.count
        let openTasks     = tasks.filter {  !$0.done }.count
        let doneTasks     = tasks.filter {   $0.done }.count
        let scheduledTasks = tasks.filter { $0.scheduledAt != nil }.count

        // ── Events ─────────────────────────────────────────────────────────
        let eventsToday    = events.filter { calendar.isDate($0.start, inSameDayAs: now) }.count
        let eventsThisWeek = events.filter { weekInterval.contains($0.start) }.count

        // ── Per-space task load ────────────────────────────────────────────
        // Group tasks by spaceName, accumulating open + total counts.
        var spaceMap: [String: (open: Int, total: Int)] = [:]
        for task in tasks {
            let name = task.spaceName.isEmpty ? "Other" : task.spaceName
            let prior = spaceMap[name] ?? (0, 0)
            spaceMap[name] = (prior.open + (task.done ? 0 : 1), prior.total + 1)
        }
        let unsorted: [SpaceLoad] = spaceMap.map { (name: String, counts: (open: Int, total: Int)) in
            // Resolve brand color from the spaces list; accent is the fallback.
            let color = spaces.first { $0.name == name }?.color ?? AtlasTheme.Colors.accent
            return SpaceLoad(
                id: UUID(), spaceName: name, color: color,
                openCount: counts.open, totalCount: counts.total
            )
        }
        let perSpace = unsorted.sorted { $0.spaceName < $1.spaceName }

        // ── Goals ──────────────────────────────────────────────────────────
        let goalAvgProgress: Double = goals.isEmpty
            ? 0.0
            : goals.map(\.progress).reduce(0, +) / Double(goals.count)

        // ── Derived ────────────────────────────────────────────────────────
        let completionRate = Double(doneTasks) / Double(max(1, totalTasks))

        return AtlasMetrics(
            totalTasks:       totalTasks,
            openTasks:        openTasks,
            doneTasks:        doneTasks,
            scheduledTasks:   scheduledTasks,
            eventsToday:      eventsToday,
            eventsThisWeek:   eventsThisWeek,
            perSpace:         perSpace,
            goalAvgProgress:  goalAvgProgress,
            noteCount:        notes.count,
            completionRate:   completionRate
        )
    }
}
