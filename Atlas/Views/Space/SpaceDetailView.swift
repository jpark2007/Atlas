import SwiftUI
import AtlasCore

struct SpaceDetailView: View {
    @EnvironmentObject var state: AppState
    let space: Space

    private var spaceTasks: [TaskItem] {
        state.tasks
            .filter { $0.spaceName == space.name }
            .sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return $0.title < $1.title
                }
            }
    }

    private var spaceEvents: [CalendarEvent] {
        state.events
            .filter { $0.spaceName == space.name }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !spaceTasks.isEmpty  { tasksSection }
                if !spaceEvents.isEmpty { eventsSection }
                if spaceTasks.isEmpty && spaceEvents.isEmpty { emptyState }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(space.color).frame(width: 14, height: 14)
            Text(space.name)
                .atlasTitleSerif(size: 26)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Text("\(spaceTasks.count) tasks · \(spaceEvents.count) events")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TASKS")
            VStack(spacing: 0) {
                ForEach(Array(spaceTasks.enumerated()), id: \.element.id) { i, task in
                    taskRow(task)
                    if i < spaceTasks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        Button { state.route = .task(task.id) } label: {
            HStack(spacing: 12) {
                Button {
                    state.toggleTask(task.id)
                } label: {
                    Image(systemName: task.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    if !task.dueLabel.isEmpty {
                        Text("Due \(task.dueLabel)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("EVENTS")
            VStack(spacing: 0) {
                ForEach(Array(spaceEvents.enumerated()), id: \.element.id) { i, event in
                    eventRow(event)
                    if i < spaceEvents.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("\(event.timeLabel) · \(event.durationLabel)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("No tasks or events in \(space.name) yet.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).atlasCapsLabel()
    }
}
