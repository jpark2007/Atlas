import SwiftUI
import AtlasCore

/// Sticky 7-day column header for the week grid.
/// Each cell is columnar: a tiny mono weekday next to a serif day number on the
/// left, and a compact outlined "N DUE" pill on the right for days that carry
/// deadlines. Today reads in clay text (accent = graphics/brand only — never a
/// filled badge).
struct WeekColumnHeader: View {
    let days: [Date]
    let columnWidth: CGFloat
    /// Number of deadlines due on a given day — drives the "N DUE" pill.
    let deadlineCount: (Date) -> Int

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
                    // 1 pt divider mirrors the grid's column dividers, so the header
                    // reads as columns rather than a loose row of labels.
                    Rectangle()
                        .fill(AtlasTheme.Colors.border)
                        .frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayNum  = Calendar.current.component(.day, from: day)
        let dues    = deadlineCount(day)
        return HStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(CalendarFormat.weekdayShort.string(from: day).uppercased())
                    .atlasMono(size: 10, weight: .bold)
                    .foregroundStyle(isToday ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
                Text("\(dayNum)")
                    .atlasTitleSerif(size: 15)
                    .foregroundStyle(isToday ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textPrimary)
            }
            Spacer(minLength: 0)
            if dues > 0 {
                Text("\(dues) DUE")
                    .atlasMono(size: 9, weight: .bold)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
