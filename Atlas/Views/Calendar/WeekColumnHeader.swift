import SwiftUI

/// Sticky 7-day column header for the week grid.
/// Each cell shows a weekday short name above a day-number badge;
/// today's badge is filled with `AtlasTheme.Colors.accent`.
struct WeekColumnHeader: View {
    let days: [Date]
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Blank gutter spacer — keeps header cells aligned above hour gutter
            Color.clear.frame(width: CalendarLayout.gutterWidth)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayCell(day)
                    .frame(width: columnWidth)
                if index < days.count - 1 {
                    // 1 pt spacer mirrors the 1 pt column dividers in the grid below
                    Color.clear.frame(width: 1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayNum  = Calendar.current.component(.day, from: day)
        return VStack(spacing: 3) {
            Text(CalendarFormat.weekdayShort.string(from: day).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isToday ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            Text("\(dayNum)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isToday ? AtlasTheme.Colors.bgDeep : AtlasTheme.Colors.textPrimary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(isToday ? AtlasTheme.Colors.accent : .clear)
                )
        }
    }
}
