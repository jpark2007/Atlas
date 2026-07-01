import SwiftUI

/// Sticky 7-day column header for the week grid.
/// Each cell shows a weekday short name above a day-number badge;
/// today's badge is filled with `AtlasTheme.Colors.accent`.
struct WeekColumnHeader: View {
    let days: [Date]
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalendarLayout.gutterWidth)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayCell(day)
                    .frame(width: columnWidth)
                if index < days.count - 1 {
                    Color.clear.frame(width: 1)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayNum  = Calendar.current.component(.day, from: day)
        return HStack(spacing: 4) {
            Text(CalendarFormat.weekdayShort.string(from: day).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(isToday ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            Text("\(dayNum)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isToday ? AtlasTheme.Colors.bgDeep : AtlasTheme.Colors.textPrimary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(isToday ? AtlasTheme.Colors.accent : .clear))
        }
    }
}
