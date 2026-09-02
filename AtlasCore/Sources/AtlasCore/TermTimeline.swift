import Foundation

/// A class page is one timeline, not two lists: "this week" means every quiz, exam and
/// assignment this week, in the order they arrive. `TermTimeline` is the merge — tasks and
/// events reduced to the only three things bucketing needs (identity, date, title) and
/// grouped with exactly the same week-horizon / month rules `TaskGrouping` already uses.
///
/// Pure and calendar-injectable so the merge order is testable without a view.
public enum TermTimeline {

    /// One thing on the timeline. `kind` is carried so the renderer can look the original
    /// task or event back up and keep its own row style — a quiz must still read as a quiz.
    public struct Entry: Identifiable, Equatable {
        public enum Kind: Equatable { case task, event }

        public let id: UUID
        public let kind: Kind
        /// The instant this entry sorts and buckets by: a task's `effectiveDueDate`, an
        /// event's `bucketDate`. `nil` only for an undated task.
        public let date: Date?
        public let title: String

        public init(id: UUID, kind: Kind, date: Date?, title: String) {
            self.id = id
            self.kind = kind
            self.date = date
            self.title = title
        }
    }

    /// Open tasks and events as one list of entries, unsorted (the groupers below sort).
    /// Done tasks are excluded, matching `TaskGrouping.byWeekHorizon` — a finished item
    /// belongs behind the "COMPLETED" reveal, not in this week.
    public static func entries(
        tasks: [TaskItem],
        events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [Entry] {
        tasks.filter { !$0.done }.map {
            Entry(id: $0.id, kind: .task, date: $0.effectiveDueDate(calendar: calendar), title: $0.title)
        }
        + events.map {
            Entry(id: $0.id, kind: .event, date: $0.bucketDate(in: calendar), title: $0.title)
        }
    }

    /// Partition entries into the week horizon — the same window `TaskGrouping` scopes
    /// tasks to, so "This week" can only ever mean one thing. Empty horizons are absent.
    public static func byWeekHorizon(
        entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimeModel.WeekHorizon: [Entry]] {
        var grouped: [TimeModel.WeekHorizon: [Entry]] = [:]
        for entry in entries {
            grouped[TimeModel.horizon(of: entry.date, now: now, calendar: calendar), default: []].append(entry)
        }
        return grouped.mapValues(sorted)
    }

    /// Group dated entries by the MONTH they fall in, ascending — the rest of the term.
    /// Undated entries are omitted (they have no place on a term timeline).
    public static func byMonth(
        entries: [Entry],
        calendar: Calendar = .current
    ) -> [(month: Date, entries: [Entry])] {
        var grouped: [Date: [Entry]] = [:]
        for entry in entries {
            guard let date = entry.date,
                  let month = calendar.dateInterval(of: .month, for: date)?.start else { continue }
            grouped[month, default: []].append(entry)
        }
        return grouped.keys.sorted().map { (month: $0, entries: sorted(grouped[$0] ?? [])) }
    }

    /// Date ascending (nil last), then title — the one deterministic order every bucket
    /// renders in, so a task and an event due the same day interleave by date rather than
    /// by which list they came from.
    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            switch (a.date, b.date) {
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
}
