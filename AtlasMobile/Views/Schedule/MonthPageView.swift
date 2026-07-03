import SwiftUI
import AtlasCore

/// A month grid for jumping the Schedule to a day. Pure navigation — reuses the
/// shared `MonthGrid` date math; tapping a day calls `onPick` (the caller pops
/// back to Schedule on that day).
struct MonthPageView: View {
    let selected: Date
    let onPick: (Date) -> Void

    @EnvironmentObject private var store: MobileStore
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
            Button { month = Date() } label: {
                Text("Today")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
            }
            .buttonStyle(.plain)
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
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 16, weight: isToday ? .heavy : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(cellColor(inMonth: inMonth, isToday: isToday))
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule)
                                .frame(width: 38, height: 38)
                        }
                    }
                dotRow(for: day)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    /// Up to 3 distinct space-color dots for the day, a faint 4th when there's more.
    private func dotRow(for day: Date) -> some View {
        let colors = dotColors(for: day)
        return HStack(spacing: 3) {
            ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, c in
                Circle().fill(c).frame(width: 4, height: 4)
            }
            if colors.count > 3 {
                Circle().fill(MobileTheme.faint.opacity(0.5)).frame(width: 4, height: 4)
            }
        }
        .frame(height: 4)
    }

    /// Distinct space colors of the day's events (by start) + tasks (by scheduledAt
    /// or dueDate), deduped by space name in encounter order.
    private func dotColors(for day: Date) -> [Color] {
        var seen: Set<String> = []
        var colors: [Color] = []
        func add(_ name: String, _ color: Color) {
            if seen.insert(name.lowercased()).inserted { colors.append(color) }
        }
        for ev in store.snapshot.events where cal.isDate(ev.start, inSameDayAs: day) {
            add(ev.spaceName, ev.color)
        }
        for t in store.snapshot.tasks where !t.done {
            if let at = t.scheduledAt, cal.isDate(at, inSameDayAs: day) { add(t.spaceName, t.spaceColor) }
            else if let due = t.dueDate, cal.isDate(due, inSameDayAs: day) { add(t.spaceName, t.spaceColor) }
        }
        return colors
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
