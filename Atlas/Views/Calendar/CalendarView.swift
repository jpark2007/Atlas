import SwiftUI

/// The Atlas Calendar — the hero screen. Day / Week time grid with a space
/// filter and a drag-to-schedule tray of unscheduled tasks. Reads/writes the
/// shared `AppState` store (`events`, `unscheduledTasks`, `schedule(taskId:at:)`).
struct CalendarView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var mode: CalendarMode = .day
    @State private var spaceFilter: String = "All"

    // MARK: - Apple Calendar sync
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    private let ekService = EventKitService()

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

                UnscheduledTray(
                    tasks: state.unscheduledTasks,
                    spaceFilter: spaceFilter,
                    onSchedule: { taskID, hour in
                        schedule(taskID: taskID, on: selectedDate, hour: Double(hour))
                    },
                    onSuggest: suggestSlot(for:),
                    onSetDueDate: { taskID, date in
                        state.setDueDate(taskId: taskID, date: date)
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { loadAppleEventsIfNeeded() }
        .onChange(of: selectedDate) { _, _ in loadAppleEventsIfNeeded() }
        .onChange(of: mode) { _, _ in loadAppleEventsIfNeeded() }
        .onChange(of: appleCalendarEnabled) { _, enabled in
            if enabled {
                Task {
                    _ = await ekService.requestAccess()
                    await MainActor.run { loadAppleEventsIfNeeded() }
                }
            } else { state.externalEvents = [] }
        }
        .sheet(isPresented: $state.presentEventEditor, onDismiss: {
            state.eventEditorSeed = nil
        }) {
            if let seed = state.eventEditorSeed {
                EventEditorSheet(seed: seed)
                    .environmentObject(state)
            }
        }
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
                addEventButton
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

    private var addEventButton: some View {
        Button {
            openEditorForNewEvent(on: selectedDate)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add event")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AtlasTheme.Colors.accent)
            .foregroundStyle(AtlasTheme.Colors.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
                onDropTask: handleDrop,
                onTapEmpty: handleTapEmpty,
                onTapEvent: openSource(for:)
            )
        case .week:
            WeekGridView(
                days: weekDays,
                eventsProvider: { filteredEvents(on: $0) },
                onDropTask: handleDrop,
                onTapEmpty: handleTapEmpty,
                onTapEvent: openSource(for:)
            )
        }
    }

    // MARK: - Data (real source of truth)

    /// Space-filtered events for a day: the store's events plus a tile for any
    /// task already dropped onto that day (`scheduledAt`), plus read-only
    /// external events (Apple Calendar) when enabled.
    private func filteredEvents(on date: Date) -> [CalendarEvent] {
        let all = state.events(on: date)
            + scheduledTaskEvents(on: date)
            + state.externalEvents(on: date)
        guard spaceFilter != "All" else { return all }
        return all.filter { $0.spaceName == spaceFilter }
    }

    /// Tasks that have been dropped onto `date`, rendered as 1-hour blocks so
    /// drag-to-schedule shows immediate, satisfying feedback on the grid.
    private func scheduledTaskEvents(on date: Date) -> [CalendarEvent] {
        state.tasks.compactMap { task in
            // Tasks whose slot has elapsed without completion resurface in the
            // tray and must drop off the grid (non-destructive revert-after-slot).
            guard !task.isEffectivelyUnscheduled(now: state.now),
                  let at = task.scheduledAt,
                  Calendar.current.isDate(at, inSameDayAs: date) else { return nil }
            let end = Calendar.current.date(byAdding: .minute, value: task.durationMin ?? 60, to: at) ?? at
            return CalendarEvent(
                id: task.id,                       // stable identity → no per-render flicker
                title: task.title,
                subtitle: "Scheduled",
                start: at,
                end: end,
                color: task.spaceColor,
                spaceName: task.spaceName           // direct, not a fragile Color reverse-map
            )
        }
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [selectedDate] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    // MARK: - Apple Calendar aggregation

    /// Fetches Apple Calendar events for the visible range and stores them in
    /// `state.externalEvents`. Called on appear, on `selectedDate` change, and
    /// when the toggle flips on. Apple events NEVER enter `state.events`.
    private func loadAppleEventsIfNeeded() {
        guard appleCalendarEnabled else {
            state.externalEvents = []
            return
        }
        let status = ekService.authorizationStatus()
        guard status == .fullAccess else {
            state.externalEvents = []
            return
        }

        let cal = Calendar.current
        // Fetch a single day in day mode; the full visible week in week mode.
        let rangeStart: Date
        let rangeEnd: Date
        switch mode {
        case .day:
            rangeStart = cal.startOfDay(for: selectedDate)
            rangeEnd   = cal.date(byAdding: .day, value: 1, to: rangeStart) ?? rangeStart
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return }
            rangeStart = interval.start
            rangeEnd   = interval.end
        }

        let defaultSpace = appleDefaultSpace.isEmpty
            ? (state.spaces.first?.name ?? "")
            : appleDefaultSpace

        Task {
            let fetched = await ekService.fetchEvents(
                start: rangeStart,
                end:   rangeEnd,
                defaultSpaceName: defaultSpace
            )
            await MainActor.run {
                state.externalEvents = fetched
            }
        }
    }

    // MARK: - Scheduling

    /// Drop callback from the grid (hour is fractional from the drop location).
    private func handleDrop(taskID: UUID, date: Date, hour: Double) -> Bool {
        schedule(taskID: taskID, on: date, hour: hour)
    }

    /// Auto-find-a-slot: scan the selected day for the first free gap that fits
    /// the task and schedule it there. No-op if the task is gone or the day's full.
    private func suggestSlot(for taskID: UUID) {
        guard let task = state.tasks.first(where: { $0.id == taskID }),
              let slot = state.suggestSlot(for: task, on: selectedDate, now: Date()) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            state.schedule(taskId: taskID, at: slot)
        }
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

    // MARK: - Event editor helpers

    /// Presents the editor seeded with a new 1-hour event at the next round
    /// hour on `date`. The "+ Add event" button calls this with `selectedDate`.
    private func openEditorForNewEvent(on date: Date) {
        let cal = Calendar.current
        let now = Date()
        let currentHour = cal.component(.hour, from: now)
        let nextHour = min(max(currentHour + 1, CalendarLayout.startHour), CalendarLayout.endHour - 1)
        let start = cal.date(bySettingHour: nextHour, minute: 0, second: 0, of: date) ?? date
        let end   = cal.date(byAdding: .hour, value: 1, to: start) ?? start

        let spaceName = state.spaces.first?.name ?? ""
        let color     = state.calendarSpaceColor(named: spaceName)

        state.eventEditorSeed = CalendarEvent(
            title: "",
            subtitle: "",
            start: start,
            end: end,
            color: color,
            spaceName: spaceName
        )
        state.presentEventEditor = true
    }

    /// Called by `DayColumnView` when the user taps an empty grid area.
    /// Converts the fractional `hour` into a concrete `Date` on `date`, snaps
    /// to 15-minute increments, and opens the editor pre-filled.
    private func handleTapEmpty(date: Date, hour: Double) {
        let cal = Calendar.current
        let clamped = min(max(hour, Double(CalendarLayout.startHour)), Double(CalendarLayout.endHour) - 0.25)
        let h = Int(clamped)
        let minute = (Int((clamped - Double(h)) * 60) / 15) * 15
        guard let start = cal.date(bySettingHour: h, minute: minute, second: 0, of: date) else { return }
        let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start

        let spaceName = state.spaces.first?.name ?? ""
        let color     = state.calendarSpaceColor(named: spaceName)

        state.eventEditorSeed = CalendarEvent(
            title: "",
            subtitle: "",
            start: start,
            end: end,
            color: color,
            spaceName: spaceName
        )
        state.presentEventEditor = true
    }

    // MARK: - Source navigation

    /// Left-click / "Open Source" resolver.
    ///
    /// If the event is linked to a project that still exists, navigates the
    /// sidebar to `.project(id)`. Otherwise falls back to opening the editor
    /// so a click on any tile is never a dead end.
    func openSource(for event: CalendarEvent) {
        // Read-only external events (e.g. Apple Calendar) — never open the editor.
        guard !event.isReadOnly else { return }

        // Task-derived synthetic events share their UUID with the underlying TaskItem.
        // Opening the editor for them would create a ghost-duplicate CalendarEvent in
        // state.events — guard against that here.
        if state.tasks.contains(where: { $0.id == event.id }) {
            // task-derived synthetic event — no project source, don't open the event editor (would create a ghost duplicate)
            return
        }
        if let projectID = event.projectID, state.project(projectID) != nil {
            state.route = .project(projectID)
        } else {
            state.eventEditorSeed = event
            state.presentEventEditor = true
        }
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
