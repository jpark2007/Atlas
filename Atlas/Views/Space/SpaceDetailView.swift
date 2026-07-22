import SwiftUI
import AtlasCore
import TipKit

struct SpaceDetailView: View {
    @EnvironmentObject var state: AppState
    let space: Space

    /// Invite-people onboarding tip, shown only on a solo space page.
    @State private var inviteTip = AtlasTips.InvitePeople()

    /// True when nobody else shares this space yet (0 or 1 member).
    private var isOnlyMember: Bool {
        (state.spaceMembers[space.id]?.count ?? 0) <= 1
    }

    /// Whether the collapsed completed-tasks / past-events groups are expanded.
    @State private var showCompleted = false
    @State private var showPast = false
    @State private var presentInvite = false

    /// Inline name editing: click the title to edit, commit on Return or blur.
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    /// The color swatch popover anchored on the space dot.
    @State private var showColorPicker = false

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

    /// Upcoming events with recurring series collapsed to one row. Synced rows
    /// (Canvas/Google/Apple) carry no persisted recurrence id, so a "series" is
    /// keyed by identical title + source + time-of-day + duration — which is a
    /// repeat in practice, while distinct one-off events (different time or name)
    /// stay separate. Each row shows the next occurrence and how many upcoming
    /// repeats there are.
    private var collapsedSpaceEvents: [(event: CalendarEvent, count: Int)] {
        var order: [String] = []
        var groups: [String: [CalendarEvent]] = [:]
        for ev in spaceEvents {
            let key = seriesKey(ev)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(ev)
        }
        return order.map { key in
            let evs = groups[key]!.sorted { $0.start < $1.start }
            return (evs.first!, evs.count)
        }
    }

    /// The key that folds repeats of the same event into one row (see above).
    private func seriesKey(_ e: CalendarEvent) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: e.start)
        let minutes = Int(e.end.timeIntervalSince(e.start) / 60)
        return "\(e.title)|\(e.spaceName)|\(e.source.displayName)|\(c.hour ?? 0):\(c.minute ?? 0)|\(minutes)"
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
            // Color dot — opens the token swatch popover to change spaces.color_token.
            Button { showColorPicker = true } label: {
                Circle().fill(space.color).frame(width: 14, height: 14)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Change space color")
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                colorPickerPopover
            }

            // Name — click to edit in place; commit on Return or blur.
            if isEditingName {
                TextField("Space name", text: $draftName)
                    .textFieldStyle(.plain)
                    .atlasTitleSerif(size: 26)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .focused($nameFieldFocused)
                    .frame(maxWidth: 360)
                    .onSubmit(commitName)
                    .onChange(of: nameFieldFocused) { focused in
                        if !focused { commitName() }
                    }
            } else {
                Text(space.name)
                    .atlasTitleSerif(size: 26)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .onTapGesture {
                        draftName = space.name
                        isEditingName = true
                        nameFieldFocused = true
                    }
                    .help("Click to rename")
            }
            Spacer()
            Button {
                presentInvite = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus").atlasFont(size: 11, weight: .semibold)
                    Text("Invite people").atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .help("Invite someone to collaborate on this space")
            .onboardingTip(inviteTip, when: isOnlyMember, arrowEdge: .bottom)
            .sheet(isPresented: $presentInvite) {
                InviteToSpaceSheet(spaceId: space.id, spaceName: space.name)
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
                        .atlasFont(size: 17)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .help(task.done ? "Mark not done" : "Mark done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
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
                    .atlasFont(size: 10, weight: .medium)
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
                let rows = collapsedSpaceEvents
                ForEach(Array(rows.enumerated()), id: \.element.event.id) { i, pair in
                    LifecycleEventRow(event: pair.event)
                        .overlay(alignment: .trailing) {
                            if pair.count > 1 {
                                Text("recurring · \(pair.count)")
                                    .atlasMono(size: 10, weight: .medium)
                                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                            }
                        }
                    if i < rows.count - 1 {
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
                .atlasFont(size: 31, weight: .light)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("No tasks or events in \(space.name) yet.")
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).atlasCapsLabel()
    }

    /// Persist the edited name (rename carries all referencing items along) and
    /// leave edit mode. A blank or unchanged name is discarded by `renameSpace`.
    private func commitName() {
        guard isEditingName else { return }
        isEditingName = false
        state.renameSpace(id: space.id, to: draftName)
    }

    /// The dense swatch grid + hex field shown in the dot popover to change the space color.
    private var colorPickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPACE COLOR").atlasCapsLabel()
            AtlasColorGrid(selected: space.color) { color in
                state.setSpaceColor(id: space.id, color: color)
            }
        }
        .padding(16)
    }
}

private extension View {
    /// Attach an onboarding tip only while `condition` holds — the macOS 14-safe form of a
    /// conditional `.popoverTip` (the optional-tip overload needs macOS 26).
    @ViewBuilder
    func onboardingTip(_ tip: some Tip, when condition: Bool, arrowEdge: Edge = .top) -> some View {
        if condition { popoverTip(tip, arrowEdge: arrowEdge) } else { self }
    }
}
