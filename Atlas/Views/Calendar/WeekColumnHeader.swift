import SwiftUI
import AtlasCore

/// Sticky 7-day column header for the week grid.
/// Each cell shows a weekday short name above a day number; today reads in clay
/// text (accent = graphics/brand only — never a filled badge).
struct WeekColumnHeader: View {
    let days: [Date]
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Blank gutter spacer — keeps header cells aligned above hour gutter.
            // +6 mirrors HourGutter's trailing padding; height 0 so the spacer
            // never stretches the header row vertically (it's width-only).
            Color.clear.frame(width: CalendarLayout.gutterWidth + 6, height: 0)
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayCell(day)
                    .frame(width: columnWidth)
                if index < days.count - 1 {
                    // 1 pt spacer mirrors the 1 pt column dividers in the grid below
                    Color.clear.frame(width: 1, height: 0)
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
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(isToday ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
            Text("\(dayNum)")
                .font(.system(size: 15, weight: isToday ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(isToday ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textPrimary)
                .frame(width: 26, height: 26)
        }
    }
}
