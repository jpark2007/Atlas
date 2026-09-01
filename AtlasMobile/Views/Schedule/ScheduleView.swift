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
    // First-visit 2-step spotlight over the list/grid toggle + calendar glyph (shown once ever).
    @AppStorage("spotlight.calendarViews.done") private var spotlightDone = false
    @State private var spotlightStep = 0
    @State private var spotlightAnchors: [String: CGRect] = [:]
    @State private var spotlightActive = false

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
        .onPreferenceChange(SpotlightAnchorKey.self) { spotlightAnchors = $0 }
        .overlay {
            if spotlightActive {
                CalendarSpotlightOverlay(step: spotlightStep, anchors: spotlightAnchors) {
                    spotlightActive = false; spotlightDone = true
                }
            }
        }
        .onChange(of: showMonth) { _, opened in
            if spotlightActive && spotlightStep == 1 && opened {
                spotlightActive = false; spotlightDone = true   // step 2 → finish on month open
            }
        }
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
                .edSheetDetents([.medium, .large], preferringLarge: true)
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
        // Apple Calendar is an on-device read, so it's refreshed rather than synced:
        // on appear, when the shown day moves out of the loaded window, and whenever
        // EventKit says the on-device store changed.
        .onReceive(store.eventKit.changeNotification) { _ in
            store.refreshAppleEvents(around: selectedDay)
        }
        .onChange(of: selectedDay) { _, day in
            store.refreshAppleEvents(around: day)
            // Leaving the day (chevron / Today / month jump) abandons any lifted block —
            // the page it belongs to cancels its own move, this releases the FAB.
            if blockMoveActive { blockMoveActive = false }
        }
        .onAppear {
            store.refreshAppleEvents(around: selectedDay)
            consumeFocusToday(); consumePlacement()
            AtlasTips.DragToSchedule.hasUnscheduled = !needsTime(on: selectedDay).isEmpty
            if !spotlightDone { spotlightActive = true }   // first Schedule visit only
        }
        .onChange(of: needsTime(on: selectedDay).count) { _, _ in
            AtlasTips.DragToSchedule.hasUnscheduled = !needsTime(on: selectedDay).isEmpty
        }
        .onChange(of: store.scheduleFocusToday) { _, _ in consumeFocusToday() }
        .onChange(of: store.pendingPlacement?.id) { _, _ in consumePlacement() }
        .onChange(of: viewMode) { _, new in
            if new != "grid" { placing = nil; blockMoveActive = false }
            if spotlightActive && spotlightStep == 0 { spotlightStep = 1 }   // step 1 → advance on toggle tap
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
                    .spotlightAnchor("toggle")
                Button {
                    showMonth = true
                    UserDefaults.standard.set(true, forKey: "checklist.month")
                    Task { await AtlasTipEvents.peekedMonth.donate() }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
                .spotlightAnchor("calendar")
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

    /// The three days the pager keeps live: yesterday, the shown day, tomorrow. Paging
    /// is unbounded (there is no first or last day), so there is no edge to rubber-band.
    private var pageDays: [Date] {
        [-1, 0, 1].compactMap { cal.date(byAdding: .day, value: $0, to: selectedDay) }
    }

    private var listBody: some View {
        // TimelineView re-evaluates every minute so the NOW rail advances.
        TimelineView(.everyMinute) { context in
            DayPager(pages: pageDays.map { DayPage(day: $0, content: listPage(day: $0, now: context.date)) },
                     enabled: !blockMoveActive,
                     onCommit: changeDay)
        }
    }

    /// One day of the list view. Everything it draws comes from `day`, never
    /// `selectedDay` — the neighbours are real, live pages, not snapshots.
    private func listPage(day: Date, now: Date) -> some View {
        let center = cal.isDate(day, inSameDayAs: selectedDay)
        return List {
            if spotlightDone {
                GetStartedCard()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            // Late is pinned above today's work — never scrolled past, never rolled.
            if cal.isDateInToday(day) {
                LateGroup(items: lateItems,
                          onToggle: toggleByID,
                          onOpen: { id in
                              if let task = store.snapshot.tasks.first(where: { $0.id == id }) {
                                  detail = .task(task)
                              }
                          },
                          onReschedule: { date in
                              Task { await store.rescheduleLateItems(to: date) }
                          })
            }
            NeedsTimeSection(tasks: needsTime(on: day),
                             onSetTime: { timing = $0 },
                             onOpen: { detail = .task($0) },
                             onPlace: { showPlace = true },
                             onLongPress: { store.pendingPlacement = $0 })
                // Only the shown page anchors the tip — three copies would fight.
                .onboardingTip(dragTip, when: spotlightDone && center)
            DayTimelineView(
                day: day,
                now: now,
                events: events(on: day),
                tasks: filteredTasks,
                loading: store.loading,
                onToggle: toggle,
                onDelete: delete,
                onOpen: { detail = $0 },
                onDeleteEvent: deleteEvent
            )
            // Apple Calendar lives on the phone, not the server, so it's connected
            // per-device. Shown until it is — the permanent toggle belongs in the
            // Settings calendar list (see AppleCalendarConnectRow).
            if !store.appleCalendarEnabled {
                AppleCalendarConnectRow(day: day)
                    .environmentObject(store)
                    .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 160, for: .scrollContent)
        .refreshable { await store.refresh() }
    }

    private var gridBody: some View {
        // TimelineView re-evaluates every minute so the NOW line advances.
        TimelineView(.everyMinute) { context in
            DayPager(pages: pageDays.map { DayPage(day: $0, content: gridPage(day: $0, now: context.date)) },
                     enabled: !blockMoveActive,
                     onCommit: changeDay)
        }
    }

    /// One day of the grid view. The placement chip and the block-move binding belong to
    /// the shown day only — a neighbour page never carries a live chip.
    private func gridPage(day: Date, now: Date) -> some View {
        let center = cal.isDate(day, inSameDayAs: selectedDay)
        return VStack(spacing: 0) {
            if spotlightDone { GetStartedCard() }
            NeedsTimeSection(tasks: needsTime(on: day),
                             onSetTime: { timing = $0 },
                             onOpen: { detail = .task($0) },
                             onPlace: { showPlace = true },
                             onLongPress: { store.pendingPlacement = $0 },
                             compact: true)
                .onboardingTip(dragTip, when: spotlightDone && center)
            DayGridView(
                day: day,
                now: now,
                events: store.gridColored(events(on: day)),
                tasks: store.gridColored(tasks: filteredTasks),
                onOpen: { detail = $0 },
                onToggle: toggle,
                placing: center ? placing : nil,
                placeMinutes: center ? $placeMinutes : .constant(placeMinutes),
                onConfirmPlace: confirmPlace,
                onCancelPlace: { withAnimation(MobileTheme.spring) { placing = nil } },
                blockMoveActive: center ? $blockMoveActive : .constant(false),
                onMoveTask: moveTask,
                onMoveEvent: moveEvent,
                isShown: center
            )
        }
        // The grid had no pull-to-refresh — only the list did — and a long-press to
        // place a task drops you into grid mode permanently, so a user could end up
        // with no way to force a re-pull at all.
        .refreshable { await store.refresh() }
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

    /// The day's display pool: Atlas events + synthesized class meetings + read-only Apple
    /// events, already collapsed by the shared dedup (`MobileStore.displayEvents`), then
    /// space-filtered here.
    private func events(on day: Date) -> [CalendarEvent] {
        store.displayEvents(on: day).filter { inFilter($0.spaceName) }
    }
    private var filteredTasks: [TaskItem] { store.snapshot.tasks.filter { inFilter($0.spaceName) } }

    /// Tasks due on `day` that truly need a time — date-only due, unscheduled.
    /// Clock-timed due tasks are deadlines and render on the timeline/grid instead.
    private func needsTime(on day: Date) -> [TaskItem] {
        filteredTasks
            .filter { task in
                guard let due = task.dueDate, task.scheduledAt == nil, !task.done,
                      cal.isDate(due, inSameDayAs: day) else { return false }
                let c = cal.dateComponents([.hour, .minute], from: due)
                return (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Overdue open tasks, from the shared `TimeModel` rule (day-granular, oldest first) —
    /// the Late group's contents. Space-filtered like everything else on the screen.
    private var lateItems: [TimeModel.LateItem] {
        TimeModel.lateItems(tasks: filteredTasks)
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

        let dayEvents = events(on: selectedDay).filter { event in
            guard cal.isDate(event.bucketDate(in: cal), inSameDayAs: selectedDay) else { return false }
            if cal.isDateInToday(selectedDay) {
                // An all-day event has no clock time to be past, so it counts all day; its
                // end is a UTC midnight, which would otherwise retire it mid-afternoon.
                return event.isAllDay || event.end > now                     // today: not yet ended
            }
            return selectedDay > cal.startOfDay(for: now)                    // future day: all; past: none
        }.count

        return tasks + dayEvents
    }

    private static let dayLabelFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f }()

    private var dayLabel: String { Self.dayLabelFormatter.string(from: selectedDay) }

    // MARK: - Actions

    /// Step a day, from a chevron tap or a completed swipe. Deliberately unanimated:
    /// the pager owns swipe motion (it re-centres itself around the new day), and a
    /// chevron's page swap would cross-fade rather than slide.
    private func changeDay(_ delta: Int) {
        if let next = cal.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = next
        }
    }

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        updated.completedAt = updated.done ? Date() : nil
        Task { await store.setTaskDone(updated) }
    }

    /// Check off a task by id — the Late group's checkbox, which is the task's own.
    private func toggleByID(_ id: UUID) {
        guard let task = store.snapshot.tasks.first(where: { $0.id == id }) else { return }
        MobileTheme.Haptic.tap()
        toggle(task)
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

// MARK: - Day pager

/// One page of `DayPager`: a day and the already-built view that draws it. The content
/// is a value, built by the parent — the pager never rebuilds it, so a 60/120 Hz drag
/// costs nothing beyond an `offset`.
struct DayPage<Content: View>: Identifiable {
    let day: Date
    let content: Content
    var id: Date { day }
}

/// A finger-tracking horizontal pager over exactly three live day pages
/// (previous / shown / next). The strip sits at `-width`, so the shown page fills the
/// viewport and both neighbours are real, rendered content one screen away — nothing is
/// loaded mid-swipe, and no snapshot is faked.
///
/// **Composing with drag-to-schedule.** The schedule owns a hand-rolled `DragGesture`
/// for placing and moving blocks (see `DayGridView`; the native drag APIs misbehave —
/// CLAUDE.md). This gesture must never eat it, so:
/// • it attaches with `simultaneousGesture`, the only form that co-exists with the
///   List/ScrollView pans this view wraps;
/// • it **axis-locks once per drag**: the first 12 pt decide. A drag that is not clearly
///   horizontal is marked `.rejected` and ignored for its whole lifetime, so a vertical
///   block-move or chip drag can never nudge the day sideways;
/// • while a block is lifted for a move, the parent passes `enabled: false` and the
///   gesture is masked out entirely — the lifted block owns every drag on screen.
///
/// Paging is unbounded (there is no first or last day), so there is no edge to
/// rubber-band against; every drag has a real page under it in both directions.
struct DayPager<Content: View>: View {
    let pages: [DayPage<Content>]        // previous, shown, next — in that order
    let enabled: Bool
    let onCommit: (Int) -> Void          // -1 back a day, +1 forward

    @State private var dragX: CGFloat = 0
    @State private var lock = Lock.undecided

    private enum Lock { case undecided, horizontal, rejected }

    /// The middle page — the day the schedule is actually on.
    private var shownDay: Date? { pages.count == 3 ? pages[1].day : nil }

    /// The first 12 pt of travel decide the axis, and a drag must be clearly sideways
    /// (1.6× more horizontal than vertical) to page at all.
    private let activation: CGFloat = 12
    private let dominance: CGFloat = 1.6
    /// Release past 30 % of the width completes; below that, a flick still completes if
    /// the projected (velocity-carried) travel would have cleared 60 %.
    private let commitFraction: CGFloat = 0.3
    private let flickFraction: CGFloat = 0.6
    /// …but a fraction alone would make a 900 pt iPad page demand a 270 pt drag. Both
    /// thresholds are capped so the gesture costs roughly the same travel at any width.
    /// The ceilings sit just above what the fractions resolve to on the widest iPhone
    /// (440 pt → 132 / 264), so on every phone the fraction still wins and the feel of
    /// the swipe is byte-for-byte what it was.
    private let commitCeiling: CGFloat = 140
    private let flickCeiling: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    page.content
                        .frame(width: w)
                        // A neighbour is on screen mid-swipe; a tap there would act on the
                        // wrong day. Only the shown page takes touches. (The flag sits on
                        // the pages, never on the container — disabling hit testing on the
                        // container would kill the swipe gesture itself.)
                        .allowsHitTesting(page.day == shownDay)
                }
            }
            .offset(x: -w + dragX)
            .simultaneousGesture(swipe(width: w), including: enabled ? .all : .subviews)
        }
        .clipped()
    }

    private func swipe(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: activation, coordinateSpace: .local)
            .onChanged { value in
                switch lock {
                case .undecided:
                    let dx = value.translation.width, dy = value.translation.height
                    guard max(abs(dx), abs(dy)) >= activation else { return }
                    lock = abs(dx) > abs(dy) * dominance ? .horizontal : .rejected
                    if lock == .horizontal { dragX = dx }
                    // Safety net: a previous drag cancelled without `onEnded` (another
                    // recognizer claimed it) would leave the strip parked off-centre.
                    else if dragX != 0 { withAnimation(MobileTheme.spring) { dragX = 0 } }
                case .horizontal:
                    dragX = value.translation.width
                case .rejected:
                    break
                }
            }
            .onEnded { value in
                let wasHorizontal = lock == .horizontal
                lock = .undecided
                guard wasHorizontal, w > 0 else { return }

                let dx = value.translation.width
                let projected = value.predictedEndTranslation.width
                let flicked = projected.sign == dx.sign
                    && abs(projected) > min(w * flickFraction, flickCeiling)
                guard abs(dx) > min(w * commitFraction, commitCeiling) || flicked else {
                    withAnimation(MobileTheme.spring) { dragX = 0 }   // released short — snap back
                    return
                }
                commit(dx < 0 ? 1 : -1, width: w)
            }
    }

    /// Land the swipe without a seam: advance the day and, in the same unanimated
    /// transaction, re-anchor `dragX` so the incoming page stays exactly where the finger
    /// left it (it moves from slot `1 + delta` to slot 1, a shift of `delta * width`).
    /// Only then animate the remaining distance home.
    private func commit(_ delta: Int, width w: CGFloat) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            onCommit(delta)
            dragX += CGFloat(delta) * w
        }
        withAnimation(MobileTheme.spring) { dragX = 0 }
        MobileTheme.Haptic.selection()
    }
}
