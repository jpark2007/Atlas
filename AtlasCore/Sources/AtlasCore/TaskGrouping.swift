import Foundation

/// Pure, testable grouping of tasks into due-date buckets for the dashboard.
///
/// Buckets are returned in a fixed order — **Overdue / Today / This week /
/// Later / No date** — and only non-empty buckets are included. Bucketing is
/// derived purely from `TaskItem.dueDate`; tasks without a due date land in
/// "No date". `now` and `calendar` are injectable so the logic is deterministic
/// under test (no hidden `Date()` / locale dependency).
public enum TaskGrouping {

    /// Stable bucket identity + display title, in render order.
    enum Bucket: Int, CaseIterable {
        case overdue, today, thisWeek, later, noDate

        var title: String {
            switch self {
            case .overdue:  return "Overdue"
            case .today:    return "Today"
            case .thisWeek: return "This week"
            case .later:    return "Later"
            case .noDate:   return "No date"
            }
        }
    }

    /// Classify a single task's `dueDate` into a bucket relative to `now`.
    static func bucket(for dueDate: Date?, now: Date, calendar: Calendar) -> Bucket {
        guard let due = dueDate else { return .noDate }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue   = calendar.startOfDay(for: due)

        if startOfDue < startOfToday { return .overdue }
        if startOfDue == startOfToday { return .today }

        // Future date: within the remainder of this calendar week, or beyond it.
        if let week = calendar.dateInterval(of: .weekOfYear, for: now),
           week.contains(due) {
            return .thisWeek
        }
        return .later
    }

    // MARK: - Week horizon

    public typealias WeekHorizon = TimeModel.WeekHorizon

    /// Where one task sits relative to the current week. Reads `effectiveDueDate`, so a
    /// Canvas date-only due buckets on ITS OWN day rather than the evening before.
    public static func horizon(
        for task: TaskItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeekHorizon {
        TimeModel.horizon(of: task.effectiveDueDate(calendar: calendar), now: now, calendar: calendar)
    }

    /// Partition OPEN tasks into the week horizon — the data behind the week-scoped
    /// calendar rail and the class page's near-term buckets. Empty horizons are absent;
    /// each list is sorted by effective due date ascending (nil last), then title.
    public static func byWeekHorizon(
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeekHorizon: [TaskItem]] {
        var grouped: [WeekHorizon: [TaskItem]] = [:]
        for task in tasks where !task.done {
            grouped[horizon(for: task, now: now, calendar: calendar), default: []].append(task)
        }
        return grouped.mapValues { sortedByDue($0, calendar: calendar) }
    }

    /// Group dated tasks by the MONTH they're due in, ascending — the "rest of the term"
    /// sections on a class page. `month` is the first instant of that month, for titling.
    /// Undated tasks are omitted (they have no place on a term timeline).
    public static func byMonth(
        tasks: [TaskItem],
        calendar: Calendar = .current
    ) -> [(month: Date, tasks: [TaskItem])] {
        var grouped: [Date: [TaskItem]] = [:]
        for task in tasks {
            guard let due = task.effectiveDueDate(calendar: calendar),
                  let month = calendar.dateInterval(of: .month, for: due)?.start else { continue }
            grouped[month, default: []].append(task)
        }
        return grouped.keys.sorted().map { (month: $0, tasks: sortedByDue(grouped[$0] ?? [], calendar: calendar)) }
    }

    /// Effective due ascending (nil last), then title — the one deterministic order every
    /// horizon/month list is rendered in.
    private static func sortedByDue(_ tasks: [TaskItem], calendar: Calendar) -> [TaskItem] {
        tasks.sorted { a, b in
            switch (a.effectiveDueDate(calendar: calendar), b.effectiveDueDate(calendar: calendar)) {
            case let (ad?, bd?):
                if ad != bd { return ad < bd }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil):
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    /// Group `tasks` by space name, ordered by `spaceOrder` (sidebar order).
    /// Within each group tasks are sorted by due date ascending (nil last), then title.
    /// Tasks with no space land in a trailing "No Space" bucket.
    public static func bySpace(
        tasks: [TaskItem],
        spaceOrder: [String],
        calendar: Calendar = .current
    ) -> [(spaceName: String, tasks: [TaskItem])] {
        var grouped: [String: [TaskItem]] = [:]
        for task in tasks {
            grouped[task.spaceName.isEmpty ? "" : task.spaceName, default: []].append(task)
        }

        let sortByDue = { (items: [TaskItem]) -> [TaskItem] in
            items.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (ad?, bd?):
                    return ad != bd ? ad < bd
                        : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil):
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
            }
        }

        var result: [(spaceName: String, tasks: [TaskItem])] = []
        let known = Set(spaceOrder)

        for name in spaceOrder {
            if let items = grouped[name], !items.isEmpty {
                result.append((spaceName: name, tasks: sortByDue(items)))
            }
        }
        // Tasks assigned to a space not in the sidebar (edge case)
        for (name, items) in grouped where !name.isEmpty && !known.contains(name) {
            result.append((spaceName: name, tasks: sortByDue(items)))
        }
        // No-space bucket last
        if let items = grouped[""], !items.isEmpty {
            result.append((spaceName: "No Space", tasks: sortByDue(items)))
        }
        return result
    }

    /// Group `tasks` by due-date bucket. Returns `(title, tasks)` pairs in fixed
    /// bucket order, omitting empty buckets. Within a bucket tasks are sorted by
    /// `dueDate` ascending (nil last), then by title — deterministic for tests.
    public static func byDueBucket(
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(title: String, tasks: [TaskItem])] {

        var grouped: [Bucket: [TaskItem]] = [:]
        for task in tasks {
            grouped[bucket(for: task.effectiveDueDate(calendar: calendar), now: now, calendar: calendar), default: []].append(task)
        }

        return Bucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            let sorted = items.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (ad?, bd?):
                    if ad != bd { return ad < bd }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case (nil, _?): return false   // nil dates sort last
                case (_?, nil): return true
                case (nil, nil):
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
            }
            return (title: bucket.title, tasks: sorted)
        }
    }
}
