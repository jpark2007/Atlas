import SwiftUI
import AtlasCore

/// The quiet mono footer under a task/event list that expands a hidden
/// completed/past group in place — "3 COMPLETED ˅". Shared by the project
/// and space detail views.
struct RevealRow: View {
    let count: Int
    let noun: String
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("\(count) \(noun)")
                    .atlasMono(size: 10, weight: .medium)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .atlasFont(size: 9, weight: .semibold)
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A due-window group header — "OVERDUE ──── 2" — over a task list. The rule between
/// the label and the count is what keeps a stack of these reading as one list rather
/// than as separate cards. `late` paints the whole header amber (Late is amber, never
/// red — see `LateBar`). Shared by the calendar rail and the class page so the two
/// surfaces group work the same way.
struct TaskGroupHeader: View {
    let title: String
    let count: Int
    var late = false

    var body: some View {
        HStack(spacing: 8) {
            // One line, always: in a narrow rail "THIS WEEK · AUG 30 – SEP 5" used to
            // wrap across two or three lines and leave the rule and count floating.
            // It truncates instead; the rule takes whatever width is left.
            Text(title.uppercased())
                .atlasMono(size: 10, weight: .semibold)
                .tracking(1.0)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Rectangle()
                .fill(AtlasTheme.Colors.hairline)
                .frame(height: 1)
                .frame(minWidth: 8)
            Text("\(count)")
                .atlasMono(size: 10, weight: .semibold)
                .fixedSize()
        }
        .foregroundStyle(late ? AtlasTheme.Colors.late : AtlasTheme.Colors.textMuted)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// The quiet outlined pill under a windowed list — "Show next week (6)", "See all 41
/// tasks". Widens the window in place; never navigates.
struct ShowMoreButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 11.5, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A class/space list scoped the way a TERM is lived (variant 2C): the near work in
/// due buckets — Overdue, then This week — and everything past this week folded into
/// collapsed month sections that open on click.
///
/// Tasks AND events share the folds: "this week" on a class page means every quiz, exam
/// and assignment this week, in date order, not two unscoped lists (Drew, 09-01). Each
/// keeps its own row style inside the fold, so a quiz still reads as a quiz.
///
/// Months start CLOSED on purpose. A course is 49 tasks long; showing December in
/// September is the density problem, not the fix. The whole semester stays one glance
/// away as four fold rows.
struct TermTaskList<Row: View, EventRow: View>: View {
    let tasks: [TaskItem]
    let events: [CalendarEvent]
    var now: Date = Date()
    /// The owning view's own task row — kept there so the class page and the space page
    /// each keep their own row affordances.
    @ViewBuilder let row: (TaskItem) -> Row
    /// The owning view's event row, for the same reason.
    @ViewBuilder let eventRow: (CalendarEvent) -> EventRow

    init(tasks: [TaskItem],
         events: [CalendarEvent] = [],
         now: Date = Date(),
         @ViewBuilder row: @escaping (TaskItem) -> Row,
         @ViewBuilder eventRow: @escaping (CalendarEvent) -> EventRow) {
        self.tasks = tasks
        self.events = events
        self.now = now
        self.row = row
        self.eventRow = eventRow
    }

    /// Which month sections are open. Keyed by the month's first instant.
    @State private var openMonths: Set<Date> = []
    /// The undated tail, folded like a month.
    @State private var showUndated = false

    private var entries: [TermTimeline.Entry] {
        TermTimeline.entries(tasks: tasks, events: events)
    }

    private var horizons: [TaskGrouping.WeekHorizon: [TermTimeline.Entry]] {
        TermTimeline.byWeekHorizon(entries: entries, now: now)
    }

    private func bucket(_ h: TaskGrouping.WeekHorizon) -> [TermTimeline.Entry] { horizons[h] ?? [] }

    /// With nothing due this week, next week gets its own open section instead of hiding
    /// inside a month fold — only then, so a busy week still reads as one list.
    private var showsNextWeek: Bool {
        bucket(.thisWeek).isEmpty && !bucket(.nextWeek).isEmpty
    }

    /// Everything past this week — next week included, unless it has been pulled out above
    /// — laid out as the rest of the term.
    private var months: [(month: Date, entries: [TermTimeline.Entry])] {
        TermTimeline.byMonth(entries: (showsNextWeek ? [] : bucket(.nextWeek)) + bucket(.later),
                             calendar: .current)
    }

    private var tasksByID: [UUID: TaskItem] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var eventsByID: [UUID: CalendarEvent] {
        Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !bucket(.overdue).isEmpty {
                TaskGroupHeader(title: "Overdue", count: bucket(.overdue).count, late: true)
                rows(bucket(.overdue))
            }
            if !bucket(.thisWeek).isEmpty {
                TaskGroupHeader(title: "This week", count: bucket(.thisWeek).count)
                rows(bucket(.thisWeek))
            }
            if bucket(.overdue).isEmpty && bucket(.thisWeek).isEmpty {
                TaskGroupHeader(title: "This week", count: 0)
                Text("Nothing due this week")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 9)
            }
            if showsNextWeek {
                TaskGroupHeader(title: "Next week", count: bucket(.nextWeek).count)
                rows(bucket(.nextWeek))
            }

            if !months.isEmpty || !bucket(.noDate).isEmpty {
                Divider()
                    .overlay(AtlasTheme.Colors.hairline)
                    .padding(.top, 14)
                ForEach(months, id: \.month) { section in
                    foldRow(title: monthTitle(section.month),
                            subtitle: rangeLabel(section.entries),
                            isOpen: openMonths.contains(section.month)) {
                        toggle(section.month)
                    }
                    if openMonths.contains(section.month) { rows(section.entries) }
                }
                if !bucket(.noDate).isEmpty {
                    foldRow(title: "No date",
                            subtitle: "\(bucket(.noDate).count) item\(bucket(.noDate).count == 1 ? "" : "s")",
                            isOpen: showUndated) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showUndated.toggle() }
                    }
                    if showUndated { rows(bucket(.noDate)) }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ items: [TermTimeline.Entry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                switch entry.kind {
                case .task:
                    if let task = tasksByID[entry.id] { row(task) }
                case .event:
                    if let event = eventsByID[entry.id] { eventRow(event) }
                }
                if i < items.count - 1 {
                    Divider().overlay(AtlasTheme.Colors.hairline)
                }
            }
        }
    }

    /// "October — Midterm 1 · 14 items — Show". One row per month of the remaining term.
    private func foldRow(title: String, subtitle: String, isOpen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .atlasFont(size: 13.5, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(subtitle)
                        .atlasFont(size: 11.5, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer(minLength: 6)
                Text(isOpen ? "Hide" : "Show")
                    .atlasMono(size: 11.5, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .atlasHairlineBelow()
    }

    private func toggle(_ month: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if openMonths.contains(month) { openMonths.remove(month) } else { openMonths.insert(month) }
        }
    }

    /// "Rest of September" for the month in progress, "October" after it, and a year once
    /// the term crosses into one.
    private func monthTitle(_ month: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(month, equalTo: now, toGranularity: .month) {
            return "Rest of \(TermTaskFormat.month.string(from: month))"
        }
        if cal.isDate(month, equalTo: now, toGranularity: .year) {
            return TermTaskFormat.month.string(from: month)
        }
        return CalendarFormat.monthYear.string(from: month)
    }

    /// "12 items · Sep 8 – Sep 30".
    private func rangeLabel(_ items: [TermTimeline.Entry]) -> String {
        let count = "\(items.count) item\(items.count == 1 ? "" : "s")"
        guard let first = items.first?.date, let last = items.last?.date else { return count }
        let span = LifecycleDate.short(first) == LifecycleDate.short(last)
            ? LifecycleDate.short(first)
            : "\(LifecycleDate.short(first)) – \(LifecycleDate.short(last))"
        return "\(count) · \(span)"
    }
}

extension TermTaskList where EventRow == EmptyView {
    /// A list with nothing but tasks in it — a space page, which has no term to fold
    /// events into.
    init(tasks: [TaskItem], now: Date = Date(), @ViewBuilder row: @escaping (TaskItem) -> Row) {
        self.init(tasks: tasks, events: [], now: now, row: row, eventRow: { _ in EmptyView() })
    }
}

enum TermTaskFormat {
    /// "September" — a month section's own name.
    static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()
}

/// Project/space event row — color bar, title, mono meta line. `dimmed` is the
/// past-event treatment: faded bar and muted title. Shared so the two views can't
/// drift apart.
struct LifecycleEventRow: View {
    let event: CalendarEvent
    var dimmed = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3, height: 30)
                .opacity(dimmed ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(dimmed ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                Text(meta)
                    .atlasMono(size: 11)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    /// "SEP 24 · 2 PM · 1h" for something that happens at a time; "SEP 24" for something
    /// that only happens on a DAY.
    ///
    /// The day is always shown: these rows now live inside month-wide folds, where a bare
    /// clock time says nothing. And an event with no real clock time never prints one —
    /// a syllabus quiz shown as "12 AM · 1h" was Atlas's invented midnight, not the exam's
    /// start time. `hasSpecificTime` is false both for a proper all-day event and for the
    /// midnight rows committed before syllabus events were marked all-day.
    private var meta: String {
        let day = LifecycleDate.short(event.bucketDate(in: .current))
        guard event.hasSpecificTime else { return day }
        return "\(day) · \(event.timeLabel) · \(event.durationLabel)"
    }
}

/// "JUL 3" — the short mono date completed/past rows carry.
enum LifecycleDate {
    static func short(_ date: Date) -> String {
        formatter.string(from: date).uppercased()
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
