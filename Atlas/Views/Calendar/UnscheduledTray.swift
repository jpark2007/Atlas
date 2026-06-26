import SwiftUI

/// The right-hand tray of unscheduled tasks (`state.unscheduledTasks`). Each
/// chip is `.draggable` onto a time slot; a context menu provides a click
/// fallback that schedules to a chosen hour.
struct UnscheduledTray: View {
    let tasks: [TaskItem]
    /// Fallback scheduler — schedules the task to the given hour.
    let onSchedule: (UUID, Int) -> Void

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
                    Text("\(tasks.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }

                Text("Drag onto the grid to schedule")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                if tasks.isEmpty {
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
                        ForEach(tasks) { task in
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
            Text("Schedule to…")
            ForEach(CalendarLayout.startHour..<CalendarLayout.endHour, id: \.self) { hour in
                Button(hourLabel(hour)) { onSchedule(task.id, hour) }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return CalendarFormat.hour.string(from: date)
    }
}
