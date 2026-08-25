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
    /// Jump the calendar to a day in Day view — the due-count cap's click target.
    var onJumpToDay: (Date) -> Void = { _ in }

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
        // A day fully in the past dims its all-day items.
        let isPastDay = Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: now)
        VStack(spacing: 2) {
            // Per-day DUE COUNT CAP. A count + jump target, never a "+N more" collapse:
            // every due still draws its own hairline marker down in the column (the markers
            // are the source of truth). The cap only says HOW MANY and takes you to the day.
            if !deadlines.isEmpty {
                DueCountCap(deadlines: deadlines, onJump: { onJumpToDay(day) })
            }
            ForEach(others) { event in
                Text(event.title)
                    .atlasFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .background(AtlasTheme.wash(event.color), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(isPastDay ? 0.65 : 1)
            }
        }
    }

}

/// The week view's per-day DUE COUNT CAP: "3 due" at the top of a column.
///
/// A cap is NOT a "+N more" collapse — nothing is hidden behind it. Every due keeps its own
/// hairline marker inside the column; the cap is a glanceable count and a jump target.
/// Clicking opens that day; right-click lists what's due without leaving the week.
/// Class-colored when the whole day belongs to one space, muted ink when it's mixed — color
/// always says WHOSE, never what state.
struct DueCountCap: View {
    let deadlines: [CalendarEvent]
    let onJump: () -> Void
    @State private var showList = false

    private var capColor: Color {
        Set(deadlines.map(\.spaceName)).count == 1
            ? (deadlines.first?.color ?? AtlasTheme.Colors.textSecondary)
            : AtlasTheme.Colors.textSecondary
    }

    var body: some View {
        Button(action: onJump) {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill").atlasFont(size: 8)
                Text("\(deadlines.count) due")
                    .atlasMono(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(capColor)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18)
            .background(AtlasTheme.wash(capColor), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open this day")
        .contextMenu { Button("See what's due") { showList = true } }
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            DeadlineListPopover(deadlines: deadlines)
        }
    }
}
