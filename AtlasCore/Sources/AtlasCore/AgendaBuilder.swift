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
