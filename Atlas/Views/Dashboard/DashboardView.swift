import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 18) {
                    // Schedule + tasks stacked on the left so tasks sit directly under
                    // the schedule (no dead space); focus/goals/metrics on the right.
                    VStack(spacing: 18) {
                        ScheduleCard(entries: state.todaysEvents)
                        DashboardTasksSection()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        FocusCard()
                        GoalsCard(goals: state.goals)
                        MetricsCard()
                    }
                    .frame(width: 320)
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(todayKicker)
                    .font(AtlasTheme.Font.kicker())
                    .tracking(1.4)
                    .foregroundStyle(AtlasTheme.Colors.accent)
                Text("\(greeting), \(state.userName)")
                    .font(AtlasTheme.Font.greeting())
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Spacer()
        }
    }

    /// Live date kicker (e.g. "THURSDAY · JUNE 26"), driven by `state.now` so it
    /// refreshes as the day rolls over — replaces the old hardcoded mock string.
    private var todayKicker: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: state.now).uppercased()
    }

    /// Time-of-day greeting, driven by `state.now`.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: state.now) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - Schedule card

struct ScheduleCard: View {
    @EnvironmentObject var state: AppState
    let entries: [CalendarEvent]

    private let rowHeight: CGFloat = 52

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Today's schedule")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Button { state.route = .calendar } label: {
                        HStack(spacing: 4) {
                            Text("Open calendar")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                if entries.isEmpty {
                    Text("Nothing scheduled today.")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.vertical, 18)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        scheduleRow(entry)
                        if index < entries.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.border).padding(.leading, 64)
                        }
                    }
                }
            }
        }
    }

    private func scheduleRow(_ entry: CalendarEvent) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(entry.timeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 50, alignment: .leading)
            // Work-blocks (scheduled tasks) get a dashed bar so they read as planned work.
            if entry.isWorkBlock {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(entry.color, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                    .frame(width: 4, height: 30)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(entry.color)
                    .frame(width: 3, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            Text(entry.durationLabel)
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(height: rowHeight)
    }
}

// MARK: - Tasks section (full-width, grouped by due-date bucket)

/// The all-tasks list, moved out of the cramped right rail into a full-width
/// section under "Today's schedule." Tasks are grouped under due-date headings
/// (Overdue / Today / This week / Later / No date) via `TaskGrouping`, with an
/// optional space filter above the groups.
struct DashboardTasksSection: View {
    @EnvironmentObject var state: AppState

    @State private var expandedSpaces: Set<String> = []
    /// Tasks fading out before deletion (completed 2 s ago).
    @State private var fadingOut: Set<UUID> = []

    private var spaceOrder: [String] { state.spaces.map(\.name) }

    private var visibleTasks: [TaskItem] {
        state.tasks.filter { !fadingOut.contains($0.id) }
    }

    private var groups: [(spaceName: String, tasks: [TaskItem])] {
        TaskGrouping.bySpace(tasks: visibleTasks, spaceOrder: spaceOrder)
    }

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                addAffordance

                if groups.isEmpty {
                    Text("No tasks yet — add one above.")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.spaceName) { index, group in
                        spaceSection(group)
                        if index < groups.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.border)
                        }
                    }
                }
            }
        }
        .onAppear { expandedSpaces = Set(groups.map(\.spaceName)) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tasks").font(AtlasTheme.Font.cardTitle())
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("\(visibleTasks.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
        }
    }

    // MARK: Space sections

    private func spaceSection(_ group: (spaceName: String, tasks: [TaskItem])) -> some View {
        let isExpanded = Binding(
            get: { expandedSpaces.contains(group.spaceName) },
            set: { if $0 { expandedSpaces.insert(group.spaceName) }
                  else   { expandedSpaces.remove(group.spaceName) } }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: 2) {
                ForEach(group.tasks) { task in taskRow(task) }
            }
            .padding(.top, 4)
        } label: {
            spaceHeading(group.spaceName, count: group.tasks.count)
        }
    }

    private func spaceHeading(_ name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.spaces.first { $0.name == name }?.color ?? AtlasTheme.Colors.accent)
                .frame(width: 7, height: 7)
            Text(name.uppercased())
                .font(AtlasTheme.Font.sectionLabel())
                .tracking(1.1)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
        }
    }

    // MARK: Affordances

    private var addAffordance: some View {
        Button { state.presentCapture = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.accent)
                Text("Add a task — Atlas files it for you")
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Text("⌘⇧K")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(AtlasTheme.Colors.bgElevated.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Task row

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            // Checkbox — toggles done and schedules deletion
            Button {
                let wasDone = task.done
                state.toggleTask(task.id)
                if !wasDone { scheduleRemoval(task.id) }
            } label: {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)

            // Row body — navigates to task detail
            Button { state.route = .task(task.id) } label: {
                HStack(spacing: 0) {
                    Text(task.title)
                        .font(.system(size: 13))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    Spacer()
                    if !task.dueLabel.isEmpty {
                        Text(task.dueLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AtlasTheme.Colors.accent.opacity(0.85))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.leading, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func scheduleRemoval(_ id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.25)) { fadingOut.insert(id) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            state.deleteTask(id: id)
            fadingOut.remove(id)
        }
    }
}

// MARK: - Focus card

struct FocusCard: View {
    var body: some View {
        AtlasCard {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .frame(width: 34, height: 34)
                    .background(AtlasTheme.Colors.accent.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus session")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("25 min · Pomodoro")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Goals card

struct GoalsCard: View {
    let goals: [Goal]

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("Long-term goals")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                ForEach(goals) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Spacer()
                            Text(goal.label)
                                .font(.system(size: 10))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AtlasTheme.Colors.bgElevated)
                                Capsule()
                                    .fill(LinearGradient(colors: [AtlasTheme.Colors.accent, AtlasTheme.Colors.accentDeep],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * goal.progress))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }
}
