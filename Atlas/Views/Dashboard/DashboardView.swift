import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 18) {
                    ScheduleCard(entries: state.todaysEvents)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        TasksCard()
                        FocusCard()
                        GoalsCard(goals: state.goals)
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
                Text("THURSDAY · JUNE 26")
                    .font(AtlasTheme.Font.kicker())
                    .tracking(1.4)
                    .foregroundStyle(AtlasTheme.Colors.accent)
                Text("Good morning, \(state.userName)")
                    .font(AtlasTheme.Font.greeting())
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Spacer()
            HStack(spacing: 22) {
                statBlock(value: "\(state.tasks.count)", label: "tasks today", accent: false)
                statBlock(value: "10", label: "free hours", accent: true)
            }
        }
    }

    private func statBlock(value: String, label: String, accent: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
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
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 3, height: 30)
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

// MARK: - Tasks card

struct TasksCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Tasks").font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("\(state.tasks.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("Add a task — Atlas files it for you")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Spacer()
                    Image(systemName: "return")
                        .font(.system(size: 10))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(spacing: 2) {
                    ForEach(state.tasks) { task in
                        Button { state.toggleTask(task.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
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
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
