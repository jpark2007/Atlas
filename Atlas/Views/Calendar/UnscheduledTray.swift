import SwiftUI

/// The right-hand tray of unscheduled tasks (`state.unscheduledTasks`). Each
/// chip is `.draggable` onto a time slot; a context menu provides a click
/// fallback that schedules to a chosen hour or auto-suggests a free slot.
/// Clicking a chip opens a popover to set the task's due date. The tray narrows
/// to `spaceFilter` (the calendar grid stays global).
struct UnscheduledTray: View {
    let tasks: [TaskItem]
    /// "All" or a space name — narrows the tray without touching the grid.
    var spaceFilter: String = "All"
    /// Fallback scheduler — schedules the task to the given hour.
    let onSchedule: (UUID, Int) -> Void
    /// Auto-find-a-slot: pick the first free gap today and schedule there.
    var onSuggest: (UUID) -> Void = { _ in }
    /// Manual due-date editor — nil clears the due date.
    var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }

    /// Which chip's due-date popover is open.
    @State private var editingTaskID: UUID?

    /// Tasks shown after applying the space filter.
    private var displayedTasks: [TaskItem] {
        spaceFilter == "All" ? tasks : tasks.filter { $0.spaceName == spaceFilter }
    }

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("Unscheduled")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("\(displayedTasks.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }

                Text("Drag onto the grid, or use Suggest a time")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                if displayedTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AtlasTheme.Colors.green)
                        Text("All scheduled")
                            .font(.system(size: 12))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(displayedTasks) { task in
                            taskChip(task)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 250)
    }

    private func taskChip(_ task: TaskItem) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(task.spaceColor)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                if !task.dueLabel.isEmpty {
                    Text("Due \(task.dueLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        // Click → due-date editor. Drag still works (distinguished by movement).
        .onTapGesture { editingTaskID = task.id }
        .draggable(DraggableTaskID(id: task.id)) {
            // Drag preview
            EventTile(event: CalendarEvent(
                title: task.title,
                subtitle: "",
                start: Date(),
                end: Date().addingTimeInterval(3600),
                color: task.spaceColor,
                spaceName: ""
            ))
            .frame(width: 160, height: 40)
        }
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
    @State private var hasDate: Bool

    init(title: String, initialDate: Date?, onSave: @escaping (Date?) -> Void, onSuggest: @escaping () -> Void) {
        self.title = title
        self.initialDate = initialDate
        self.onSave = onSave
        self.onSuggest = onSuggest
        _date = State(initialValue: initialDate ?? Date())
        _hasDate = State(initialValue: initialDate != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(2)

            DatePicker(
                "Due",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .onChange(of: date) { _, _ in hasDate = true }

            Button {
                onSuggest()
            } label: {
                Label("Suggest a time today", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AtlasTheme.Colors.accent)

            Divider().overlay(AtlasTheme.Colors.border)

            HStack {
                Button("Clear") { onSave(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .font(.system(size: 12))
                Spacer()
                Button("Set due date") { onSave(hasDate ? date : nil) }
                    .keyboardShortcut(.defaultAction)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}
