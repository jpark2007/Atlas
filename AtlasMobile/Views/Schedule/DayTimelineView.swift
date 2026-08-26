import SwiftUI
import AtlasCore

/// The day's timeline. Order/merge comes from the shared `AgendaBuilder` (same
/// semantics as the Mac); each row is then resolved back to its real
/// `CalendarEvent`/`TaskItem` so events show their true source and read-only
/// sources get no destructive actions. Due-but-untimed tasks are excluded here —
/// they live in `NeedsTimeSection`.
///
/// Phase-2 calendar language, in list form:
/// • **Deadlines are boundaries, not blocks** — they leave the timeline and gather in
///   their own compact "Due today / Due tomorrow / Due Mar 3" header group, each row a
///   flag marker at its due time.
/// • **Work sessions read as the plan, not the commitment** — where the grid uses a
///   dashed outline, the list uses a dashed spine plus the shared `TimeModel` planned
///   label. An event's spine stays solid.
/// • **Red is earned, once**: a deadline goes red only when it's due today with no work
///   time planned (`TimeModel.isDueTodayUnplanned`). Everything overdue is amber, in the
///   `LateGroup` above — a red overdue graveyard causes avoidance.
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
        // Events + scheduled (timed) tasks stay. Among due-only tasks (kind .task &&
        // allDay), keep the ones carrying a clock time — those render as deadline rows;
        // date-only due tasks live in the Needs-a-time block.
        return dayItems.filter { item in
            guard item.kind == .task, item.allDay else { return true }
            return hasClockTime(item.date)
        }
    }

    /// Deadline markers for the day — due-only tasks carrying a clock time.
    private var dueItems: [AgendaItem] { items.filter { $0.kind == .task && $0.allDay } }
    /// Everything that actually occupies time: events, class meetings, work sessions.
    private var timelineItems: [AgendaItem] { items.filter { !($0.kind == .task && $0.allDay) } }

    var body: some View {
        dueSection
        timelineSection
    }

    // MARK: - Due group

    @ViewBuilder
    private var dueSection: some View {
        if !dueItems.isEmpty {
            Section {
                ForEach(dueItems) { item in
                    row(for: item)
                        .listRowInsets(EdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                }
            } header: {
                HStack {
                    Text("\(dueHeading) · \(dueItems.count)")
                        .edCapsLabel()
                        .textCase(nil)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }
        }
    }

    /// "Due today" / "Due tomorrow" / "Due Mar 3" — the phone's UpAhead-style grouping,
    /// named by the shown day so paging days keeps the label honest.
    private var dueHeading: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Due today" }
        if cal.isDateInTomorrow(day) { return "Due tomorrow" }
        return "Due \(Self.dueDayFormat.string(from: day))"
    }

    private static let dueDayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    // MARK: - Timeline

    private var timelineSection: some View {
        Section {
            if timelineItems.isEmpty {
                emptyContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(timelineItems) { item in
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
            AtlasLoader(size: 26)
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
        // A due-only task that survived the filter is a clock-timed deadline.
        let isDeadline = item.kind == .task && item.allDay
        // The one place red is earned: due today with no work time planned.
        let urgent = isDeadline && (task.map { TimeModel.isDueTodayUnplanned($0, now: now) } ?? false)
        // A timed task IS a work session — planned time, not a commitment.
        let isWorkSession = item.kind == .task && !item.allDay

        HStack(alignment: .top, spacing: 12) {
            timeColumn(item, isNow: isNow, urgent: urgent)

            if isDeadline {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(urgent ? AtlasTheme.Colors.danger : item.color)
                    .padding(.top, 3)
            } else if let task {
                checkCircle(task)
            } else {
                Circle().fill(item.color).frame(width: 9, height: 9).padding(.top, 4)
            }

            // Solid spine = something happening; dashed spine = planned work. Same
            // solid-vs-dashed distinction the Mac's grid tiles make, at list scale.
            if !isDeadline { spine(color: item.color, dashed: isWorkSession) }

            Text(item.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle((task?.done ?? false) ? MobileTheme.faint : MobileTheme.ink)
                .strikethrough(task?.done ?? false, color: MobileTheme.faint)
                // Work sessions read as provisional, like their faded tiles on the grid.
                .opacity(isWorkSession ? 0.75 : 1)

            Spacer(minLength: 8)

            trailingTag(item: item, event: event, isNow: isNow,
                        isDeadline: isDeadline, urgent: urgent,
                        workSessionTask: isWorkSession ? task : nil)
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

    /// The row's type spine: solid for an event/class meeting, dashed for a work session.
    private func spine(color: Color, dashed: Bool) -> some View {
        Group {
            if dashed {
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(color)
            }
        }
        .frame(width: 3, height: 20)
        .padding(.top, 1)
    }

    private func timeColumn(_ item: AgendaItem, isNow: Bool, urgent: Bool) -> some View {
        // Only genuine all-day events read "all-day"; a clock-timed deadline shows its due time.
        let text = (item.allDay && item.kind == .event) ? "all-day" : clock(item.date)
        let color: Color = urgent ? AtlasTheme.Colors.danger
            : isNow ? MobileTheme.accentText : MobileTheme.muted
        return Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 66, alignment: .leading)
    }

    private func checkCircle(_ task: TaskItem) -> some View {
        CheckCircle(done: task.done, color: task.spaceColor) { onToggle(task) }
            .padding(.top, 1)
    }

    private func trailingTag(item: AgendaItem, event: CalendarEvent?, isNow: Bool,
                             isDeadline: Bool, urgent: Bool,
                             workSessionTask: TaskItem?) -> some View {
        let text: String
        let color: Color
        if isNow { text = "NOW"; color = MobileTheme.accentText }
        else if isDeadline { text = "DUE"; color = urgent ? AtlasTheme.Colors.danger : MobileTheme.faint }
        // A work session states the plan it belongs to ("2.5 of 4h planned"), from the
        // same shared TimeModel math the Mac's due markers use.
        else if let task = workSessionTask {
            text = TimeModel.plannedLabel(estimateMin: task.estimateMin,
                                          sessionMinutes: [task.durationMin ?? 60])
            color = MobileTheme.faint
        }
        else if let event { text = sourceLabel(event.source); color = MobileTheme.faint }
        else { text = item.spaceName; color = MobileTheme.faint }

        return Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(0.84).textCase(.uppercase)
            .foregroundStyle(color)
            .fixedSize()
    }

    @ViewBuilder
    private func swipeActions(for item: AgendaItem) -> some View {
        // Atlas + Google events are deletable (deletes tombstone back to Google);
        // Apple events stay read-only. Google work-block tasks aren't hand-deletable.
        if item.kind == .task, let task = tasks.first(where: { $0.id == item.id }),
           task.workBlockGoogleEventId == nil {
            Button(role: .destructive) { onDelete(task) } label: {
                Label("Delete", systemImage: "trash")
            }
        } else if item.kind == .event, let event = events.first(where: { $0.id == item.id }),
                  event.source == .atlas || event.source == .google {
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
        case .canvas: return "Canvas"
        case .icsFeed: return source.displayName   // the feed's own name — never "Canvas"
        }
    }

    /// True when a date carries a specific clock time (not local midnight) — the
    /// signal that a due-only task is a real deadline, not a date-only "needs a time".
    private func hasClockTime(_ date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0
    }
}
