import SwiftUI
import AtlasCore

/// A month grid for jumping the Schedule to a day. Pure navigation — reuses the
/// shared `MonthGrid` date math; tapping a day calls `onPick` (the caller pops
/// back to Schedule on that day).
struct MonthPageView: View {
    let selected: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var month: Date

    private let cal = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _month = State(initialValue: selected)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(monthTitle).edScreenTitle()
                Spacer()
                stepper
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(orderedWeekdays, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
                ForEach(MonthGrid.cells(for: month, calendar: cal), id: \.self) { day in
                    dayCell(day)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
    }

    private var stepper: some View {
        HStack(spacing: 22) {
            Button { shift(-1) } label: { chevron("chevron.left") }
            Button { shift(1) } label: { chevron("chevron.right") }
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MobileTheme.ink)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = MonthGrid.isInMonth(day, of: month, calendar: cal)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        return Button { onPick(cal.startOfDay(for: day)); dismiss() } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 16, weight: isToday ? .heavy : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(cellColor(inMonth: inMonth, isToday: isToday))
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule)
                            .frame(width: 38, height: 38)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func cellColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return MobileTheme.accentText }   // today = clay text
        return inMonth ? MobileTheme.ink : MobileTheme.faint
    }

    private var orderedWeekdays: [String] {
        // Rotate so the grid's first column matches the calendar's firstWeekday.
        let shift = cal.firstWeekday - 1
        return Array(weekdaySymbols[shift...] + weekdaySymbols[..<shift])
    }

    private static let monthTitleFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f }()

    private var monthTitle: String { Self.monthTitleFormatter.string(from: month) }

    private func shift(_ months: Int) {
        if let next = cal.date(byAdding: .month, value: months, to: month) { month = next }
    }
}
