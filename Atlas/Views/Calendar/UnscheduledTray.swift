import SwiftUI
import AtlasCore

/// The side RAIL of unscheduled tasks (`state.unscheduledTasks`) — the canonical surface
/// for planning work.
///
/// A task lives here until you drag it onto the grid, which creates a WORK SESSION for it
/// (custom pointer drag → `AppState.schedule(taskId:at:)`). Unscheduled tasks are never
/// drawn on the grid itself. There is deliberately no auto-slot "schedule this for me"
/// action: planning a session is always a deliberate drag (silent auto-scheduling is the
/// most-cited trust failure in this category). A context menu keeps a keyboard/click
/// fallback that schedules to a chosen hour. The rail hides the same spaces as the
/// calendar's category chips (`hiddenSpaces`).
struct UnscheduledTray: View {
    /// Used only to resolve a task's CLASS color and class name — the task list itself
    /// still arrives via `tasks` (the parent owns the filtering).
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tasks: [TaskItem]
    /// The shared "now" — drives the overdue (bright-red) treatment for re-planned chips.
    var now: Date = Date()
    /// Spaces hidden via the calendar's category chips — narrows the tray to match the grid.
    var hiddenSpaces: Set<String> = []
    /// Fallback scheduler — schedules the task to the given hour.
    let onSchedule: (UUID, Int) -> Void
    /// Manual due-date editor — nil clears the due date.
    var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }
    /// Check a task off — it completes and drops out of the tray.
    var onToggleDone: (UUID) -> Void = { _ in }
    /// Open a task in Atlas (the expanded card's "Open" affordance).
    var onOpenTask: (UUID) -> Void = { _ in }
    /// Live drag position (point in `calendarDragSpace`) while a chip is being dragged.
    var onDragChanged: (UUID, CGPoint) -> Void = { _, _ in }
    /// Drag released at this point (in `calendarDragSpace`) — CalendarView maps it to a slot.
    var onDragEnded: (UUID, CGPoint) -> Void = { _, _ in }
    /// Collapse the tray into the thin rail (the parent owns the collapsed state).
    var onCollapse: () -> Void = {}

    /// Which chip's due-date popover is open.
    @State private var editingTaskID: UUID?
    /// How far past this week the rail is showing. The rail opens on the current week
    /// every time — a November assignment is not this Wednesday's problem — and the
    /// footer widens the window in place.
    @State private var window: Window = .thisWeek

    enum Window: Int, Comparable {
        case thisWeek, nextWeek, all
        static func < (a: Window, b: Window) -> Bool { a.rawValue < b.rawValue }
    }
    /// The one chip expanded in place (click to open, click again to fold). At most one
    /// at a time — clicking another row moves the expansion rather than stacking cards.
    @State private var expandedTaskID: UUID?
    /// The chip currently playing its check-off animation. It stays on screen, inked and
    /// softening, until `onToggleDone` actually completes it.
    @State private var completingTaskID: UUID?

    /// Tasks shown after applying the hidden-space filter.
    private var displayedTasks: [TaskItem] {
        tasks.filter { !hiddenSpaces.contains($0.spaceName) }
    }

    /// The week horizon this rail is scoped to. Overdue work is its own bucket, pinned
    /// above the week window and never windowed away.
    private var horizons: [TaskGrouping.WeekHorizon: [TaskItem]] {
        TaskGrouping.byWeekHorizon(tasks: displayedTasks, now: now)
    }

    private func tasks(_ horizon: TaskGrouping.WeekHorizon) -> [TaskItem] {
        horizons[horizon] ?? []
    }

    /// Overdue + this week: what the rail shows by default, and what the collapsed rail's
    /// badge counts.
    static func inWeekCount(tasks: [TaskItem], now: Date) -> Int {
        let horizons = TaskGrouping.byWeekHorizon(tasks: tasks, now: now)
        return (horizons[.overdue]?.count ?? 0) + (horizons[.thisWeek]?.count ?? 0)
    }

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .atlasFont(size: 13, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    // The title never wraps — at the panel's narrow width it used to
                    // break mid-word ("Unschedule / d"). It holds one line; the summary
                    // beside it is what gives way (truncates) when the width is tight.
                    Text("Unscheduled")
                        .atlasFont(size: 15, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(window == .thisWeek
                         ? "\(tasks(.overdue).count + tasks(.thisWeek).count) this week"
                         : "\(displayedTasks.count)")
                        .atlasMono(size: 11, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                    // Collapse into the rail. chevron.right points toward the right
                    // edge the panel folds into (the rail's chevron.left brings it back).
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.right")
                            .atlasFont(size: 11, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse")
                }

                Text("Drag one onto the grid to plan a work session")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                if displayedTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AtlasTheme.Colors.green)
                        Text("All scheduled")
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 8)
                    Spacer(minLength: 0)
                } else {
                    // Anything past the panel's height used to be silently clipped —
                    // the rail is a list, so it scrolls. The chips' drag-to-schedule is a
                    // custom global-coordinate DragGesture (see `taskChip`), deliberately
                    // left untouched: on macOS a ScrollView pans by wheel/trackpad, not by
                    // a pointer drag, so the two don't compete for the same input.
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Overdue is PINNED above the week window — it can't be
                            // scrolled past on the way to Wednesday, and no footer control
                            // ever hides it.
                            if !tasks(.overdue).isEmpty {
                                TaskGroupHeader(title: "Overdue", count: tasks(.overdue).count, late: true)
                                rows(tasks(.overdue))
                            }

                            TaskGroupHeader(title: "This week · \(weekRangeLabel(offset: 0))",
                                            count: tasks(.thisWeek).count)
                            if tasks(.thisWeek).isEmpty {
                                emptyLine("Nothing unscheduled this week")
                            } else {
                                rows(tasks(.thisWeek))
                            }

                            if window >= .nextWeek, !tasks(.nextWeek).isEmpty {
                                TaskGroupHeader(title: "Next week · \(weekRangeLabel(offset: 1))",
                                                count: tasks(.nextWeek).count)
                                rows(tasks(.nextWeek))
                            }
                            if window == .all {
                                if !tasks(.later).isEmpty {
                                    TaskGroupHeader(title: "Later", count: tasks(.later).count)
                                    rows(tasks(.later))
                                }
                                if !tasks(.noDate).isEmpty {
                                    TaskGroupHeader(title: "No date", count: tasks(.noDate).count)
                                    rows(tasks(.noDate))
                                }
                            }

                            footer
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: Groups

    private func rows(_ items: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, task in
                taskChip(task)
                if i < items.count - 1 {
                    Divider().overlay(AtlasTheme.Colors.hairline)
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .atlasFont(size: 12, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.vertical, 9)
    }

    /// "Show next week (6)" → "See all 41 tasks" → "Show this week only", in that order.
    @ViewBuilder
    private var footer: some View {
        let hidden = displayedTasks.count - shownCount
        HStack(spacing: 8) {
            if window == .thisWeek, !tasks(.nextWeek).isEmpty {
                ShowMoreButton(title: "Show next week (\(tasks(.nextWeek).count))") {
                    withAnimation(AtlasTheme.taskCrossOut) { window = .nextWeek }
                }
            }
            if window != .all, hidden > 0 {
                ShowMoreButton(title: "See all \(displayedTasks.count) tasks") {
                    withAnimation(AtlasTheme.taskCrossOut) { window = .all }
                }
            }
            if window != .thisWeek {
                ShowMoreButton(title: "Show this week only") {
                    withAnimation(AtlasTheme.taskCrossOut) { window = .thisWeek }
                }
            }
        }
        .padding(.top, 14)
    }

    /// How many rows the current window is rendering.
    private var shownCount: Int {
        switch window {
        case .thisWeek: return tasks(.overdue).count + tasks(.thisWeek).count
        case .nextWeek: return tasks(.overdue).count + tasks(.thisWeek).count + tasks(.nextWeek).count
        case .all:      return displayedTasks.count
        }
    }

    /// "Aug 31 – Sep 6" — the window a group header names.
    private func weekRangeLabel(offset: Int) -> String {
        let cal = Calendar.current
        let week = TimeModel.weekInterval(offset: offset, from: now, calendar: cal)
        let last = week.end.addingTimeInterval(-1)
        let end = cal.isDate(week.start, equalTo: last, toGranularity: .month)
            ? CalendarFormat.dayNumber.string(from: last)
            : CalendarFormat.monoMonthDay.string(from: last)
        return "\(CalendarFormat.monoMonthDay.string(from: week.start)) – \(end)"
    }

    private func taskChip(_ task: TaskItem) -> some View {
        let horizon = TaskGrouping.horizon(for: task, now: now)
        // Overdue in the rail is AMBER, matching the Late bar and the 1A mockup's overdue
        // group. Red stays reserved for "due today with nothing planned".
        let overdue = horizon == .overdue
        // WHOSE work this is: the class's own color when the task's project set one, else
        // the space color, else the neutral accent. Resolved by AppState so the rail and
        // the day grid can never disagree (see `taskAccentColor` / `gridColored`).
        let accent = state.taskAccentColor(for: task)
        let ink = overdue ? AtlasTheme.Colors.late : accent
        let expanded = expandedTaskID == task.id
        let completing = completingTaskID == task.id
        return HStack(alignment: .top, spacing: 8) {
            // Check it off — completes the task; it then drops out of the tray.
            Button { completeTask(task) } label: {
                Image(systemName: completing ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 15, weight: .medium)
                    .foregroundStyle(completing ? ink : AtlasTheme.Colors.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark done")
            // The class dot — the row's whole color signal, per the mockup.
            Circle()
                .fill(ink)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .atlasFont(size: 13.5, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: expanded)
                        .multilineTextAlignment(.leading)
                    // Canvas moved the due date since this was scheduled (migration 0047) —
                    // the work block was left untouched, so this marker is the only signal
                    // the plan may no longer match the deadline.
                    if task.dueMovedFrom != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .atlasFont(size: 10, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.warning)
                            .help("Due date moved")
                    }
                }
                Text(metaLine(task, horizon: horizon, expanded: expanded))
                    .atlasFont(size: 11.5, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .lineLimit(expanded ? nil : 1)
                if expanded {
                    Button { onOpenTask(task.id) } label: {
                        HStack(spacing: 4) {
                            Text("Open")
                            Image(systemName: "arrow.up.right")
                        }
                        .atlasFont(size: 11, weight: .semibold, design: .rounded)
                        .foregroundStyle(ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open this task in Atlas")
                }
            }
            Spacer(minLength: 6)
            Text(trailingLabel(task, horizon: horizon))
                .atlasMono(size: 11.5, weight: .semibold)
                .foregroundStyle(overdue ? AtlasTheme.Colors.late : AtlasTheme.Colors.textMuted)
                .fixedSize()
                .padding(.top, 1)
        }
        .padding(.leading, overdue ? 11 : 0)
        .padding(.vertical, 9)
        // The overdue rail: a 2pt amber edge down the row, per the 1A mockup.
        .overlay(alignment: .leading) {
            if overdue {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AtlasTheme.Colors.late)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        // The compact done animation: the box inks in, the row softens and slides toward
        // the rail's edge on its way out — distinct from the main window's strikethrough,
        // which has room for a drawn line the chip does not. Reduce motion keeps the fade
        // and drops the travel.
        .opacity(completing ? 0.2 : 1)
        .offset(x: completing && !reduceMotion ? 16 : 0)
        // Hairline-separated rows on flat paper — no outlined chip, no fill. The rows are
        // a LIST (that is the density fix); the drag affordance lives in the hint line
        // above the list and in the pointer cursor.
        .contentShape(Rectangle())
        // A stationary click EXPANDS the chip in place (full title, class, due date, Open).
        // It never opens a sheet or a popover — the card grows where it already sits.
        // Setting a due date stays on the context menu ("Set due date…").
        .onTapGesture { toggleExpanded(task.id) }
        // Custom pointer drag (NOT native `.draggable`): moving the chip ≥6pt schedules it
        // onto the grid via coordinate math in CalendarView. This sidesteps the macOS green
        // "+" copy badge and the unreliable native drop, matching the prototype that worked.
        // `minimumDistance: 6` means a stationary CLICK never engages the drag, so it passes
        // through to the check-off Button (the checkbox completes instead of mis-firing) and
        // to the tap gesture above.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in onDragChanged(task.id, value.location) }
                .onEnded { value in onDragEnded(task.id, value.location) }
        )
        .contextMenu {
            Button {
                editingTaskID = task.id
            } label: {
                Label("Set due date…", systemImage: "calendar")
            }
            Divider()
            Text("Schedule to…")
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                Button(hourLabel(hour)) { onSchedule(task.id, hour) }
            }
        }
        .popover(isPresented: Binding(
            get: { editingTaskID == task.id },
            set: { if !$0 { editingTaskID = nil } }
        )) {
            DueDatePopover(
                title: task.title,
                initialDate: task.dueDate,
                onSave: { date in
                    onSetDueDate(task.id, date)
                    editingTaskID = nil
                }
            )
        }
    }

    /// Expand this chip in place, folding whichever one was open (only one at a time).
    private func toggleExpanded(_ id: UUID) {
        // The house spring the tray itself folds with — the card grows the same way.
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.3, dampingFraction: 0.85)
        withAnimation(animation) {
            expandedTaskID = expandedTaskID == id ? nil : id
        }
    }

    /// Ink the checkbox, soften the row out, THEN complete the task — so the chip's own
    /// done animation reads before the row leaves the rail.
    private func completeTask(_ task: TaskItem) {
        guard completingTaskID == nil else { return }
        withAnimation(AtlasTheme.taskCrossOut) {
            completingTaskID = task.id
            expandedTaskID = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onToggleDone(task.id)
            completingTaskID = nil
        }
    }

    /// "Calc I · Wed Sep 2" — whose work this is, and when it's due. Overdue rows name the
    /// day they were due ("· due Aug 28") rather than a weekday that has already gone by.
    private func metaLine(_ task: TaskItem, horizon: TaskGrouping.WeekHorizon, expanded: Bool) -> String {
        let owner = state.project(for: task)?.name ?? task.spaceName
        guard let due = task.effectiveDueDate() else { return owner }
        if expanded { return owner.isEmpty ? fullDueLabel(task) : "\(owner) · \(fullDueLabel(task))" }
        let when = horizon == .overdue
            ? "due \(CalendarFormat.monoMonthDay.string(from: due))"
            : CalendarFormat.monoDay.string(from: due)
        return owner.isEmpty ? when : "\(owner) · \(when)"
    }

    /// The right-hand marker: "4d late" in amber for overdue, the weekday for this week's
    /// work, a date for anything further out.
    private func trailingLabel(_ task: TaskItem, horizon: TaskGrouping.WeekHorizon) -> String {
        guard let due = task.effectiveDueDate() else { return "" }
        switch horizon {
        case .overdue:
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: task.originalDueDate ?? due),
                                          to: cal.startOfDay(for: now)).day ?? 0
            return "\(max(1, days))d late"
        case .thisWeek:
            return CalendarFormat.weekdayShort.string(from: due)
        case .nextWeek, .later:
            return CalendarFormat.monoMonthDay.string(from: due)
        case .noDate:
            return ""
        }
    }

    /// The expanded card's fuller due line — "MON AUG 24 · 5 PM", falling back to the
    /// compact label when the task carries no concrete date. An all-day due names a day,
    /// so it drops the clock half and reads from its local day anchor.
    private func fullDueLabel(_ task: TaskItem) -> String {
        guard let due = task.dueDate else { return task.dueLabel }
        guard !task.allDay else {
            return CalendarFormat.monoDay.string(from: AllDayDate.localDay(of: due, calendar: .current))
        }
        return "\(CalendarFormat.monoDay.string(from: due)) · \(CalendarFormat.hour.string(from: due))"
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return CalendarFormat.hour.string(from: date)
    }
}

/// The collapsed form of the tray: a thin vertical rail that reclaims the panel's
/// width for the grid. A chevron expands it; the tray icon + count badge keep the
/// unscheduled total glanceable. Tapping anywhere on the rail expands.
struct UnscheduledRail: View {
    let count: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .atlasFont(size: 11, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Image(systemName: "tray.full")
                    .atlasFont(size: 14, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .atlasMono(size: 10, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AtlasTheme.wash(AtlasTheme.Colors.accent), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .frame(width: 34)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show unscheduled tasks")
    }
}

/// Compact popover to set/clear a task's due date and trigger auto-scheduling.
private struct DueDatePopover: View {
    let title: String
    let initialDate: Date?
    let onSave: (Date?) -> Void

    @State private var date: Date?

    init(title: String, initialDate: Date?, onSave: @escaping (Date?) -> Void) {
        self.title = title
        self.initialDate = initialDate
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(2)

            AtlasDatePicker(date: $date)

            HStack {
                Spacer()
                Button("Set due date") { onSave(date) }
                    .keyboardShortcut(.defaultAction)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
