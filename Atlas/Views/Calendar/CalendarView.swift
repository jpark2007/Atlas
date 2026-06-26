import SwiftUI

/// The Atlas Calendar — the hero screen. Day / Week time grid with a space
/// filter and a drag-to-schedule tray of unscheduled tasks. Reads/writes the
/// shared `AppState` store (`events`, `unscheduledTasks`, `schedule(taskId:at:)`).
struct CalendarView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var mode: CalendarMode = .day
    @State private var spaceFilter: String = "All"

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider().overlay(AtlasTheme.Colors.border)

            HStack(alignment: .top, spacing: 18) {
                grid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                UnscheduledTray(tasks: state.unscheduledTasks) { taskID, hour in
                    schedule(taskID: taskID, on: selectedDate, hour: Double(hour))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALENDAR")
                        .font(AtlasTheme.Font.kicker())
                        .tracking(1.4)
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text(titleLabel)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                Spacer()
                navigationControls
            }

            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    ForEach(CalendarMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()

                spaceFilterMenu
                Spacer()
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)

            Button { selectedDate = Calendar.current.startOfDay(for: Date()) } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AtlasTheme.Colors.accent.opacity(0.14))
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private var spaceFilterMenu: some View {
        Menu {
            Button("All") { spaceFilter = "All" }
            Divider()
            ForEach(state.spaces) { space in
                Button {
                    spaceFilter = space.name
                } label: {
                    Label(space.name, systemImage: spaceFilter == space.name ? "checkmark" : "circle.fill")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(spaceFilter == "All" ? AtlasTheme.Colors.textMuted : state.calendarSpaceColor(named: spaceFilter))
                    .frame(width: 8, height: 8)
                Text(spaceFilter)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        switch mode {
        case .day:
            DayCalendarView(
                date: selectedDate,
                events: filteredEvents(on: selectedDate),
                onDropTask: handleDrop
            )
        case .week:
            WeekGridView(
                days: weekDays,
                eventsProvider: { filteredEvents(on: $0) },
                onDropTask: handleDrop
            )
        }
    }

    // MARK: - Data (real source of truth)

    /// Space-filtered events for a day: the store's events plus a tile for any
    /// task already dropped onto that day (`scheduledAt`).
    private func filteredEvents(on date: Date) -> [CalendarEvent] {
        let all = state.events(on: date) + scheduledTaskEvents(on: date)
        guard spaceFilter != "All" else { return all }
        return all.filter { $0.spaceName == spaceFilter }
    }

    /// Tasks that have been dropped onto `date`, rendered as 1-hour blocks so
    /// drag-to-schedule shows immediate, satisfying feedback on the grid.
    private func scheduledTaskEvents(on date: Date) -> [CalendarEvent] {
        state.tasks.compactMap { task in
            guard let at = task.scheduledAt,
                  Calendar.current.isDate(at, inSameDayAs: date) else { return nil }
            let end = Calendar.current.date(byAdding: .minute, value: 60, to: at) ?? at
            return CalendarEvent(
                title: task.title,
                subtitle: "Scheduled",
                start: at,
                end: end,
                color: task.spaceColor,
                spaceName: state.calendarSpaceName(matching: task.spaceColor)
            )
        }
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [selectedDate] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    // MARK: - Scheduling

    /// Drop callback from the grid (hour is fractional from the drop location).
    private func handleDrop(taskID: UUID, date: Date, hour: Double) -> Bool {
        schedule(taskID: taskID, on: date, hour: hour)
    }

    @discardableResult
    private func schedule(taskID: UUID, on date: Date, hour: Double) -> Bool {
        guard state.unscheduledTasks.contains(where: { $0.id == taskID }) else { return false }
        let cal = Calendar.current

        // Clamp into the visible range and snap to 15-minute increments.
        let clamped = min(max(hour, Double(CalendarLayout.startHour)), Double(CalendarLayout.endHour) - 0.25)
        let h = Int(clamped)
        let minute = (Int((clamped - Double(h)) * 60) / 15) * 15
        guard let dropped = cal.date(bySettingHour: h, minute: minute, second: 0, of: date) else { return false }

        withAnimation(.easeOut(duration: 0.2)) {
            state.schedule(taskId: taskID, at: dropped)
        }
        return true
    }

    // MARK: - Header helpers

    private var titleLabel: String {
        switch mode {
        case .day:
            if Calendar.current.isDateInToday(selectedDate) {
                return "Today · " + CalendarFormat.fullDay.string(from: selectedDate)
            }
            return CalendarFormat.fullDay.string(from: selectedDate)
        case .week:
            return CalendarFormat.monthYear.string(from: selectedDate)
        }
    }

    private func shift(by amount: Int) {
        let cal = Calendar.current
        let component: Calendar.Component = mode == .day ? .day : .weekOfYear
        if let next = cal.date(byAdding: component, value: amount, to: selectedDate) {
            selectedDate = cal.startOfDay(for: next)
        }
    }
}
