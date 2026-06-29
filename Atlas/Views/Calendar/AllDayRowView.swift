import SwiftUI

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
                Color.clear.frame(width: CalendarLayout.gutterWidth)
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    allDayCell(for: day)
                        .frame(width: columnWidth, height: CalendarLayout.allDayRowHeight)
                        .clipped()
                    if index < days.count - 1 {
                        Color.clear.frame(width: 1)
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
        VStack(spacing: 2) {
            ForEach(events) { event in
                if event.isDeadline {
                    // Deadline → flag-pill (matches the day-view DUE strip), red when overdue.
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill").font(.system(size: 7))
                        Text(event.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(event.color)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .background(Capsule().fill(event.color.opacity(0.12)))
                    .overlay(Capsule().stroke(event.color.opacity(0.45), lineWidth: 1))
                } else {
                    Text(event.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 18)
                        .background(event.color.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }
}
