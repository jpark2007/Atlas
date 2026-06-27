import SwiftUI

/// The Atlas Calendar — the hero screen. Day / Week time grid with a space
/// filter and a drag-to-schedule tray of unscheduled tasks. Reads/writes the
/// shared `AppState` store (`events`, `unscheduledTasks`, `schedule(taskId:at:)`).
struct CalendarView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var mode: CalendarMode = .day
    @State private var spaceFilter: String = "All"

    /// In-calendar title search; empty = no search filter.
    @State private var searchText: String = ""
    /// Space names hidden via the color/category filter row. Empty = show all.
    @State private var hiddenSpaces: Set<String> = []

    // MARK: - Apple Calendar sync
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    private let ekService = EventKitService()

    // MARK: - Google Calendar sync
    @EnvironmentObject private var googleAuth: GoogleAuthService
    @AppStorage("calendar.google.enabled") private var googleCalendarEnabled: Bool = false

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
            } else { loadAppleEventsIfNeeded() }
        }
        .onChange(of: googleCalendarEnabled) { _, _ in loadAppleEventsIfNeeded() }
        .onChange(of: googleAuth.isConnected) { _, _ in loadAppleEventsIfNeeded() }
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
                .frame(width: 280)
                .labelsHidden()

                spaceFilterMenu
                Spacer()
                searchField
            }

            categoryFilterRow
        }
    }

    /// In-calendar title search. Filters events/tasks across every view.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(width: 150)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
        )
        .fixedSize()
    }

    /// Color/category filter (Image #1): a row of toggleable space-color chips.
    /// Tapping a chip hides/shows that space across every view. Reuses space
    /// colors as the categories (per spec — additive tags come later).
    @ViewBuilder
    private var categoryFilterRow: some View {
        if state.spaces.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.spaces) { space in
                        categoryChip(space)
                    }
                }
            }
        }
    }

    private func categoryChip(_ space: Space) -> some View {
        let isHidden = hiddenSpaces.contains(space.name)
        return Button {
            if isHidden { hiddenSpaces.remove(space.name) }
            else { hiddenSpaces.insert(space.name) }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isHidden ? AtlasTheme.Colors.textMuted.opacity(0.4) : space.color)
                    .frame(width: 8, height: 8)
                Text(space.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHidden ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    .strikethrough(isHidden, color: AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (isHidden ? Color.clear : space.color.opacity(0.12))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isHidden ? AtlasTheme.Colors.border : space.color.opacity(0.4),
                    lineWidth: 1
                )
            )
            .opacity(isHidden ? 0.6 : 1)
        }
        .buttonStyle(.plain)
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
        case .month:
            MonthGridView(
                monthDate: selectedDate,
                now: state.now,
                eventsProvider: { filteredEvents(on: $0) },
                onSelectDay: { day in
                    selectedDate = Calendar.current.startOfDay(for: day)
                    mode = .day
                }
            )
        case .list:
            AgendaListView(
                sections: agendaSections,
                now: state.now,
                onSelect: handleAgendaSelect
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
        return all.filter { passesFilters($0.spaceName, title: $0.title) }
    }

    /// Shared filter gate for both events and tasks: the single-space dropdown,
    /// the color/category hide-row, and the in-calendar title search.
    private func passesFilters(_ spaceName: String, title: String) -> Bool {
        if spaceFilter != "All" && spaceName != spaceFilter { return false }
        if hiddenSpaces.contains(spaceName) { return false }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty && !title.localizedCaseInsensitiveContains(q) { return false }
        return true
    }

    // MARK: - Agenda (List mode)

    /// Filtered, day-grouped agenda for the List view. Pulls the store's events +
    /// read-only external events + dated tasks, applies the same filters as the
    /// grid, then orders them via the pure `AgendaBuilder`.
    private var agendaSections: [AgendaSection] {
        let events = (state.events + state.externalEvents)
            .filter { passesFilters($0.spaceName, title: $0.title) }
        let tasks = state.tasks
            .filter { !$0.done && passesFilters($0.spaceName, title: $0.title) }
        return AgendaBuilder.build(
            events: events,
            tasks: tasks,
            from: selectedDate,
            now: state.now
        )
    }

    /// Tapping an agenda row: events open their source; tasks jump to the Day
    /// view on the task's date so it can be rescheduled / inspected.
    private func handleAgendaSelect(_ item: AgendaItem) {
        switch item.kind {
        case .event:
            if let event = (state.events + state.externalEvents).first(where: { $0.id == item.id }) {
                openSource(for: event)
            }
        case .task:
            selectedDate = Calendar.current.startOfDay(for: item.date)
            mode = .day
        }
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

    // MARK: - External calendar aggregation (Apple + Google)

    /// Fetches external events for the visible range and stores them in
    /// `state.externalEvents`. Aggregates Apple Calendar (read-only EventKit) and
    /// Google Calendar (read via `GoogleCalendarService`) — whichever are enabled
    /// and authorized. Called on appear, on `selectedDate`/`mode` change, and when
    /// a source toggles. External events NEVER enter `state.events`.
    private func loadAppleEventsIfNeeded() {
        let wantApple = appleCalendarEnabled && ekService.authorizationStatus() == .fullAccess
        let wantGoogle = googleCalendarEnabled && googleAuth.isConnected
        guard wantApple || wantGoogle else {
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
        case .month:
            // Fetch the whole visible 6-week grid so trailing/leading days fill in.
            let cells = MonthGrid.cells(for: selectedDate, calendar: cal)
            guard let first = cells.first, let last = cells.last else { return }
            rangeStart = cal.startOfDay(for: first)
            rangeEnd   = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? last
        case .list:
            // Upcoming window: from the selected day forward ~6 weeks.
            rangeStart = cal.startOfDay(for: selectedDate)
            rangeEnd   = cal.date(byAdding: .day, value: 42, to: rangeStart) ?? rangeStart
        }

        let defaultSpace = appleDefaultSpace.isEmpty
            ? (state.spaces.first?.name ?? "")
            : appleDefaultSpace

        Task {
            var combined: [CalendarEvent] = []
            if wantApple {
                combined += await ekService.fetchEvents(
                    start: rangeStart,
                    end:   rangeEnd,
                    defaultSpaceName: defaultSpace
                )
            }
            if wantGoogle {
                let service = GoogleCalendarService(auth: googleAuth)
                if let googleEvents = try? await service.listEvents(
                    start: rangeStart,
                    end:   rangeEnd,
                    defaultSpaceName: defaultSpace
                ) {
                    combined += googleEvents
                }
            }
            await MainActor.run {
                state.externalEvents = combined
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
        case .week, .month:
            return CalendarFormat.monthYear.string(from: selectedDate)
        case .list:
            return "Upcoming"
        }
    }

    private func shift(by amount: Int) {
        let cal = Calendar.current
        let component: Calendar.Component
        switch mode {
        case .day:   component = .day
        case .month: component = .month
        case .week:  component = .weekOfYear
        case .list:  component = .weekOfYear
        }
        if let next = cal.date(byAdding: component, value: amount, to: selectedDate) {
            selectedDate = cal.startOfDay(for: next)
        }
    }
}
