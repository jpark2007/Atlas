import SwiftUI
import AtlasCore

/// The right-hand tray of unscheduled tasks (`state.unscheduledTasks`). Each
/// chip is `.draggable` onto a time slot; a context menu provides a click
/// fallback that schedules to a chosen hour or auto-suggests a free slot.
/// Clicking a chip opens a popover to set the task's due date. The tray hides the
/// same spaces as the calendar's category chips (`hiddenSpaces`).
struct UnscheduledTray: View {
    let tasks: [TaskItem]
    /// The shared "now" — drives the overdue (bright-red) treatment for re-planned chips.
    var now: Date = Date()
    /// Spaces hidden via the calendar's category chips — narrows the tray to match the grid.
    var hiddenSpaces: Set<String> = []
    /// Sidebar space order — used to sort collapsible sections.
    var spaceOrder: [String] = []
    /// Fallback scheduler — schedules the task to the given hour.
    let onSchedule: (UUID, Int) -> Void
    /// Auto-find-a-slot: pick the first free gap today and schedule there.
    var onSuggest: (UUID) -> Void = { _ in }
    /// Manual due-date editor — nil clears the due date.
    var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }
    /// Check a task off — it completes and drops out of the tray.
    var onToggleDone: (UUID) -> Void = { _ in }
    /// Live drag position (point in `calendarDragSpace`) while a chip is being dragged.
    var onDragChanged: (UUID, CGPoint) -> Void = { _, _ in }
    /// Drag released at this point (in `calendarDragSpace`) — CalendarView maps it to a slot.
    var onDragEnded: (UUID, CGPoint) -> Void = { _, _ in }

    /// Which chip's due-date popover is open.
    @State private var editingTaskID: UUID?
    /// Which space sections are expanded (all open by default).
    @State private var expandedSpaces: Set<String> = []

    /// Tasks shown after applying the hidden-space filter.
    private var displayedTasks: [TaskItem] {
        tasks.filter { !hiddenSpaces.contains($0.spaceName) }
    }

    private var groups: [(spaceName: String, tasks: [TaskItem])] {
        TaskGrouping.bySpace(tasks: displayedTasks, spaceOrder: spaceOrder)
    }

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Text("Unscheduled")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("\(displayedTasks.count)")
                        .atlasMono(size: 11, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }

                Text("Drag onto the grid, or use Suggest a time")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                if displayedTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AtlasTheme.Colors.green)
                        Text("All scheduled")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(groups.enumerated()), id: \.element.spaceName) { index, group in
                            spaceSection(group)
                            if index < groups.count - 1 {
                                Divider().overlay(AtlasTheme.Colors.border)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 250)
        .onAppear { expandedSpaces = Set(groups.map(\.spaceName)) }
    }

    // MARK: Space section

    private func spaceSection(_ group: (spaceName: String, tasks: [TaskItem])) -> some View {
        let isExpanded = Binding(
            get: { expandedSpaces.contains(group.spaceName) },
            set: { if $0 { expandedSpaces.insert(group.spaceName) }
                  else   { expandedSpaces.remove(group.spaceName) } }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: 8) {
                ForEach(group.tasks) { task in taskChip(task) }
            }
            .padding(.top, 6)
        } label: {
            spaceLabel(group.spaceName, count: group.tasks.count)
        }
    }

    private func spaceLabel(_ name: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(spaceColor(for: name))
                .frame(width: 7, height: 7)
            Text(name.uppercased())
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.1)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("\(count)")
                .atlasMono(size: 10, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
        }
    }

    private func spaceColor(for name: String) -> Color {
        // Match the chip's own spaceColor when available, fallback to accent.
        tasks.first { $0.spaceName == name }?.spaceColor ?? AtlasTheme.Colors.accent
    }

    private func taskChip(_ task: TaskItem) -> some View {
        // Overdue tasks that returned to the tray to be re-planned read bright red — the
        // same danger color the overdue deadline pill uses (don't invent a new red).
        let overdue = task.isOverdue(now: now)
        return HStack(spacing: 9) {
            // Check it off — completes the task; it then drops out of the tray.
            Button { onToggleDone(task.id) } label: {
                Image(systemName: "square")
                    .font(.system(size: 15))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark done")
            RoundedRectangle(cornerRadius: 2)
                .fill(overdue ? AtlasTheme.Colors.danger : task.spaceColor)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(overdue ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                if !task.dueLabel.isEmpty {
                    atlasTag(text: "Due \(task.dueLabel)", color: overdue ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // A grabbable chip: transparent on the cream bg, a hairline outline for the
        // drag affordance (overdue keeps the danger tint + red outline).
        .background(overdue ? AtlasTheme.wash(AtlasTheme.Colors.danger) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                .strokeBorder(overdue ? AtlasTheme.Colors.danger : AtlasTheme.Colors.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        // Custom pointer drag (NOT native `.draggable`): moving the chip ≥6pt schedules it
        // onto the grid via coordinate math in CalendarView. This sidesteps the macOS green
        // "+" copy badge and the unreliable native drop, matching the prototype that worked.
        // `minimumDistance: 6` means a stationary CLICK never engages the drag, so it passes
        // through to the check-off Button (the checkbox completes instead of mis-firing).
        // Setting a due date is via the context menu ("Set due date…") — no chip-body tap,
        // which would otherwise fight both the drag and the checkbox.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in onDragChanged(task.id, value.location) }
                .onEnded { value in onDragEnded(task.id, value.location) }
        )
        .contextMenu {
            Button {
                onSuggest(task.id)
            } label: {
                Label("Suggest a time", systemImage: "wand.and.stars")
            }
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
                },
                onSuggest: {
                    onSuggest(task.id)
                    editingTaskID = nil
                }
            )
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return CalendarFormat.hour.string(from: date)
    }
}

/// Compact popover to set/clear a task's due date and trigger auto-scheduling.
private struct DueDatePopover: View {
    let title: String
    let initialDate: Date?
    let onSave: (Date?) -> Void
    let onSuggest: () -> Void

    @State private var date: Date

    init(title: String, initialDate: Date?, onSave: @escaping (Date?) -> Void, onSuggest: @escaping () -> Void) {
        self.title = title
        self.initialDate = initialDate
        self.onSave = onSave
        self.onSuggest = onSuggest
        _date = State(initialValue: initialDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(2)

            DatePicker(
                "Due",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)
            .labelsHidden()

            Button {
                onSuggest()
            } label: {
                Label("Suggest a time today", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.Colors.accentText)

            Divider().overlay(AtlasTheme.Colors.border)

            HStack {
                Button("Clear") { onSave(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .font(.system(size: 12, design: .rounded))
                Spacer()
                Button("Set due date") { onSave(date) }
                    .keyboardShortcut(.defaultAction)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}
