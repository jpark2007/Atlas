import SwiftUI
import AtlasCore

struct SpaceDetailView: View {
    @EnvironmentObject var state: AppState
    let space: Space

    /// Whether the collapsed completed-tasks / past-events groups are expanded.
    @State private var showCompleted = false
    @State private var showPast = false
    @State private var presentInvite = false

    private var allTasks: [TaskItem] {
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

    /// Open tasks (plus just-checked ones still lingering) — the default list.
    private var spaceTasks: [TaskItem] {
        allTasks.filter(state.isVisiblyPending)
    }

    /// Checked-off tasks behind the "N COMPLETED" reveal, newest finish first.
    private var completedTasks: [TaskItem] {
        allTasks
            .filter(state.isSettledDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var allEvents: [CalendarEvent] {
        state.events
            .filter { $0.spaceName == space.name }
            .sorted { $0.start < $1.start }
    }

    /// Upcoming (or still in progress) events — the default list.
    private var spaceEvents: [CalendarEvent] {
        allEvents.filter { $0.end >= state.now }
    }

    /// Elapsed events behind the "N PAST" reveal, most recent first.
    private var pastEvents: [CalendarEvent] {
        allEvents.filter { $0.end < state.now }.sorted { $0.start > $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !spaceTasks.isEmpty || !completedTasks.isEmpty { tasksSection }
                if !spaceEvents.isEmpty || !pastEvents.isEmpty    { eventsSection }
                if allTasks.isEmpty && allEvents.isEmpty { emptyState }
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
            Button {
                presentInvite = true
            } label: {
                Text("Invite")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $presentInvite) {
                InviteToSpaceSheet(spaceId: space.id)
            }
            // Counts describe the visible (pending/upcoming) lists — a finished
            // space saying "0 tasks" above a 30-COMPLETED reveal would read wrong.
            Text("\(spaceTasks.count) open · \(spaceEvents.count) upcoming")
                .atlasMono(size: 12)
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
            if !completedTasks.isEmpty {
                RevealRow(count: completedTasks.count, noun: "COMPLETED", isOpen: $showCompleted)
                if showCompleted {
                    VStack(spacing: 0) {
                        ForEach(Array(completedTasks.enumerated()), id: \.element.id) { i, task in
                            taskRow(task)
                            if i < completedTasks.count - 1 {
                                Divider().overlay(AtlasTheme.Colors.hairline)
                            }
                        }
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
                            .atlasMono(size: 11)
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
                    LifecycleEventRow(event: event)
                    if i < spaceEvents.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
            if !pastEvents.isEmpty {
                RevealRow(count: pastEvents.count, noun: "PAST", isOpen: $showPast)
                if showPast {
                    VStack(spacing: 0) {
                        ForEach(Array(pastEvents.enumerated()), id: \.element.id) { i, event in
                            LifecycleEventRow(event: event, dimmed: true)
                            if i < pastEvents.count - 1 {
                                Divider().overlay(AtlasTheme.Colors.hairline)
                            }
                        }
                    }
                }
            }
        }
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
