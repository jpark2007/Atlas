import SwiftUI
import AtlasCore

/// The dashboard, restructured to the locked Phase-3 mockup (spec 3.1):
/// a tiny mono greeting/date title bar, then a two-column body — a main column
/// (live clock · today's focus · recent notes) beside a right rail (an outlined
/// mini-month date navigator · the selected day's agenda).
///
/// The rail (navigator + agenda, its own `selectedDay`/`visibleMonth`) lives in
/// `MiniMonthAgenda`, shared with the menu-bar calendar popup. The focus list is
/// always the next upcoming OPEN tasks by deadline, NEVER the rail's selected
/// day (a fixed glance at what's next, per the binding data semantics).
struct DashboardView: View {
    @EnvironmentObject var state: AppState

    /// How many upcoming tasks the focus list shows.
    private let focusCount = 8

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                titleBar

                GetStartedCard()

                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 26) {
                        clockBlock
                        // Late bar sits above the day's work — overdue is the first thing
                        // you see, never something you scroll past.
                        LateBar(compact: true, onOpenTask: { state.route = .task($0) })
                            .environmentObject(state)
                        focusList
                        dueTodayRail
                        tonightsWork
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    MiniMonthAgenda(onOpenCalendar: { state.route = .calendar })
                        .frame(width: 348)
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Title bar (tiny mono greeting left · date right)

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(greeting)
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.4)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Spacer()
            Text(titleDate)
                .atlasMono(size: 11, weight: .semibold)
                .tracking(1.4)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// Time-of-day greeting, uppercased ("GOOD AFTERNOON"), driven by `state.now`.
    /// Appends the user's nickname when set ("GOOD MORNING, DREW"); plain otherwise.
    private var greeting: String {
        let timeOfDay: String
        switch calendar.component(.hour, from: state.now) {
        case 5..<12:  timeOfDay = "GOOD MORNING"
        case 12..<17: timeOfDay = "GOOD AFTERNOON"
        default:      timeOfDay = "GOOD EVENING"
        }
        let name = state.nickname.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? timeOfDay : "\(timeOfDay), \(name.uppercased())"
    }

    /// "MON — JUL 6, 2026" — driven by `state.now`.
    private var titleDate: String {
        "\(DashFmt.weekdayShort.string(from: state.now)) — \(DashFmt.monthDayYear.string(from: state.now))"
            .uppercased()
    }

    // MARK: - Clock block (live 12-hour clock + dateline, plain on paper)

    /// Huge mono ink digits, clay colons, muted seconds, small AM/PM; a mono
    /// dateline below; a hairline under the whole block. No panel, no boxes, no
    /// flip animation. `TimelineView` ticks it once a second.
    private var clockBlock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                clockDigits(context.date)
                Text(dateline(context.date))
                    .atlasMono(size: 12, weight: .medium)
                    .tracking(1.6)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .atlasHairlineBelow()
        }
    }

    private func clockDigits(_ date: Date) -> some View {
        let h24 = calendar.component(.hour, from: date)
        let h = h24 % 12 == 0 ? 12 : h24 % 12
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let ampm = h24 < 12 ? "AM" : "PM"
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            bigDigit("\(h)")
            bigColon
            bigDigit(String(format: "%02d", m))
            Text(":")
                .atlasMono(size: 26, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.accent)
                .padding(.leading, 4)
            Text(String(format: "%02d", s))
                .atlasMono(size: 26, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(ampm)
                .atlasMono(size: 15, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.leading, 8)
        }
    }

    private func bigDigit(_ s: String) -> some View {
        Text(s)
            .atlasMono(size: 64, weight: .semibold)
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
    }

    private var bigColon: some View {
        Text(":")
            .atlasMono(size: 64, weight: .semibold)
            .foregroundStyle(AtlasTheme.Colors.accent)
    }

    /// "MONDAY —— JUL 6 / 2026".
    private func dateline(_ date: Date) -> String {
        let day = DashFmt.weekdayFull.string(from: date).uppercased()
        let md  = DashFmt.monthDay.string(from: date).uppercased()
        let yr  = DashFmt.year.string(from: date)
        return "\(day) —— \(md) / \(yr)"
    }

    // MARK: - Focus list (next upcoming open tasks — NOT the selected day)

    private var focusList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S FOCUS").atlasCapsLabel()

            let tasks = focusTasks
            if tasks.isEmpty {
                Text("Nothing due — you're clear.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasks) { task in focusRow(task) }
                }
            }

            addTaskAffordance
        }
    }

    /// The next `focusCount` OPEN tasks ordered by deadline: dated before undated,
    /// earliest `dueDate` first, `scheduledAt` as the tiebreaker. Independent of
    /// the calendar selection (a fixed "what's next" glance).
    private var focusTasks: [TaskItem] {
        // Just-checked tasks linger (struck-through) before sliding out.
        let open = state.tasks.filter(state.isVisiblyPending)
        let sorted = open.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?):
                if da != db { return da < db }
                return (a.scheduledAt ?? .distantFuture) < (b.scheduledAt ?? .distantFuture)
            case (_?, nil): return true       // dated tasks come before undated
            case (nil, _?): return false
            case (nil, nil):
                return (a.scheduledAt ?? .distantFuture) < (b.scheduledAt ?? .distantFuture)
            }
        }
        return Array(sorted.prefix(focusCount))
    }

    private func focusRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(task.id) }
            } label: {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 15)
                    .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help(task.done ? "Mark not done" : "Mark done")

            Button { state.route = .task(task.id) } label: {
                HStack(spacing: 8) {
                    Text(task.title)
                        .atlasFont(size: 14, design: .rounded)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !task.dueLabel.isEmpty {
                        Text(task.dueLabel)
                            .atlasMono(size: 11, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    if !task.spaceName.isEmpty {
                        atlasTag(text: task.spaceName, color: task.spaceColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    /// Plain text affordance (not a boxed input) — opens the existing quick capture.
    private var addTaskAffordance: some View {
        Button { state.presentCapture = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
                Text("Add a task")
                    .atlasFont(size: 13, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - Due today (the one place red is earned)

    /// Everything due TODAY, as due markers rather than blocks — a deadline is a boundary,
    /// not an occupancy. A row turns red only when it's due today AND no work time is
    /// planned for it; that's the entire red budget in Atlas.
    @ViewBuilder
    private var dueTodayRail: some View {
        let due = dueTodayTasks
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("DUE TODAY").atlasCapsLabel()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(due) { task in dueRow(task) }
                }
            }
        }
    }

    private var dueTodayTasks: [TaskItem] {
        state.tasks
            .filter { state.isVisiblyPending($0) && ($0.dueDate.map { calendar.isDate($0, inSameDayAs: state.now) } ?? false) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private func dueRow(_ task: TaskItem) -> some View {
        let unplanned = TimeModel.isDueTodayUnplanned(task, now: state.now)
        let sessions = task.scheduledAt == nil ? [] : [task.durationMin ?? 60]
        return HStack(spacing: 10) {
            Button {
                withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(task.id) }
            } label: {
                Image(systemName: "square")
                    .atlasFont(size: 15)
                    .foregroundStyle(unplanned ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Mark done")

            Button { state.route = .task(task.id) } label: {
                HStack(spacing: 8) {
                    // Colour still says WHOSE.
                    Circle().fill(task.spaceColor).frame(width: 6, height: 6)
                    Text(task.title)
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(TimeModel.plannedLabel(estimateMin: task.estimateMin, sessionMinutes: sessions))
                        .atlasMono(size: 11, weight: .medium)
                        .foregroundStyle(unplanned ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Tonight's work (the sessions you actually planned)

    @ViewBuilder
    private var tonightsWork: some View {
        let sessions = tonightsSessions
        VStack(alignment: .leading, spacing: 12) {
            Text("TONIGHT'S WORK").atlasCapsLabel()
            if sessions.isEmpty {
                Text("No work sessions planned. Drag a task onto the calendar to plan one.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sessions) { session in sessionRow(session) }
                }
            }
        }
    }

    /// Work sessions still ahead of you today — a plan, not a commitment, so past ones
    /// (which are history) stay off this list.
    private var tonightsSessions: [CalendarEvent] {
        state.scheduledWorkBlocks(on: state.now)
            .filter { !$0.isHistory && $0.end >= state.now }
            .sorted { $0.start < $1.start }
    }

    private func sessionRow(_ session: CalendarEvent) -> some View {
        Button { state.route = .task(session.id) } label: {
            HStack(spacing: 10) {
                Text(session.timeLabel)
                    .atlasMono(size: 11, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 62, alignment: .trailing)
                // Dashed spine — the same "planned, movable" language the grid tile uses.
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(session.color, style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                    .frame(width: 3, height: 22)
                Text(session.title)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(session.durationLabel)
                    .atlasMono(size: 11, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cached formatters

/// Cached `DateFormatter`s for the dashboard's mono datelines. Strings that mix
/// em-dashes / slashes are composed in code from these plain patterns so no
/// literal-quoting is needed.
private enum DashFmt {
    static let weekdayShort  = formatter("EEE")
    static let weekdayFull   = formatter("EEEE")
    static let monthDay      = formatter("MMM d")
    static let monthDayYear  = formatter("MMM d, yyyy")
    static let year          = formatter("yyyy")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}
