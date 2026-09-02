import SwiftUI

extension DateInterval {
    /// `start ..< end`. `DateInterval.contains` includes the END instant, which would put
    /// the first tick of next week in BOTH weeks — never what a window wants.
    func containsHalfOpen(_ date: Date) -> Bool { date >= start && date < end }
}

/// Pure time-model logic for the Phase-2 calendar language: late detection, the
/// "due today with nothing planned" red state, and the deadline↔work-session
/// planned-time math. Kept free of `AppState` and SwiftUI layout so every rule
/// is unit-testable with an injected `Calendar` / `now`.
public enum TimeModel {

    // MARK: - Late

    /// One overdue open task, as the Late bar renders it.
    public struct LateItem: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        /// The date the item was ORIGINALLY due — `originalDueDate` when the task has been
        /// rescheduled off the Late bar, otherwise its current `dueDate`. Never rewritten,
        /// so "you missed this on the 3rd" survives any number of reschedules.
        public let originalDue: Date
        public let daysLate: Int
        public let spaceName: String
        public let color: Color

        public init(id: UUID, title: String, originalDue: Date, daysLate: Int, spaceName: String, color: Color) {
            self.id = id
            self.title = title
            self.originalDue = originalDue
            self.daysLate = daysLate
            self.spaceName = spaceName
            self.color = color
        }
    }

    /// Open tasks whose due DAY is strictly before today — the Late bar's contents,
    /// oldest first. Deliberately day-granular (not `dueDate < now`): something due at
    /// 5 PM today is not "late", it's due today; that's the red state below, not amber.
    public static func lateItems(
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LateItem] {
        let today = calendar.startOfDay(for: now)
        return tasks.compactMap { task -> LateItem? in
            guard !task.done, let due = task.effectiveDueDate(calendar: calendar) else { return nil }
            let original = task.originalDueDate ?? due
            let dueDay = calendar.startOfDay(for: due)
            guard dueDay < today else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: original), to: today).day ?? 0
            return LateItem(
                id: task.id,
                title: task.title,
                originalDue: original,
                daysLate: max(1, days),
                spaceName: task.spaceName,
                color: task.spaceColor
            )
        }
        .sorted { $0.originalDue < $1.originalDue }
    }

    /// "4 days late" / "1 day late".
    public static func daysLateLabel(_ days: Int) -> String {
        days == 1 ? "1 day late" : "\(days) days late"
    }

    /// Late-bar triage, as data: every overdue open task moved to `date`, with
    /// `originalDueDate` stamped once so the ORIGINAL date survives as a faded marker in
    /// the past. Returns only the tasks that changed, for the caller to apply + persist.
    /// Never automatic — this only ever runs from an explicit "Reschedule N late items".
    /// Shared so Mac and iOS reschedule identically.
    public static func rescheduleLate(
        tasks: [TaskItem],
        to date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let lateIDs = Set(lateItems(tasks: tasks, now: now, calendar: calendar).map(\.id))
        return tasks.filter { lateIDs.contains($0.id) }.map { task in
            var updated = task
            if updated.originalDueDate == nil { updated.originalDueDate = updated.dueDate }
            updated.dueDate = date
            updated.dueLabel = TaskItem.dueLabel(for: date)
            return updated
        }
    }

    // MARK: - Red state

    /// The ONE place red is earned: the task is due today and no work time is planned for
    /// it. Pressure where pressure helps — an overdue graveyard stays amber (see `lateItems`).
    public static func isDueTodayUnplanned(
        _ task: TaskItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !task.done, let due = task.effectiveDueDate(calendar: calendar) else { return false }
        guard calendar.isDate(due, inSameDayAs: now) else { return false }
        return task.scheduledAt == nil
    }

    // MARK: - Week horizon

    /// Where a date sits relative to the week `now` is in — the shared window the calendar
    /// rail and the class page are both scoped to, so "this week" can only ever mean one
    /// thing. Deliberately day-granular at the front edge: something due at 5 PM today is
    /// still this week's work, never `.overdue`.
    public enum WeekHorizon: Int, CaseIterable, Sendable {
        case overdue, thisWeek, nextWeek, later, noDate

        public var title: String {
            switch self {
            case .overdue:  return "Overdue"
            case .thisWeek: return "This week"
            case .nextWeek: return "Next week"
            case .later:    return "Later"
            case .noDate:   return "No date"
            }
        }
    }

    /// The calendar week containing `date`. The ONE definition of a week in Atlas —
    /// `dateInterval(of: .weekOfYear,…)` should not be called anywhere else.
    public static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 60 * 60)
    }

    /// The week `offset` weeks from the one containing `date` (0 = this week, 1 = next).
    public static func weekInterval(offset: Int, from date: Date, calendar: Calendar = .current) -> DateInterval {
        let base = weekStart(for: date, calendar: calendar)
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: base) ?? base
        return weekInterval(containing: shifted, calendar: calendar)
    }

    /// First instant of the week containing `date`.
    public static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        weekInterval(containing: date, calendar: calendar).start
    }

    public static func isInCurrentWeek(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        weekInterval(containing: now, calendar: calendar).containsHalfOpen(date)
    }

    public static func isInFollowingWeek(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        weekInterval(offset: 1, from: now, calendar: calendar).containsHalfOpen(date)
    }

    /// Classify one already-resolved due instant. Callers holding a `TaskItem` should go
    /// through `TaskGrouping.horizon(for:)`, which unpacks the all-day encoding first.
    public static func horizon(of due: Date?, now: Date = Date(), calendar: Calendar = .current) -> WeekHorizon {
        guard let due else { return .noDate }
        if calendar.startOfDay(for: due) < calendar.startOfDay(for: now) { return .overdue }
        if isInCurrentWeek(due, now: now, calendar: calendar) { return .thisWeek }
        if isInFollowingWeek(due, now: now, calendar: calendar) { return .nextWeek }
        return .later
    }

    // MARK: - Planned time (deadline ↔ work session link)

    /// The planned-time readout carried by a due marker.
    ///
    /// - `sessionMinutes`: the length of every work session planned for the task. Atlas
    ///   currently persists one session per task (`TaskItem.scheduledAt`), so this is a
    ///   0- or 1-element array today; the math is written over the array so multi-session
    ///   support is a data change, not a logic change.
    /// - With an estimate the marker reads as a fill ("2.5 of 4h planned"); with none it
    ///   falls back to a count ("1 session planned"), per the spec's optional-estimate rule.
    public static func plannedLabel(estimateMin: Int?, sessionMinutes: [Int]) -> String {
        let planned = sessionMinutes.reduce(0, +)
        if let estimate = estimateMin, estimate > 0 {
            return "\(hoursLabel(planned)) of \(hoursLabel(estimate)) planned"
        }
        if sessionMinutes.isEmpty { return "No time planned" }
        return sessionMinutes.count == 1 ? "1 session planned" : "\(sessionMinutes.count) sessions planned"
    }

    /// Fraction of the estimate that is planned, clamped to 0...1. `nil` when the task
    /// carries no estimate — the marker then shows a count instead of a fill.
    public static func plannedFraction(estimateMin: Int?, sessionMinutes: [Int]) -> Double? {
        guard let estimate = estimateMin, estimate > 0 else { return nil }
        let planned = sessionMinutes.reduce(0, +)
        return min(1, max(0, Double(planned) / Double(estimate)))
    }

    /// "0h" / "45m" / "2.5h" / "4h" — compact hours for the planned-time readout.
    /// Whole hours drop the decimal; sub-hour amounts stay in minutes.
    public static func hoursLabel(_ minutes: Int) -> String {
        if minutes <= 0 { return "0h" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }

    // MARK: - "+ more time"

    /// Where a past session's "+ more time" click puts the next one: the SAME clock time
    /// tomorrow. Deliberately boring and predictable — Atlas never picks a "smart" slot
    /// (auto-slot scheduling is cut), and the new session is draggable like any other.
    public static func nextSessionSlot(
        after session: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)
        let h = calendar.component(.hour, from: session)
        let m = calendar.component(.minute, from: session)
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) ?? tomorrow
    }
}
