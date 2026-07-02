import SwiftUI
import AtlasCore

/// The day's timeline. Order/merge comes from the shared `AgendaBuilder` (same
/// semantics as the Mac); each row is then resolved back to its real
/// `CalendarEvent`/`TaskItem` so events show their true source and read-only
/// sources get no destructive actions. Due-but-untimed tasks are excluded here —
/// they live in `NeedsTimeSection`.
struct DayTimelineView: View {
    let day: Date
    let now: Date
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let loading: Bool
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onOpen: (ItemDetailSheet.Detail) -> Void
    let onDeleteEvent: (CalendarEvent) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var items: [AgendaItem] {
        let cal = Calendar.current
        let sections = AgendaBuilder.build(events: events, tasks: tasks, from: day, now: now)
        let dayItems = sections.first { cal.isDate($0.day, inSameDayAs: day) }?.items ?? []
        // Due-only tasks (kind .task && allDay) belong to the Needs-a-time block.
        return dayItems.filter { !($0.kind == .task && $0.allDay) }
    }

    var body: some View {
        Section {
            if items.isEmpty {
                emptyContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    row(for: item)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                        .swipeActions(edge: .trailing) { swipeActions(for: item) }
                }
            }
        }
    }

    /// The empty-day row: a spinner while the store is loading, else the calm copy.
    @ViewBuilder
    private var emptyContent: some View {
        if loading {
            ProgressView().tint(MobileTheme.muted)
        } else {
            Text("Nothing scheduled")
                .edCapsLabel()
                .textCase(nil)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for item: AgendaItem) -> some View {
        let isNow = isCurrent(item)
        let task = item.kind == .task ? tasks.first { $0.id == item.id } : nil
        let event = item.kind == .event ? events.first { $0.id == item.id } : nil

        HStack(alignment: .top, spacing: 12) {
            timeColumn(item, isNow: isNow)

            if let task {
                checkCircle(task)
            } else {
                Circle().fill(item.color).frame(width: 9, height: 9).padding(.top, 4)
            }

            Text(item.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle((task?.done ?? false) ? MobileTheme.faint : MobileTheme.ink)
                .strikethrough(task?.done ?? false, color: MobileTheme.faint)

            Spacer(minLength: 8)

            trailingTag(item: item, event: event, isNow: isNow)
        }
        .overlay(alignment: .leading) {
            if isNow {
                Capsule().fill(MobileTheme.accent).frame(width: 3)
                    .padding(.vertical, -6).offset(x: -16)
            }
        }
        // Tapping the row (the check-circle handles its own taps) opens the detail sheet.
        .contentShape(Rectangle())
        .onTapGesture {
            if let task { onOpen(.task(task)) }
            else if let event { onOpen(.event(event)) }
        }
    }

    private func timeColumn(_ item: AgendaItem, isNow: Bool) -> some View {
        Text(item.allDay ? "all-day" : clock(item.date))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isNow ? MobileTheme.accentText : MobileTheme.muted)
            .frame(width: 66, alignment: .leading)
    }

    private func checkCircle(_ task: TaskItem) -> some View {
        CheckCircle(done: task.done, color: task.spaceColor) { onToggle(task) }
            .padding(.top, 1)
    }

    private func trailingTag(item: AgendaItem, event: CalendarEvent?, isNow: Bool) -> some View {
        let text: String
        if isNow { text = "NOW" }
        else if let event { text = sourceLabel(event.source) }
        else { text = item.spaceName }

        return Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(0.84).textCase(.uppercase)
            .foregroundStyle(isNow ? MobileTheme.accentText : MobileTheme.faint)
            .fixedSize()
    }

    @ViewBuilder
    private func swipeActions(for item: AgendaItem) -> some View {
        // Only Atlas-native tasks are destructible; read-only events + Google work-blocks aren't.
        if item.kind == .task, let task = tasks.first(where: { $0.id == item.id }),
           task.workBlockGoogleEventId == nil {
            Button(role: .destructive) { onDelete(task) } label: {
                Label("Delete", systemImage: "trash")
            }
        } else if item.kind == .event, let event = events.first(where: { $0.id == item.id }),
                  event.source == .atlas {
            Button(role: .destructive) { onDeleteEvent(event) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    /// True when this row is the item happening now (today only, timed items).
    private func isCurrent(_ item: AgendaItem) -> Bool {
        guard isToday, !item.allDay else { return false }
        let end = item.endDate ?? item.date.addingTimeInterval(3600)
        return item.date <= now && now < end
    }

    private static let clockHour: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h a"; return f }()
    private static let clockHourMinute: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()

    private func clock(_ date: Date) -> String {
        let onHour = Calendar.current.component(.minute, from: date) == 0
        return (onHour ? Self.clockHour : Self.clockHourMinute).string(from: date)
    }

    private func sourceLabel(_ source: EventSource) -> String {
        switch source {
        case .atlas:  return "Atlas"
        case .apple:  return "Apple"
        case .google: return "Google"
        }
    }
}
