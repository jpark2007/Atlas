import SwiftUI
import AtlasCore

/// The Atlas Calendar — the hero screen. Day / Week time grid with a space
/// filter and a drag-to-schedule tray of unscheduled tasks. Reads/writes the
/// shared `AppState` store (`events`, `unscheduledTasks`, `schedule(taskId:at:)`).
struct CalendarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var mode: CalendarMode = .day

    /// In-calendar title search; empty = no search filter.
    @State private var searchText: String = ""
    /// Space names hidden via the color/category filter row. Empty = show all.
    @State private var hiddenSpaces: Set<String> = []

    // MARK: - Drag-to-schedule (custom pointer drag)
    /// The task currently being dragged from the tray (nil = no drag in progress).
    @State private var dragTaskID: UUID?
    /// Live cursor position during a drag, in global space.
    @State private var dragLocation: CGPoint = .zero
    /// Day-column hit-frames published by the grid, in global space.
    @State private var dropColumns: [TaskDropColumn] = []
    /// An already-placed event being dragged to a new slot (nil = not dragging from grid).
    @State private var draggingEvent: CalendarEvent?

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
                    now: state.now,
                    hiddenSpaces: hiddenSpaces,
                    spaceOrder: state.spaces.map(\.name),
                    onSchedule: { taskID, hour in
                        schedule(taskID: taskID, on: selectedDate, hour: Double(hour))
                    },
                    onSuggest: suggestSlot(for:),
                    onSetDueDate: { taskID, date in
                        state.setDueDate(taskId: taskID, date: date)
                    },
                    onToggleDone: { state.toggleTask($0) },
                    onDragChanged: { id, point in
                        dragTaskID = id
                        dragLocation = point
                    },
                    onDragEnded: { id, point in
                        performTaskDrop(taskID: id, at: point)
                        dragTaskID = nil
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .onPreferenceChange(TaskDropColumnsKey.self) { dropColumns = $0 }
            // The drag point + column frames are in GLOBAL space. Convert the global
            // drag point into the overlay's local space (subtract its global origin)
            // to position the preview chip under the cursor.
            .overlay {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    if let id = dragTaskID, let task = state.tasks.first(where: { $0.id == id }) {
                        TaskDragPreview(title: task.title, color: task.spaceColor)
                            .position(x: dragLocation.x - origin.x, y: dragLocation.y - origin.y)
                    } else if let event = draggingEvent {
                        TaskDragPreview(title: event.title, color: event.color)
                            .position(x: dragLocation.x - origin.x, y: dragLocation.y - origin.y)
                    }
                }
                .allowsHitTesting(false)
            }
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
        // Auto-refresh so Google-side changes (incl. deletes) surface without leaving and
        // re-entering the tab: poll every 60s while the calendar is visible, and refresh
        // immediately when the app regains focus (e.g. after you edited on your phone).
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            loadAppleEventsIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadAppleEventsIfNeeded() }
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.88)
                        .textCase(.uppercase)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                    Text(titleLabel)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                Spacer()
                addEventButton
                navigationControls
            }

            HStack(spacing: 12) {
                AtlasSegmentedPicker(
                    options: CalendarMode.allCases,
                    label: { $0.rawValue },
                    selection: $mode
                )

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
                .font(.system(size: 12, design: .rounded))
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
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1)
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
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isHidden ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    .strikethrough(isHidden, color: AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isHidden ? Color.clear : AtlasTheme.wash(space.color),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
            )
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                    )
            }
            .buttonStyle(.plain)

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        switch mode {
        case .day:
            DayCalendarView(
                date: selectedDate,
                events: filteredEvents(on: selectedDate),
                now: state.now,
                onTapEmpty: handleTapEmpty,
                onTapEvent: openSource(for:),
                onDragEvent: { event, point in
                    draggingEvent = event
                    dragLocation = point
                },
                onDropEvent: { event, point in
                    performEventReschedule(event: event, at: point)
                    draggingEvent = nil
                }
            )
        case .week:
            WeekGridView(
                days: weekDays,
                eventsProvider: { filteredEvents(on: $0) },
                now: state.now,
                onTapEmpty: handleTapEmpty,
                onTapEvent: openSource(for:),
                onDragEvent: { event, point in
                    draggingEvent = event
                    dragLocation = point
                },
                onDropEvent: { event, point in
                    performEventReschedule(event: event, at: point)
                    draggingEvent = nil
                }
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
            + deadlineEvents(on: date)
            + state.externalEvents(on: date)
        return all.filter { passesFilters($0.spaceName, title: $0.title) }
    }

    /// Deadline markers for `date`: one per open task whose `dueDate` falls on that day.
    /// Rendered as flag-pills in the deadline strip (never time blocks), red once the due
    /// day has passed. Deadlines stay in Atlas — they are never pushed to Google.
    private func deadlineEvents(on date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return state.tasks.compactMap { task in
            guard !task.done, let due = task.dueDate,
                  cal.isDate(due, inSameDayAs: date) else { return nil }
            let overdue = cal.startOfDay(for: due) < cal.startOfDay(for: state.now)
            return CalendarEvent(
                id: GoogleCalendarMapper.stableUUID(from: "deadline-" + task.id.uuidString),
                title: task.title,
                subtitle: "Due",
                start: due,
                end: due,
                color: overdue ? AtlasTheme.Colors.danger : AtlasTheme.Colors.accent,
                spaceName: task.spaceName,
                isAllDay: true,        // excluded from time-block packing; shown in the strip
                isDeadline: true
            )
        }
    }

    /// Shared filter gate for both events and tasks: the single-space dropdown,
    /// the color/category hide-row, and the in-calendar title search.
    private func passesFilters(_ spaceName: String, title: String) -> Bool {
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
        state.scheduledWorkBlocks(on: date)
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
        // Single-owner: when the server owns Google↔DB sync the Mac makes ZERO Google
        // calls — no live pull, no reap, no `externalEvents` merge for Google. Google
        // events instead arrive as `events` rows via `loadAll()`. Apple stays live here.
        let wantGoogle = googleCalendarEnabled && googleAuth.isConnected && !state.serverSyncEnabled
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

        // Pre-fetch snapshot of our pushed-mirror ids. An event created during the fetch
        // won't be in here, so a listing that predates its id can never reap it (B2).
        let eligibleGoogleIDs = Set(
            state.events.filter { $0.source == .atlas }.compactMap(\.googleEventId))

        Task {
            var combined: [CalendarEvent] = []
            if wantApple {
                combined += await ekService.fetchEvents(
                    start: rangeStart,
                    end:   rangeEnd,
                    defaultSpaceName: defaultSpace
                )
            }
            var googlePresentIDs: Set<String> = []
            var googleFetchOK = true
            var fetchError: String? = nil
            if wantGoogle {
                let service = GoogleCalendarService(auth: googleAuth)
                do {
                    let googleEvents = try await service.listEvents(
                        start: rangeStart,
                        end:   rangeEnd,
                        defaultSpaceName: defaultSpace
                    )
                    combined += googleEvents
                    googlePresentIDs = Set(googleEvents.compactMap(\.googleEventId))
                } catch {
                    // A failed fetch returns no events — this must NOT be read as
                    // "everything was deleted on Google", or the reaper would wipe the
                    // window. Record the error and skip reaping this cycle.
                    googleFetchOK = false
                    fetchError = error.localizedDescription
                }
            }
            await MainActor.run {
                // Drop any external (Google) event that is actually one of our own
                // Atlas events / scheduled work-blocks we already pushed — otherwise it
                // shows twice (once native, once as a read-only Google copy).
                let ownGoogleIDs = Set(state.events.compactMap(\.googleEventId))
                    .union(state.tasks.compactMap(\.workBlockGoogleEventId))
                state.externalEvents = combined.filter { ev in
                    guard let gid = ev.googleEventId else { return true }
                    return !ownGoogleIDs.contains(gid)
                }
                // Reflect Google-side deletions: reap our mirrors that vanished from a
                // SUCCESSFUL listing for this window. Safety rules live in CalendarSync.
                if wantGoogle && googleFetchOK {
                    let reap = CalendarSync.reapableEventIDs(
                        events: state.events,
                        presentGoogleIDs: googlePresentIDs,
                        eligibleGoogleIDs: eligibleGoogleIDs,
                        windowStart: rangeStart,
                        windowEnd: rangeEnd)
                    state.removeEventsLocally(ids: reap)
                }
                if wantGoogle { state.lastCalendarSyncError = fetchError }
            }
        }
    }

    // MARK: - Scheduling

    /// Resolve a custom-drag release point (in `calendarDragSpace`) to a day column +
    /// fractional hour, then schedule. No-op if released outside any day column (e.g.
    /// back on the tray), so a mis-drop simply returns the task to the tray.
    private func performTaskDrop(taskID: UUID, at point: CGPoint) {
        guard let column = dropColumns.first(where: { $0.frame.contains(point) }) else { return }
        let hour = Double(CalendarLayout.startHour)
            + Double(point.y - column.frame.minY) / Double(CalendarLayout.hourHeight)
        _ = schedule(taskID: taskID, on: column.date, hour: hour)
    }

    /// Resolve a drag-release of an already-placed event/task to a new slot and reschedule it.
    /// Task-derived tiles (id matches a TaskItem) update `scheduledAt` directly.
    /// Native CalendarEvents preserve their duration and move start/end.
    /// Reschedule an already-placed event/task to the dropped grid slot (drag-to-reschedule).
    private func performEventReschedule(event: CalendarEvent, at point: CGPoint) {
        guard let column = dropColumns.first(where: { $0.frame.contains(point) }) else { return }
        let hour = Double(CalendarLayout.startHour)
            + Double(point.y - column.frame.minY) / Double(CalendarLayout.hourHeight)
        let clamped = min(max(hour, Double(CalendarLayout.startHour)), Double(CalendarLayout.endHour) - 0.25)
        let h = Int(clamped)
        let minute = (Int((clamped - Double(h)) * 60) / 15) * 15
        let cal = Calendar.current
        guard var newStart = cal.date(bySettingHour: h, minute: minute, second: 0, of: column.date) else { return }

        // Bump a past-today drop to the next 15-min boundary at/after now.
        if cal.isDateInToday(newStart), newStart < state.now {
            let nowMinutes = cal.component(.hour, from: state.now) * 60 + cal.component(.minute, from: state.now)
            let snapped = ((nowMinutes / 15) + 1) * 15
            if let next = cal.date(bySettingHour: snapped / 60, minute: snapped % 60, second: 0, of: column.date) {
                newStart = next
            }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            if state.tasks.contains(where: { $0.id == event.id }) {
                state.schedule(taskId: event.id, at: newStart)
            } else {
                var updated = event
                let duration = event.end.timeIntervalSince(event.start)
                updated.start = newStart
                updated.end = newStart.addingTimeInterval(duration)
                state.updateEvent(updated)
            }
        }
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
        guard var dropped = cal.date(bySettingHour: h, minute: minute, second: 0, of: date) else { return false }

        // An explicit drop in the past (earlier today than "now") would land already
        // "passed" (dimmed) the instant it's placed. Bump it to the next 15-min boundary
        // at/after now so a deliberate drop is actionable, not instantly elapsed.
        if cal.isDateInToday(dropped), dropped < state.now {
            let nowMinutes = cal.component(.hour, from: state.now) * 60 + cal.component(.minute, from: state.now)
            let snapped = ((nowMinutes / 15) + 1) * 15
            if let next = cal.date(bySettingHour: snapped / 60, minute: snapped % 60, second: 0, of: date) {
                dropped = next
            }
        }

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
        // Deadlines have no detail page. A work-block IS a task, so open the richer task
        // detail page (due date, scheduled time, project, notes); plain events open the
        // calendar-item detail view.
        guard !event.isDeadline else { return }
        if event.isWorkBlock {
            state.route = .task(event.id)   // work-block id == task id (AppState.scheduledWorkBlocks)
        } else {
            state.calendarDetailItem = event
            state.route = .calendarDetail
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
