import SwiftUI

// TODO: richer time-bucketed metrics once tasks carry completedAt
//       (e.g. completedToday, completedThisWeek, streaks)

// MARK: - Supporting types

/// Per-space task distribution used for the space-load bars.
public struct SpaceLoad: Identifiable {
    public let id: UUID
    public let spaceName: String
    public let color: Color
    public let openCount: Int
    public let totalCount: Int

    public init(id: UUID = UUID(), spaceName: String, color: Color, openCount: Int, totalCount: Int) {
        self.id = id
        self.spaceName = spaceName
        self.color = color
        self.openCount = openCount
        self.totalCount = totalCount
    }
}

// MARK: - AtlasMetrics

/// A snapshot of Atlas activity derived purely from the app's collections.
/// No metrics are fabricated: only values directly computable from the
/// current data model are included. Focus-session history is NOT persisted
/// through AppState (FocusViewModel is in-memory only), so no focus metrics
/// are included here.
public struct AtlasMetrics {
    public let totalTasks: Int
    /// Tasks where `done == false`.
    public let openTasks: Int
    /// Tasks where `done == true`.
    public let doneTasks: Int
    /// Tasks where `scheduledAt != nil`.
    public let scheduledTasks: Int
    /// Events whose `start` falls on today (per the reference date's calendar day).
    public let eventsToday: Int
    /// Events whose `start` falls within the current calendar week.
    public let eventsThisWeek: Int
    /// Per-space task distribution, sorted by spaceName.
    public let perSpace: [SpaceLoad]
    /// Mean of `goals.progress`; 0 when there are no goals.
    public let goalAvgProgress: Double
    public let noteCount: Int
    /// `doneTasks / max(1, totalTasks)` — never NaN.
    public let completionRate: Double

    // MARK: Pure compute (array-based, testable without AppState)

    /// Primary computation.  All parameters have sensible defaults so callers
    /// (and tests) only need to supply the data they care about.
    ///
    /// What each population is, and why:
    ///
    /// - **Tasks** (`tasks`): everything the store holds, whatever door it came through —
    ///   Atlas-native, Canvas, or another ICS feed. A Canvas assignment is real coursework
    ///   you check off locally, so it counts toward open/done/completion like any task.
    ///   Class MEETINGS are deliberately absent: a lecture is an event on the timetable,
    ///   never something you complete, so it must not move a completion rate.
    /// - **Events** (`events` + synthesized class meetings): every calendar commitment in
    ///   the counted window, from whichever calendar it came — Atlas, Google, Canvas, an
    ///   imported `.ics` exam, or Apple. Class meetings never exist as stored rows (they're
    ///   synthesized from each class's `meetingPattern`), so they are materialized here for
    ///   the week and merged into the same pool, then run through `collapsingDuplicates` —
    ///   a lecture that ALSO arrives from Google counts once, not twice.
    ///   Work-blocks and deadline markers are excluded: those are tasks drawn on the grid,
    ///   already counted by the task stats. Term Key Date flags aren't events at all
    ///   ("Spring break" is a label on the day), so callers don't pass them.
    ///
    /// - Parameters:
    ///   - classes: the active term's live classes, whose meeting patterns are synthesized
    ///     into the counted week. Empty (or `term == nil`) ⇒ no meetings are counted.
    ///   - term: the active term; meetings only exist inside its dates and off its breaks.
    ///   - calendar: Calendar used for day/week bucketing (default: `.current`).
    ///   - referenceDate: The "now" anchor (default: `Date()`).  Injected in
    ///     tests to avoid week-boundary flakiness.
    public static func compute(
        tasks:         [TaskItem],
        events:        [CalendarEvent],
        goals:         [Goal],
        spaces:        [Space],
        notes:         [Note],
        classes:       [Project] = [],
        term:          Term?     = nil,
        calendar:      Calendar  = .current,
        referenceDate: Date      = Date()
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
        // Only the counted week matters, so narrow before merging and deduping.
        let stored = events.filter {
            !$0.isWorkBlock && !$0.isDeadline && weekInterval.contains($0.bucketDate(in: calendar))
        }
        let counted = CalendarSync.collapsingDuplicates(
            stored + classMeetings(in: weekInterval, classes: classes, term: term, calendar: calendar),
            calendar: calendar
        )
        let eventsToday    = counted.filter { calendar.isDate($0.bucketDate(in: calendar), inSameDayAs: now) }.count
        let eventsThisWeek = counted.count

        // ── Per-space task load ────────────────────────────────────────────
        // Group tasks by spaceName, accumulating open + total counts. Class tasks carry
        // their School space's name like any other task, so School rolls up here even
        // though the sidebar lists classes under the School section instead of SPACES —
        // the grouping is over tasks, so a class can be neither orphaned nor counted twice.
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

    /// Every class meeting inside `interval`, day by day — the only way they exist, since
    /// a meeting is synthesized from its class's pattern rather than stored as a row.
    private static func classMeetings(
        in interval: DateInterval,
        classes: [Project],
        term: Term?,
        calendar: Calendar
    ) -> [CalendarEvent] {
        guard let term, !classes.isEmpty else { return [] }
        var out: [CalendarEvent] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            out += SchoolCalendar.meetingEvents(on: day, classes: classes, term: term, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}
