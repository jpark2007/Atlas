import SwiftUI
import AtlasCore

/// A 6-week (6×7) month grid modeled on Image #1. Each day cell shows the day
/// number (today highlighted, out-of-month days dimmed) and up to `maxChips`
/// event chips with a "+k" overflow indicator. Tapping a day asks the parent to
/// switch to the Day view for that date.
///
/// The grid geometry comes from the pure, unit-tested `MonthGrid` helper; this
/// view is presentation only. Events are pulled per-day from `eventsProvider`,
/// which already has the calendar's space/category/search filters applied.
struct MonthGridView: View {
    /// Any day in the month to display.
    let monthDate: Date
    /// Observed "now" so the today highlight refreshes as the day rolls over.
    let now: Date
    /// Filtered events for a given day (same provider the time grid uses).
    let eventsProvider: (Date) -> [CalendarEvent]
    /// Tap a day → parent switches to Day view for it.
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    private let maxChips = 3

    private var cells: [Date] { MonthGrid.cells(for: monthDate, calendar: calendar) }
    private var weeks: [[Date]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Divider().overlay(AtlasTheme.Colors.border)
            GeometryReader { geo in
                let rowH = max(64, geo.size.height / 6)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            HStack(spacing: 0) {
                                ForEach(week, id: \.self) { day in
                                    dayCell(day, height: rowH)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Instrument-container language (matches the dashboard mini-month, P3-1):
        // the whole month reads as one outlined box — a hairline-stroked rounded
        // container, its grid lines clipped to the rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1)
        )
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.prefix(7)), id: \.self) { day in
                Text(CalendarFormat.weekdayShort.string(from: day).uppercased())
                    .atlasCapsLabel()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Day cell

    private func dayCell(_ day: Date, height: CGFloat) -> some View {
        let inMonth = MonthGrid.isInMonth(day, of: monthDate, calendar: calendar)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let events = eventsProvider(day)

        return VStack(alignment: .leading, spacing: 3) {
            dayNumber(day, inMonth: inMonth, isToday: isToday)

            ForEach(events.prefix(maxChips)) { event in
                chip(event)
            }
            if events.count > maxChips {
                Text("+\(events.count - maxChips) more")
                    .atlasMono(size: 9, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AtlasTheme.Colors.border).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AtlasTheme.Colors.border).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(day) }
    }

    private func dayNumber(_ day: Date, inMonth: Bool, isToday: Bool) -> some View {
        let number = "\(calendar.component(.day, from: day))"
        return Text(number)
            .atlasMono(size: 11.5, weight: isToday ? .heavy : .medium)
            .foregroundStyle(
                isToday ? AtlasTheme.Colors.accentText
                        : (inMonth ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
            )
            .frame(width: 20, height: 20)
            .opacity(inMonth || isToday ? 1 : 0.55)
    }

    private func chip(_ event: CalendarEvent) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(event.isReadOnly ? AtlasTheme.Colors.textSecondary : event.color)
                .frame(width: 5, height: 5)
            Text(event.title)
                .atlasFont(size: 10, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            AtlasTheme.wash(event.isReadOnly ? AtlasTheme.Colors.textSecondary : event.color),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
    }
}
