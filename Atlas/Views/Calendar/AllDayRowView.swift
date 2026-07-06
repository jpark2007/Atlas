import SwiftUI
import AtlasCore

/// Horizontal all-day event strip placed between the column header and the time grid.
///
/// **Height behaviour:**  collapses to zero (renders nothing) when there are no
/// all-day events — achieved via an `if hasAnyAllDayEvents` guard in `body`.
///
/// **Task 5 hook:**  `CalendarEvent.isAllDay` doesn't exist yet.
/// When Task 5 adds the field, change the filter predicate in
/// `allDayEvents(for:)` from `{ _ in false }` to `{ $0.isAllDay }`.
struct AllDayRowView: View {
    let days: [Date]
    let columnWidth: CGFloat
    /// Shared 60-sec clock (AppState.now) — a day fully before `now` dims its all-day items.
    let now: Date
    let eventsProvider: (Date) -> [CalendarEvent]

    // MARK: - Helpers

    private func allDayEvents(for day: Date) -> [CalendarEvent] {
        eventsProvider(day).filter { $0.isAllDay }
    }

    private var hasAnyAllDayEvents: Bool {
        days.contains { !allDayEvents(for: $0).isEmpty }
    }

    // MARK: - Body

    var body: some View {
        if hasAnyAllDayEvents {
            HStack(spacing: 0) {
                // Width-only spacers (height 0) — a plain Color.clear is flexible in
                // BOTH axes and would stretch this strip to grab the grid's height.
                // +6 mirrors HourGutter's trailing padding so cells align with columns.
                Color.clear.frame(width: CalendarLayout.gutterWidth + 6, height: 0)
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    allDayCell(for: day)
                        .frame(width: columnWidth, height: CalendarLayout.allDayRowHeight)
                        .clipped()
                    if index < days.count - 1 {
                        Color.clear.frame(width: 1, height: 0)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        // else → EmptyView (0 height, nothing rendered)
    }

    @ViewBuilder
    private func allDayCell(for day: Date) -> some View {
        let events = allDayEvents(for: day)
        let deadlines = events.filter { $0.isDeadline }
        let others = events.filter { !$0.isDeadline }
        // A day fully in the past dims its (non-deadline) all-day items; deadline pills keep
        // their own red-overdue treatment and are never dimmed.
        let isPastDay = Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: now)
        VStack(spacing: 2) {
            // Several deadlines on one day would overflow the clipped cell — collapse them into
            // one "N due ▸" pill (tap → popover). A lone deadline keeps its flag-pill look.
            if deadlines.count > 1 {
                CollapsedDeadlinePill(deadlines: deadlines)
            } else {
                ForEach(deadlines) { deadlinePill($0) }
            }
            ForEach(others) { event in
                Text(event.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .background(event.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .opacity(isPastDay ? 0.65 : 1)
            }
        }
    }

    /// Deadline → flag-pill (matches the day-view DUE strip), red when overdue.
    private func deadlinePill(_ event: CalendarEvent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill").font(.system(size: 7))
            Text(event.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if event.hasSpecificTime {
                Text(event.timeLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(event.color)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 18)
        .background(AtlasTheme.wash(event.color), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Collapsed "N due ▸" pill for a week day-cell with several deadlines — taps to a popover
/// listing each. All deadlines in one cell share an overdue colour (same day), so the first
/// one's `color` drives the pill.
private struct CollapsedDeadlinePill: View {
    let deadlines: [CalendarEvent]
    @State private var show = false

    var body: some View {
        let color = deadlines.first?.color ?? AtlasTheme.Colors.danger
        Button { show.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill").font(.system(size: 7))
                Text("\(deadlines.count) due")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18)
            .background(AtlasTheme.wash(color), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            DeadlineListPopover(deadlines: deadlines)
        }
    }
}
