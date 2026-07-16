import SwiftUI
import AtlasCore

/// A month grid for jumping the Schedule to a day. Tapping a day previews that
/// day's items below the grid (it does not navigate); "Visit this day" commits the
/// jump via `onPick`. Reuses the shared `MonthGrid` date math. Default preview =
/// the day the Schedule is currently showing.
struct MonthPageView: View {
    let selected: Date
    let onPick: (Date) -> Void

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var month: Date
    /// The day being previewed below the grid — tapping a cell moves it, and only
    /// "Visit this day" navigates. Seeded to the Schedule's current day.
    @State private var pickedDay: Date

    private let cal = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _month = State(initialValue: selected)
        _pickedDay = State(initialValue: Calendar.current.startOfDay(for: selected))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            dayPreview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
    }

    // MARK: - Day preview (the tapped day's items + "Visit this day")

    private var dayPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
                .padding(.top, 16)

            Text(previewTitle)
                .edCapsLabel().textCase(nil)
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)

            let items = previewItems
            if items.isEmpty {
                Text("Nothing scheduled.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            previewRow(item)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                MobileTheme.Haptic.selection()
                onPick(pickedDay)
                dismiss()
            } label: {
                Text("Visit this day")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewRow(_ item: DayItem) -> some View {
        HStack(spacing: 12) {
            Text(item.time)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .frame(width: 62, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3, height: 18)
            Text(item.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MobileTheme.hairline).frame(height: 1).padding(.horizontal, 24)
        }
    }

    // MARK: - Preview data

    private struct DayItem: Identifiable {
        let id: UUID
        let sortMinute: Int
        let time: String
        let title: String
        let color: Color
    }

    /// The picked day's events (by start) + open tasks (scheduled or due), sorted by
    /// time. All-day events sort first; date-only due tasks sort last as "Due".
    /// Colored per space like the month dots.
    private var previewItems: [DayItem] {
        var items: [DayItem] = []
        for ev in store.snapshot.events where cal.isDate(ev.start, inSameDayAs: pickedDay) {
            items.append(DayItem(id: ev.id,
                                 sortMinute: ev.isAllDay ? -1 : minutesOf(ev.start),
                                 time: ev.isAllDay ? "All day" : timeLabel(ev.start),
                                 title: ev.title, color: ev.color))
        }
        for t in store.snapshot.tasks where !t.done {
            if let at = t.scheduledAt, cal.isDate(at, inSameDayAs: pickedDay) {
                items.append(DayItem(id: t.id, sortMinute: minutesOf(at),
                                     time: timeLabel(at), title: t.title, color: t.spaceColor))
            } else if let due = t.dueDate, cal.isDate(due, inSameDayAs: pickedDay) {
                let timed = hasClockTime(due)
                items.append(DayItem(id: t.id, sortMinute: timed ? minutesOf(due) : 2000,
                                     time: timed ? timeLabel(due) : "Due",
                                     title: t.title, color: t.spaceColor))
            }
        }
        return items.sorted { $0.sortMinute < $1.sortMinute }
    }

    private func minutesOf(_ date: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func hasClockTime(_ date: Date) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private func timeLabel(_ date: Date) -> String { Self.timeFormatter.string(from: date) }

    private static let previewTitleFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()
    private var previewTitle: String { Self.previewTitleFormatter.string(from: pickedDay) }

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
        let isSelected = cal.isDate(day, inSameDayAs: pickedDay)
        let isToday = cal.isDateInToday(day)
        return Button {
            MobileTheme.Haptic.selection()
            pickedDay = cal.startOfDay(for: day)
        } label: {
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
