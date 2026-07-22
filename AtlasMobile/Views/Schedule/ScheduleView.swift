import SwiftUI
import AtlasCore
import TipKit

/// The Schedule home (spec §4.1): a day header with nav + swipe, the shared space
/// filter, a "Needs a time" block pinned on top, and the day's timeline. Opens on
/// today; the calendar glyph pushes a month page for jumping days.
struct ScheduleView: View {
    @EnvironmentObject private var store: MobileStore

    @AppStorage("scheduleViewMode") private var viewMode = "list"   // "list" | "grid"

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showMonth = false
    @State private var showSettings = false
    @State private var timing: TaskItem?
    @State private var detail: ItemDetailSheet.Detail?
    // Drag-to-place scheduling.
    @State private var showPlace = false
    @State private var placing: TaskItem?
    @State private var placeMinutes = 9 * 60
    // A block on the grid is lifted for a drag-move (Task H) — hides the FAB, like `placing`.
    @State private var blockMoveActive = false
    // Create-here: captured while PlaceTaskSheet is open, presented on its dismiss.
    @State private var pendingPrefill: ManualAddSheet.Prefill?
    @State private var manualPrefill: ManualAddSheet.Prefill?
    // Onboarding tip #2 — anchored on the "Needs a time" section (rule-gated in AtlasTips).
    @State private var dragTip = AtlasTips.DragToSchedule()

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .overlay(alignment: .bottomTrailing) {
                    if placing == nil && !blockMoveActive {
                        fab
                    }
                }
                .animation(MobileTheme.spring, value: placing != nil || blockMoveActive)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if !cal.isDateInToday(selectedDay) {
                Button {
                    MobileTheme.Haptic.selection()
                    withAnimation(MobileTheme.spring) {
                        selectedDay = cal.startOfDay(for: Date())
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(0.96).textCase(.uppercase)
                        .foregroundStyle(MobileTheme.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(MobileTheme.bg))
                        .overlay(Capsule().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(MobileTheme.spring, value: cal.isDateInToday(selectedDay))
        .sheet(isPresented: $showMonth) {
            MonthPageView(selected: selectedDay) { selectedDay = $0 }
                .environmentObject(store)
        }
        .sheet(isPresented: $showPlace, onDismiss: finishPlaceSheet) {
            PlaceTaskSheet(onPick: { beginPlacing($0) },
                           onNewEvent: { pendingPrefill = prefill(kind: "event") },
                           onNewTask: { pendingPrefill = prefill(kind: "task") })
                .environmentObject(store)
        }
        .sheet(item: $manualPrefill) { prefill in
            ManualAddSheet(prefill: prefill)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
        .sheet(item: $timing) { task in
            SetTimeSheet(task: task, day: selectedDay) { updated in
                Task { await store.updateTask(updated) }
            }
        }
        .sheet(item: $detail) { detail in
            ItemDetailSheet(detail: detail).environmentObject(store)
        }
        .onAppear {
            consumeFocusToday(); consumePlacement()
            AtlasTips.DragToSchedule.hasUnscheduled = !needsTime.isEmpty
        }
        .onChange(of: needsTime.count) { _, _ in
            AtlasTips.DragToSchedule.hasUnscheduled = !needsTime.isEmpty
        }
        .onChange(of: store.scheduleFocusToday) { _, _ in consumeFocusToday() }
        .onChange(of: store.pendingPlacement?.id) { _, _ in consumePlacement() }
        .onChange(of: viewMode) { _, new in
            if new != "grid" { placing = nil; blockMoveActive = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { changeDay(-1) } label: { chevron("chevron.left") }
                Text(dayLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(MobileTheme.ink)
                    .layoutPriority(1)
                Button { changeDay(1) } label: { chevron("chevron.right") }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }

            HStack(spacing: 14) {
                Text("\(leftCount) left").edCapsLabel()
                Spacer()
                spaceFilterMenu
                viewToggle
                Button {
                    showMonth = true
                    UserDefaults.standard.set(true, forKey: "checklist.month")
                    Task { await AtlasTipEvents.peekedMonth.donate() }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MobileTheme.ink).frame(height: MobileTheme.rule)   // strong header rule
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MobileTheme.ink)
            .frame(width: 30, height: 30)
    }

    private var spaceFilterMenu: some View {
        Menu {
            Button("All spaces") { store.spaceFilter = nil }
            ForEach(store.snapshot.spaces) { space in
                Button(space.name) { store.spaceFilter = space.id }
            }
        } label: {
            HStack(spacing: 6) {
                if let space = filterSpace {
                    Circle().fill(space.color).frame(width: 8, height: 8)
                }
                Text(filterSpace?.name ?? "All")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MobileTheme.faint)
            }
        }
    }

    private var viewToggle: some View {
        HStack(spacing: 12) {
            toggleGlyph("list.bullet", "list")
            toggleGlyph("calendar.day.timeline.left", "grid")
        }
    }

    private func toggleGlyph(_ name: String, _ mode: String) -> some View {
        Button {
            guard viewMode != mode else { return }
            MobileTheme.Haptic.selection()
            withAnimation(MobileTheme.spring) { viewMode = mode }
        } label: {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(viewMode == mode ? MobileTheme.ink : MobileTheme.faint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body (list ↔ grid)

    @ViewBuilder
    private var content: some View {
        if viewMode == "grid" { gridBody } else { listBody }
    }

    /// Floating place entry — the permanent way to open `PlaceTaskSheet` in either
    /// view mode, even on days with no "needs a time" tasks (the section header's
    /// PLACE can't). Sits bottom-trailing, same corner DayGridView's placement
    /// confirm/cancel circles use — hidden whenever `placing != nil` so they never
    /// overlap; mirrors `placeCircle`'s look (paper fill, ink stroke, ink glyph).
    private var fab: some View {
        Button { showPlace = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MobileTheme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(MobileTheme.bg))
                .overlay(Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
                .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 68)   // sits closer to the tab bar (comfortable margin, no overlap)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private var listBody: some View {
        // TimelineView re-evaluates every minute so the NOW rail advances.
        TimelineView(.everyMinute) { context in
            List {
                GetStartedCard()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                NeedsTimeSection(tasks: needsTime,
                                 onSetTime: { timing = $0 },
                                 onOpen: { detail = .task($0) },
                                 onPlace: { showPlace = true },
                                 onLongPress: { store.pendingPlacement = $0 })
                    .popoverTip(dragTip)
                DayTimelineView(
                    day: selectedDay,
                    now: context.date,
                    events: filteredEvents,
                    tasks: filteredTasks,
                    loading: store.loading,
                    onToggle: toggle,
                    onDelete: delete,
                    onOpen: { detail = $0 },
                    onDeleteEvent: deleteEvent
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 160, for: .scrollContent)
            .refreshable { await store.refresh() }
            .simultaneousGesture(daySwipe)
        }
    }

    private var gridBody: some View {
        // TimelineView re-evaluates every minute so the NOW line advances.
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                GetStartedCard()
                NeedsTimeSection(tasks: needsTime,
                                 onSetTime: { timing = $0 },
                                 onOpen: { detail = .task($0) },
                                 onPlace: { showPlace = true },
                                 onLongPress: { store.pendingPlacement = $0 },
                                 compact: true)
                    .popoverTip(dragTip)
                DayGridView(
                    day: selectedDay,
                    now: context.date,
                    events: store.gridColored(filteredEvents),
                    tasks: store.gridColored(tasks: filteredTasks),
                    onOpen: { detail = $0 },
                    onToggle: toggle,
                    placing: placing,
                    placeMinutes: $placeMinutes,
                    onConfirmPlace: confirmPlace,
                    onCancelPlace: { withAnimation(MobileTheme.spring) { placing = nil } },
                    blockMoveActive: $blockMoveActive,
                    onMoveTask: moveTask,
                    onMoveEvent: moveEvent
                )
            }
            .simultaneousGesture(daySwipe)
        }
    }

    /// Horizontal fling changes the day (stays usable while placing).
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 50 else { return }
                changeDay(value.translation.width < 0 ? 1 : -1)
            }
    }

    // MARK: - Data (space-filtered)

    private var filterSpace: Space? {
        guard let id = store.spaceFilter else { return nil }
        return store.snapshot.spaces.first { $0.id == id }
    }

    private func inFilter(_ spaceName: String) -> Bool {
        guard let name = filterSpace?.name else { return true }
        return spaceName.caseInsensitiveCompare(name) == .orderedSame
    }

    private var filteredEvents: [CalendarEvent] { store.snapshot.events.filter { inFilter($0.spaceName) } }
    private var filteredTasks: [TaskItem] { store.snapshot.tasks.filter { inFilter($0.spaceName) } }

    /// Tasks due on the shown day that truly need a time — date-only due, unscheduled.
    /// Clock-timed due tasks are deadlines and render on the timeline/grid instead.
    private var needsTime: [TaskItem] {
        filteredTasks
            .filter { task in
                guard let due = task.dueDate, task.scheduledAt == nil, !task.done,
                      cal.isDate(due, inSameDayAs: selectedDay) else { return false }
                let c = cal.dateComponents([.hour, .minute], from: due)
                return (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// "N left" — what's still ahead on the shown day: open tasks landing on it
    /// (scheduled OR any due — the needs-time + timed + clock-deadline populations, !done)
    /// PLUS events that haven't ended. For today an event counts while `end > now`; for a
    /// future day all its events count; for a past day none do (the day is over).
    private var leftCount: Int {
        let now = Date()
        let tasks = filteredTasks.filter { task in
            guard !task.done else { return false }
            if let at = task.scheduledAt { return cal.isDate(at, inSameDayAs: selectedDay) }
            if let due = task.dueDate { return cal.isDate(due, inSameDayAs: selectedDay) }
            return false
        }.count

        let events = filteredEvents.filter { event in
            guard cal.isDate(event.start, inSameDayAs: selectedDay) else { return false }
            if cal.isDateInToday(selectedDay) { return event.end > now }     // today: not yet ended
            return selectedDay > cal.startOfDay(for: now)                    // future day: all; past: none
        }.count

        return tasks + events
    }

    private static let dayLabelFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f }()

    private var dayLabel: String { Self.dayLabelFormatter.string(from: selectedDay) }

    // MARK: - Actions

    private func changeDay(_ delta: Int) {
        if let next = cal.date(byAdding: .day, value: delta, to: selectedDay) {
            withAnimation(.easeInOut(duration: 0.18)) { selectedDay = next }
        }
    }

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        updated.completedAt = updated.done ? Date() : nil
        Task { await store.setTaskDone(updated) }
    }

    private func delete(_ task: TaskItem) {
        Task { await store.deleteTask(id: task.id) }
    }

    private func deleteEvent(_ event: CalendarEvent) {
        Task { await store.deleteEvent(id: event.id) }
    }

    // MARK: - Placement

    /// Picked a task in PlaceTaskSheet → flip to grid mode with a floating chip
    /// at the default initial time.
    private func beginPlacing(_ task: TaskItem) {
        placeMinutes = initialPlaceMinutes()
        withAnimation(MobileTheme.spring) {
            viewMode = "grid"
            placing = task
        }
    }

    /// Build a ManualAddSheet prefill for the shown day (kind only — no slot time).
    private func prefill(kind: String) -> ManualAddSheet.Prefill {
        ManualAddSheet.Prefill(kind: kind, day: selectedDay, minute: nil)
    }

    /// On PlaceTaskSheet dismiss: if a create-here row was tapped, present
    /// ManualAddSheet now (a second sheet can't open until the first is gone).
    private func finishPlaceSheet() {
        if let p = pendingPrefill {
            pendingPrefill = nil
            manualPrefill = p
        }
    }

    /// Initial chip time: next 15-min slot after now (today) else 9:00 AM.
    private func initialPlaceMinutes() -> Int {
        guard cal.isDateInToday(selectedDay) else { return 9 * 60 }
        let c = cal.dateComponents([.hour, .minute], from: Date())
        let m = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        return min(1425, ((m / 15) + 1) * 15)
    }

    private func confirmPlace() {
        guard let task = placing else { return }
        var updated = task
        updated.scheduledAt = cal.date(bySettingHour: placeMinutes / 60,
                                       minute: placeMinutes % 60, second: 0,
                                       of: cal.startOfDay(for: selectedDay))
        Task { await store.updateTask(updated) }
        Task { await AtlasTipEvents.scheduledOnCalendar.donate() }
        UserDefaults.standard.set(true, forKey: "checklist.scheduled")
        MobileTheme.Haptic.success()
        withAnimation(MobileTheme.spring) { placing = nil }
    }

    /// Block-move confirm (Task H) — a scheduled task lands at `minute` on the shown
    /// day. Mirrors `confirmPlace`'s `scheduledAt` write; `workBlockGoogleEventId` and
    /// every other field are carried through by copying the struct.
    private func moveTask(_ task: TaskItem, _ minute: Int) {
        var updated = task
        updated.scheduledAt = cal.date(bySettingHour: minute / 60,
                                       minute: minute % 60, second: 0,
                                       of: cal.startOfDay(for: selectedDay))
        Task { await store.updateTask(updated) }
        UserDefaults.standard.set(true, forKey: "checklist.scheduled")
    }

    /// Block-move confirm for an event — shift start AND end by the same `delta`
    /// (minutes) so the duration is preserved; `googleEventId` and all other fields
    /// ride along by copying the struct so the Google mirror stays attached.
    private func moveEvent(_ event: CalendarEvent, _ delta: Int) {
        var updated = event
        updated.start = cal.date(byAdding: .minute, value: delta, to: event.start) ?? event.start
        updated.end = cal.date(byAdding: .minute, value: delta, to: event.end) ?? event.end
        Task { await store.updateEvent(updated) }
    }

    private func consumeFocusToday() {
        guard store.scheduleFocusToday else { return }
        store.scheduleFocusToday = false
        selectedDay = cal.startOfDay(for: Date())
    }

    /// A long-press elsewhere set `pendingPlacement`; pick it up (grid mode + chip)
    /// exactly like a `PlaceTaskSheet` pick, then clear it.
    private func consumePlacement() {
        guard let task = store.pendingPlacement else { return }
        store.pendingPlacement = nil
        beginPlacing(task)
    }
}
