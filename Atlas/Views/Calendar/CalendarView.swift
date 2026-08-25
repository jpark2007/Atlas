import SwiftUI
import AtlasCore
import TipKit

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
    /// Whether the unscheduled tray is folded into its thin rail (persists across launches).
    @AppStorage("calendar.unscheduledTray.collapsed") private var unscheduledCollapsed: Bool = false

    // MARK: - Drag-to-schedule (custom pointer drag)
    /// The task currently being dragged from the tray (nil = no drag in progress).
    @State private var dragTaskID: UUID?
    /// Live cursor position during a drag, in global space.
    @State private var dragLocation: CGPoint = .zero
    /// Day-column hit-frames published by the grid, in global space.
    @State private var dropColumns: [TaskDropColumn] = []
    /// An already-placed event being dragged to a new slot (nil = not dragging from grid).
    @State private var draggingEvent: CalendarEvent?

    /// The deadline↔work-session link: the task whose due marker is hovered/pinned. Its work
    /// sessions glow and everything else on the grid dims. `nil` = no link active.
    @State private var linkedTaskID: UUID?

    /// Drag-to-schedule onboarding tip, anchored on the unscheduled tray.
    @State private var dragTip = AtlasTips.DragToSchedule()

    // MARK: - Apple Calendar sync
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    @AppStorage("calendar.workSessions.titlePrefix") private var workSessionPrefix: String = CalendarSync.defaultWorkSessionPrefix
    private let ekService = EventKitService()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider().overlay(AtlasTheme.Colors.border)

            // Late bar pinned above today — spanning the grid AND the side rail, so nothing
            // overdue can be scrolled past on the way to the day's work. It sits above both
            // rather than being duplicated in each.
            LateBar(onOpenTask: { state.route = .task($0) })
                .environmentObject(state)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            HStack(alignment: .top, spacing: 18) {
                grid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Group {
                    if unscheduledCollapsed {
                        UnscheduledRail(
                            count: state.unscheduledTasks.filter { !hiddenSpaces.contains($0.spaceName) }.count,
                            onExpand: { toggleUnscheduledTray() }
                        )
                    } else {
                        UnscheduledTray(
                            tasks: state.unscheduledTasks,
                            now: state.now,
                            hiddenSpaces: hiddenSpaces,
                            spaceOrder: state.spaces.map(\.name),
                            onSchedule: { taskID, hour in
                                schedule(taskID: taskID, on: selectedDate, hour: Double(hour))
                            },
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
                            },
                            onCollapse: { toggleUnscheduledTray() }
                        )
                        .frame(width: 250)
                    }
                }
                .popoverTip(dragTip, arrowEdge: .leading)
                .onAppear { AtlasTips.DragToSchedule.hasUnscheduled = !state.unscheduledTasks.isEmpty }
                .onChange(of: state.unscheduledTasks.count) { _, count in
                    AtlasTips.DragToSchedule.hasUnscheduled = count > 0
                }
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
        .onChange(of: mode) { _, newMode in
            loadAppleEventsIfNeeded()
            if newMode == .month { AtlasChecklist.mark(AtlasChecklist.month) }  // Get-started card
        }
        .onChange(of: appleCalendarEnabled) { _, enabled in
            if enabled {
                Task {
                    _ = await ekService.requestAccess()
                    await MainActor.run { loadAppleEventsIfNeeded() }
                }
            } else { loadAppleEventsIfNeeded() }
        }
        // Auto-refresh so Apple-side changes (incl. deletes) surface without leaving and
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

    /// Fold/unfold the unscheduled tray with the house spring; the grid reclaims the
    /// panel's width when it collapses.
    private func toggleUnscheduledTray() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            unscheduledCollapsed.toggle()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALENDAR")
                        .atlasMono(size: 11, weight: .bold)
                        .tracking(0.88)
                        .textCase(.uppercase)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                    Text(titleLabel)
                        .atlasFont(size: 26, weight: .bold, design: .rounded)
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
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(width: 150)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .atlasFont(size: 12, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
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
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
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
                    .atlasFont(size: 12, weight: .bold)
                Text("Add event")
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
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
            .help("Previous day, week, or month")

            Button { selectedDate = Calendar.current.startOfDay(for: Date()) } label: {
                Text("Today")
                    .atlasMono(size: 11, weight: .bold)
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
            .help("Next day, week, or month")
        }
        .atlasFont(size: 14, weight: .semibold, design: .rounded)
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        switch mode {
        case .day:
            DayCalendarView(
                date: selectedDate,
                events: gridEvents(on: selectedDate),
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
                },
                linkedTaskID: linkedTaskID,
                onLinkTask: { linkedTaskID = $0 },
                onToggleTask: { id in withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(id) } },
                onMoreTime: { state.addMoreTime(taskId: $0) },
                plannedLabel: plannedLabel(for:)
            )
        case .week:
            WeekGridView(
                days: weekDays,
                eventsProvider: { gridEvents(on: $0) },
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
                },
                linkedTaskID: linkedTaskID,
                onLinkTask: { linkedTaskID = $0 },
                onToggleTask: { id in withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(id) } },
                onMoreTime: { state.addMoreTime(taskId: $0) },
                plannedLabel: plannedLabel(for:),
                onJumpToDay: { day in
                    selectedDate = Calendar.current.startOfDay(for: day)
                    mode = .day
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
                buckets: agendaBuckets,
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
            + state.classMeetingEvents(on: date)
            + state.externalEvents(on: date)
        // Collapse the same real block arriving from several calendars (school ICS + Google,
        // Google + Apple). Display-time and client-side by necessity: Apple events are only
        // ever in memory, so no server pass can see this pool. Synthesized class meetings go
        // through it deliberately — that's how an already-in-Google lecture collapses into
        // its class's meeting instead of showing twice (Phase 1, door 2).
        let collapsed = CalendarSync.collapsingDuplicates(all, workSessionPrefix: workSessionTitlePrefix)
        // Key Date flags stay OUT of dedup: a term flag is a label on the day, never a second
        // copy of an event, so it must not absorb (or be absorbed by) anything.
        return (collapsed + state.keyDateFlags(on: date))
            .filter { passesFilters($0.spaceName, title: $0.title) }
    }

    /// The work-session mirror label, so dedup can strip it off an inbound "Work: X" copy
    /// and recognise it as the native session it mirrors.
    private var workSessionTitlePrefix: String {
        workSessionPrefix.isEmpty ? CalendarSync.defaultWorkSessionPrefix : workSessionPrefix
    }

    /// Day/week-grid events: `filteredEvents` with per-project colors layered on top
    /// (Option B). Month keeps calling `filteredEvents` directly so its dots stay the
    /// space color; only the grid tiles wear a project's own color.
    private func gridEvents(on date: Date) -> [CalendarEvent] {
        state.gridColored(filteredEvents(on: date))
    }

    /// Deadline markers for `date`: one per open task whose `dueDate` falls on that day,
    /// plus a faded HISTORY marker at the original due date of anything rescheduled off the
    /// Late bar (so a missed date never silently vanishes).
    ///
    /// Deadlines are never blocks — `DueMarkerRow` draws them as hairlines. Colour is the
    /// task's own space/class colour (colour = whose, never what); the ONE state override is
    /// red for "due today and no work time planned", the single place red is earned. Overdue
    /// stays in its own colour here and is surfaced in amber by the Late bar instead.
    /// Deadlines stay in Atlas — they are never pushed to Google.
    private func deadlineEvents(on date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        var markers: [CalendarEvent] = []
        for task in state.tasks {
            guard !task.done else { continue }
            if let due = task.dueDate, cal.isDate(due, inSameDayAs: date) {
                let red = TimeModel.isDueTodayUnplanned(task, now: state.now)
                markers.append(CalendarEvent(
                    id: GoogleCalendarMapper.stableUUID(from: "deadline-" + task.id.uuidString),
                    title: task.title,
                    subtitle: "Due",
                    start: due,
                    end: due,
                    color: red ? AtlasTheme.Colors.danger : task.spaceColor,
                    spaceName: task.spaceName,
                    // Never packed as a time block either way — drawn as a rule on the grid.
                    // A due date carrying a real clock time is NOT all-day, so it draws only
                    // as its rule; a date-only due stays all-day and rides the pinned strip.
                    isAllDay: !hasClockTime(due),
                    isDeadline: true,
                    deadlineTaskID: task.id
                ))
            }
            // The original date keeps a faded marker in the past after a late-reschedule.
            if let original = task.originalDueDate, original != task.dueDate,
               cal.isDate(original, inSameDayAs: date) {
                markers.append(CalendarEvent(
                    id: GoogleCalendarMapper.stableUUID(from: "was-due-" + task.id.uuidString),
                    title: "Was due · " + task.title,
                    subtitle: "Originally due",
                    start: original,
                    end: original,
                    color: AtlasTheme.Colors.textMuted,
                    spaceName: task.spaceName,
                    isAllDay: !hasClockTime(original),
                    isDeadline: true,
                    isHistory: true
                ))
            }
        }
        return markers
    }

    /// Whether a due date carries a real clock time (not bare-date midnight). Mirrors
    /// `CalendarEvent.hasSpecificTime`, but has to be answered before the event is built.
    private func hasClockTime(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0
    }

    /// The planned-time readout a due marker carries: a fill against the task's optional
    /// estimate ("2.5h of 4h planned"), or a session count when it has none.
    /// Atlas persists one session per task today (`TaskItem.scheduledAt`), so the session
    /// array is 0- or 1-length; the math itself is written over many.
    private func plannedLabel(for taskID: UUID) -> String {
        guard let task = state.tasks.first(where: { $0.id == taskID }) else { return "" }
        let sessions = task.scheduledAt == nil ? [] : [task.durationMin ?? 60]
        return TimeModel.plannedLabel(estimateMin: task.estimateMin, sessionMinutes: sessions)
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

    /// Filtered agenda for the List view, bucketed Late / Due today / Tomorrow / This week.
    /// Pulls the store's events + read-only external events + dated tasks, collapses the
    /// cross-source duplicates the grid also hides, applies the same filters as the grid,
    /// then buckets them via the pure `AgendaBuilder`.
    private var agendaBuckets: [AgendaBucket] {
        // Class meetings are synthesized per day, so the agenda's horizon (Late → this
        // week) is materialized a day at a time before dedup sees the pool.
        let cal = Calendar.current
        let today = cal.startOfDay(for: state.now)
        let meetings = (0..<8).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .flatMap { state.classMeetingEvents(on: $0) }
        let events = CalendarSync
            .collapsingDuplicates(state.events + meetings + state.externalEvents,
                                  workSessionPrefix: workSessionTitlePrefix)
            .filter { passesFilters($0.spaceName, title: $0.title) }
        let tasks = state.tasks
            .filter { !$0.done && passesFilters($0.spaceName, title: $0.title) }
        return AgendaBuilder.buckets(events: events, tasks: tasks, now: state.now)
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
    /// `state.externalEvents`. Reads Apple Calendar (read-only EventKit) when enabled
    /// and authorized. Called on appear, on `selectedDate`/`mode` change, and when the
    /// Apple source toggles. External events NEVER enter `state.events`.
    ///
    /// Google is NOT read here: server-owned cloud sync owns Google↔DB, so Google
    /// events arrive as `events` rows via `loadAll()`. A Mac-local Google pull would
    /// double-show them on top of the synced rows.
    private func loadAppleEventsIfNeeded() {
        let wantApple = appleCalendarEnabled && ekService.authorizationStatus() == .fullAccess
        guard wantApple else {
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
            let combined = await ekService.fetchEvents(
                start: rangeStart,
                end:   rangeEnd,
                defaultSpaceName: defaultSpace
            )
            await MainActor.run {
                // Drop any Apple event that is actually one of our own events we already
                // mirrored via the Atlas→Apple toggle (EventKit re-reads it next tick).
                // Otherwise it shows twice: once native, once as its read-only Apple copy.
                // Work sessions mirror to Apple too (Phase 3), and their handle lives on the
                // TASK — so their ids must join the drop-set or every mirrored session
                // double-displays as its own "Work: …" Apple copy.
                let ownAppleIDs = Set(state.events.compactMap(\.appleEventId))
                    .union(state.tasks.compactMap(\.appleEventId))
                state.externalEvents = CalendarSync.excludingOwnMirrors(
                    external: combined,
                    ownGoogleIDs: [],
                    ownAppleIDs: ownAppleIDs)
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
        Task { await AtlasTipEvents.scheduledByDrag.donate() }
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
