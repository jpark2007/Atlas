import SwiftUI
import AtlasCore

/// The outlined mini-month date navigator + the selected day's agenda — the
/// dashboard's right rail (locked Phase-3 mockup), extracted so the menu-bar
/// calendar popup can show the same instrument over any app.
///
/// `selectedDay` drives the agenda only; `visibleMonth` is which month the grid
/// pages. `onOpenCalendar` backs the FULL VIEW link; `agendaLimit` caps the
/// agenda rows (the popover sets it so a stacked day can't grow the popup
/// unbounded).
struct MiniMonthAgenda: View {
    @EnvironmentObject var state: AppState

    let onOpenCalendar: () -> Void
    var agendaLimit: Int? = nil

    /// Navigator selection — the agenda's day. Defaults to today.
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    /// Which month the mini-calendar grid shows (paged by the chevrons).
    @State private var visibleMonth: Date = Date()

    private let calendar = Calendar.current

    /// Live "today" — the menu-bar popup instance survives for the app's whole
    /// lifetime, so the selection must follow the date, not launch day.
    private var today: Date { calendar.startOfDay(for: state.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            miniCalendar
            agenda
        }
        // Midnight rollover: re-anchor the glance to the new day. Without this a
        // long-lived instance (the MenuBarExtra window) opens on yesterday.
        .onChange(of: today) { _, newToday in
            selectedDay = newToday
            visibleMonth = newToday
        }
    }

    // MARK: - Mini month calendar (the one outlined instrument container)

    private var miniCalendar: some View {
        VStack(spacing: 10) {
            calendarHeader
            weekdayHeader
            monthGrid
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1)
        )
    }

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            Text(MiniFmt.monthYear.string(from: visibleMonth).uppercased())
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.2)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            chevron("chevron.left")  { pageMonth(-1) }
                .help("Previous month")
            chevron("chevron.right") { pageMonth(1) }
                .help("Next month")
        }
    }

    private func chevron(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .atlasFont(size: 11, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pageMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = next
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .atlasMono(size: 9, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Single-letter weekday headers rotated to the locale's `firstWeekday`.
    private var orderedWeekdaySymbols: [String] {
        let syms = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private var monthGrid: some View {
        let cells = MonthGrid.cells(for: visibleMonth, calendar: calendar)
        // Unlike the full calendar (fixed 6-week height), the mini grid drops
        // trailing weeks that are pure next-month spill — one less row of days
        // for most months.
        let weeks = stride(from: 0, to: cells.count, by: 7)
            .map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }
            .filter { week in week.contains { MonthGrid.isInMonth($0, of: visibleMonth, calendar: calendar) } }
        let dots = dotDayStarts()
        return VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day, hasItems: dots.contains(calendar.startOfDay(for: day)))
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, hasItems: Bool) -> some View {
        let inMonth = MonthGrid.isInMonth(day, of: visibleMonth, calendar: calendar)
        let isToday = calendar.isDate(day, inSameDayAs: state.now)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)

        return ZStack {
            // today keeps the solid clay square; a non-today selection gets the outline.
            if isToday {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.accent)
                    .frame(width: 28, height: 28)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5)
                    .frame(width: 28, height: 28)
            }
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .atlasMono(size: 12, weight: (isToday || isSelected) ? .bold : .medium)
                    .foregroundStyle(
                        isToday ? AtlasTheme.Colors.bgBase
                                : (inMonth ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                    )
                Circle()
                    .fill(isToday ? AtlasTheme.Colors.bgBase : AtlasTheme.Colors.accent)
                    .frame(width: 4, height: 4)
                    .opacity(hasItems && inMonth ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(Rectangle())
        .onTapGesture { selectDay(day) }
    }

    /// Tapping a day drives the AGENDA (not the dashboard's focus list); it also
    /// snaps the grid to that day's month so a spilled adjacent-month day shows
    /// in-month.
    private func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !MonthGrid.isInMonth(day, of: visibleMonth, calendar: calendar) {
            visibleMonth = day
        }
    }

    /// The days that carry a dot: store events (Atlas/Google/Canvas), read-only
    /// Apple externals, scheduled work-blocks, or an open task deadline — the same
    /// master feed the full calendar draws (mirrors `events(on:)` +
    /// `externalEvents(on:)` + `scheduledWorkBlocks(on:)` +
    /// `CalendarView.deadlineEvents`). One pass over the collections per render
    /// instead of one per grid cell.
    private func dotDayStarts() -> Set<Date> {
        var days = Set<Date>()
        for event in state.events { days.insert(calendar.startOfDay(for: event.start)) }
        for event in state.externalEvents { days.insert(calendar.startOfDay(for: event.start)) }
        for task in state.tasks where !task.done {
            if let at = task.scheduledAt, !task.needsReplan(now: state.now) {
                days.insert(calendar.startOfDay(for: at))
            }
            if let due = task.dueDate { days.insert(calendar.startOfDay(for: due)) }
        }
        return days
    }

    // MARK: - Agenda (the selected day's events + work-blocks)

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(agendaLabel).atlasCapsLabel()
                if !isViewingToday {
                    Button { selectedDay = calendar.startOfDay(for: state.now) } label: {
                        Text("← TODAY")
                            .atlasMono(size: 10, weight: .semibold)
                            .tracking(0.8)
                            .foregroundStyle(AtlasTheme.Colors.accentText)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onOpenCalendar) {
                    HStack(spacing: 4) {
                        Text("FULL VIEW")
                            .atlasMono(size: 10, weight: .semibold)
                            .tracking(0.8)
                        Image(systemName: "chevron.right")
                            .atlasFont(size: 9, weight: .semibold)
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }

            let items = agendaItems
            let shown = agendaLimit.map { Array(items.prefix($0)) } ?? items
            if items.isEmpty {
                Text("Nothing scheduled.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { item in agendaRow(item) }
                    if items.count > shown.count {
                        Text("+ \(items.count - shown.count) MORE")
                            .atlasMono(size: 10, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var isViewingToday: Bool {
        calendar.isDate(selectedDay, inSameDayAs: state.now)
    }

    /// "TODAY" for today, else the navigated day ("THU, JUL 9").
    private var agendaLabel: String {
        isViewingToday ? "TODAY" : MiniFmt.agendaDay.string(from: selectedDay).uppercased()
    }

    /// The selected day's master feed — store events (Atlas/Google/Canvas) +
    /// scheduled work-blocks + read-only Apple externals — in time order, exactly
    /// what the full calendar composes. Each row keeps its own source color and
    /// attribution (externals stay Apple/read-only); merging never relabels them.
    private var agendaItems: [CalendarEvent] {
        (state.events(on: selectedDay)
            + state.scheduledWorkBlocks(on: selectedDay)
            + state.externalEvents(on: selectedDay))
            .sorted { $0.start < $1.start }
    }

    private func agendaRow(_ event: CalendarEvent) -> some View {
        // "now" applies only while viewing today and the event is in progress.
        let isNow = isViewingToday && event.start <= state.now && state.now < event.end
        return HStack(spacing: 10) {
            Text(event.timeLabel)
                .atlasMono(size: 11, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 52, alignment: .leading)
            Circle()
                .fill(event.color)
                .frame(width: 7, height: 7)
            Text(event.title)
                .atlasFont(size: 14, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isNow {
                Text("NOW")
                    .atlasMono(size: 10, weight: .bold)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            } else {
                Text(event.durationLabel)
                    .atlasMono(size: 11, weight: .regular)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            isNow ? AtlasTheme.wash(AtlasTheme.Colors.accent) : .clear,
            in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
        )
    }
}

/// Cached `DateFormatter`s for the navigator's mono labels.
private enum MiniFmt {
    static let monthYear = formatter("MMMM yyyy")
    static let agendaDay = formatter("EEE, MMM d")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = pattern
        return f
    }
}
