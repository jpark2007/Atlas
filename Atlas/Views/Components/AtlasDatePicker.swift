import SwiftUI
import AtlasCore

/// The editorial date + time picker — the themed replacement for the stock
/// `.graphical` `DatePicker`, whose white well, blue selection and analogue
/// clock face are the one place system chrome punches through the paper.
///
/// Speaks the dashboard mini-month's language: mono month title, mono weekday
/// headers, mono day cells, a clay square for the selected day, flat paper and
/// ink hairlines — just sized for a sheet rather than a sidebar. Time is the
/// themed `atlasDateField` at hour/minute only.
///
/// The binding is optional so "no date" is a first-class, labelled choice
/// rather than a bare Clear link parked next to Cancel.
struct AtlasDatePicker: View {
    @Binding var date: Date?
    /// Show the hour/minute row. False renders date-only.
    var includesTime: Bool = true
    /// Copy for the row that clears the date. `nil` hides that row, for the
    /// surfaces where an item must keep a date (an event, say).
    var clearLabel: String? = "No due date"

    @State private var visibleMonth: Date

    private let calendar = Calendar.current

    init(date: Binding<Date?>, includesTime: Bool = true, clearLabel: String? = "No due date") {
        _date = date
        self.includesTime = includesTime
        self.clearLabel = clearLabel
        _visibleMonth = State(initialValue: date.wrappedValue ?? Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            monthGrid
            Divider().overlay(AtlasTheme.Colors.hairline)
            if includesTime { timeRow }
            if let clearLabel { clearRow(clearLabel) }
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1)
        )
    }

    // MARK: - Month navigation

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(AtlasDatePickerFmt.monthYear.string(from: visibleMonth).uppercased())
                .atlasMono(size: 12, weight: .semibold)
                .tracking(1.2)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            chevron("chevron.left") { pageMonth(-1) }
                .help("Previous month")
            chevron("chevron.right") { pageMonth(1) }
                .help("Next month")
        }
    }

    private func chevron(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .atlasFont(size: 12, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pageMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = next
        }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .atlasMono(size: 10, weight: .semibold)
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

    /// Fixed six weeks — a picker that changes height as you page makes the
    /// sheet it sits in jump under the cursor.
    private var monthGrid: some View {
        let cells = MonthGrid.cells(for: visibleMonth, calendar: calendar)
        let weeks = stride(from: 0, to: cells.count, by: 7)
            .map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }
        return VStack(spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in dayCell(day) }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = MonthGrid.isInMonth(day, of: visibleMonth, calendar: calendar)
        let isSelected = date.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        let isToday = calendar.isDateInToday(day)

        return ZStack {
            // The selection is the act here, so it takes the solid clay square;
            // today keeps the quieter outline (the mini-month has it the other
            // way round, where nothing is being chosen).
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AtlasTheme.Colors.accent)
                    .frame(width: 32, height: 32)
            } else if isToday {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1.5)
                    .frame(width: 32, height: 32)
            }
            Text("\(calendar.component(.day, from: day))")
                .atlasMono(size: 13, weight: (isSelected || isToday) ? .bold : .medium)
                .foregroundStyle(
                    isSelected ? AtlasTheme.Colors.bgBase
                               : (inMonth ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                )
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture { select(day) }
    }

    /// Picking a day keeps whatever time was already set, so tapping around the
    /// grid never silently moves a 5pm deadline to midnight.
    private func select(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: date ?? Date())
        date = calendar.date(bySettingHour: time.hour ?? 9,
                             minute: time.minute ?? 0,
                             second: 0,
                             of: day)
        visibleMonth = day
    }

    // MARK: - Time and clear

    private var timeRow: some View {
        HStack {
            Text("Time").atlasCapsLabel()
            Spacer()
            DatePicker("", selection: Binding(
                get: { date ?? Date() },
                set: { date = $0 }
            ), displayedComponents: .hourAndMinute)
            .atlasDateField()
            .fixedSize()
            .disabled(date == nil)
            .opacity(date == nil ? 0.4 : 1)
        }
    }

    private func clearRow(_ label: String) -> some View {
        Button { date = nil } label: {
            HStack(spacing: 8) {
                Image(systemName: date == nil ? "largecircle.fill.circle" : "circle")
                    .atlasFont(size: 12, weight: .medium)
                    .foregroundStyle(date == nil ? AtlasTheme.Colors.accentText
                                                 : AtlasTheme.Colors.textMuted)
                Text(label)
                    .atlasFont(size: 13, weight: date == nil ? .semibold : .medium, design: .rounded)
                    .foregroundStyle(date == nil ? AtlasTheme.Colors.textPrimary
                                                 : AtlasTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Cached `DateFormatter` for the picker's mono month label.
private enum AtlasDatePickerFmt {
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
