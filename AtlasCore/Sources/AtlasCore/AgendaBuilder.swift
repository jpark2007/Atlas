import SwiftUI

/// One row in the agenda (List) view — either a calendar event or a dated task,
/// flattened into a common shape so the list renders and sorts them uniformly.
public struct AgendaItem: Identifiable {
    public enum Kind { case event, task }

    public let id: UUID            // underlying CalendarEvent.id or TaskItem.id (for tap resolution)
    public let kind: Kind
    public let title: String
    public let date: Date          // the time it sorts/groups by
    public let endDate: Date?      // for a duration label; nil for date-only items
    public let allDay: Bool        // all-day events + due-only tasks render at the top of their day
    public let color: Color
    public let spaceName: String
}

/// A day's worth of agenda items, in render order.
public struct AgendaSection: Identifiable {
    public let day: Date           // start-of-day key
    public let items: [AgendaItem]
    public var id: Date { day }
}

/// Pure builder that merges events + dated tasks into a chronological,
/// day-grouped agenda. Kept free of `AppState` and SwiftUI layout so the
/// ordering is unit-testable with an injected `Calendar`.
public enum AgendaBuilder {

    /// Build the upcoming agenda starting at the start of `from`'s day.
    ///
    /// - Events whose `start` is before that day-start are dropped (past).
    /// - Tasks contribute when not `done` and they have a `scheduledAt` (timed)
    ///   or, failing that, a `dueDate` (rendered as an all-day item); past-dated
    ///   tasks are dropped the same way.
    /// - Sections are returned in ascending day order. Within a day: all-day
    ///   items first, then by `date`, ties broken by case-insensitive title.
    public static func build(
        events: [CalendarEvent],
        tasks: [TaskItem],
        from: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AgendaSection] {
        let dayStart = calendar.startOfDay(for: from)
        var items: [AgendaItem] = []

        for ev in events where ev.start >= dayStart {
            items.append(AgendaItem(
                id: ev.id,
                kind: .event,
                title: ev.title,
                date: ev.start,
                endDate: ev.end,
                allDay: ev.isAllDay,
                color: ev.color,
                spaceName: ev.spaceName
            ))
        }

        for task in tasks where !task.done {
            guard let date = task.scheduledAt ?? task.dueDate, date >= dayStart else { continue }
            let timed = task.scheduledAt != nil
            let end = timed
                ? date.addingTimeInterval(TimeInterval((task.durationMin ?? 60) * 60))
                : nil
            items.append(AgendaItem(
                id: task.id,
                kind: .task,
                title: task.title,
                date: date,
                endDate: end,
                allDay: !timed,           // due-only tasks sit at the top of their day
                color: task.spaceColor,
                spaceName: task.spaceName
            ))
        }

        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            let dayItems = grouped[day]!.sorted { a, b in
                if a.allDay != b.allDay { return a.allDay && !b.allDay } // all-day first
                if a.date != b.date { return a.date < b.date }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            return AgendaSection(day: day, items: dayItems)
        }
    }
}

// MARK: - Bucketed agenda (List view)

/// The List view's four fixed buckets. Ordered as declared — Late always first, so an
/// overdue item can never be scrolled past on the way to today's work.
public enum AgendaBucketKind: Int, CaseIterable, Identifiable {
    case late, dueToday, tomorrow, thisWeek
    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .late:     return "Late"
        case .dueToday: return "Due today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        }
    }
}

/// One bucket of the List agenda.
public struct AgendaBucket: Identifiable {
    public let kind: AgendaBucketKind
    public let items: [AgendaItem]
    public var id: Int { kind.rawValue }
}

extension AgendaBuilder {

    /// Bucketed agenda for the calendar's List mode: Late / Due today / Tomorrow / This week.
    ///
    /// Reuses `build` for the forward-looking material (so ordering rules stay in one place)
    /// and adds the Late bucket, which `build` deliberately drops as "past". Empty buckets
    /// are omitted. "This week" runs from the day after tomorrow through the end of the
    /// current week; anything beyond that is out of scope for the list.
    public static func buckets(
        events: [CalendarEvent],
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AgendaBucket] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        // End of the current week (exclusive), or a 7-day fallback if the interval is missing.
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end
            ?? calendar.date(byAdding: .day, value: 7, to: today) ?? today

        // Late: open, dated tasks whose due DAY is already behind us. Events are never
        // "late" — an event that happened is simply over.
        let lateItems: [AgendaItem] = tasks
            .filter { !$0.done }
            .compactMap { task in
                guard let due = task.dueDate, calendar.startOfDay(for: due) < today else { return nil }
                return AgendaItem(
                    id: task.id,
                    kind: .task,
                    title: task.title,
                    date: due,
                    endDate: nil,
                    allDay: true,
                    color: task.spaceColor,
                    spaceName: task.spaceName
                )
            }
            .sorted { $0.date < $1.date }

        let forward = build(events: events, tasks: tasks, from: today, now: now, calendar: calendar)
        func items(in range: Range<Date>) -> [AgendaItem] {
            forward.filter { range.contains($0.day) }.flatMap(\.items)
        }

        let candidates: [(AgendaBucketKind, [AgendaItem])] = [
            (.late,     lateItems),
            (.dueToday, items(in: today..<tomorrow)),
            (.tomorrow, items(in: tomorrow..<dayAfter)),
            (.thisWeek, dayAfter < weekEnd ? items(in: dayAfter..<weekEnd) : [])
        ]
        return candidates.filter { !$0.1.isEmpty }.map { AgendaBucket(kind: $0.0, items: $0.1) }
    }
}
