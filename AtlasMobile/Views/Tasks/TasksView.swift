import SwiftUI
import AtlasCore

/// The Tasks tab (spec §4.3): all open tasks under a Project | Due grouping toggle.
/// Reuses the shared `TaskGrouping` (same buckets as the Mac). Honors the shared
/// space filter; check off inline; swipe to set a time or delete.
struct TasksView: View {
    @EnvironmentObject private var store: MobileStore

    @AppStorage("tasksGrouping") private var grouping = "project"   // "project" (shown "Space") | "due"
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""
    @State private var timing: TaskItem?
    @State private var detail: ItemDetailSheet.Detail?
    @State private var showSettings = false

    /// Space section headers the user has folded shut, keyed by space name.
    @State private var collapsedSpaces: Set<String> = []

    /// Rows checked off in this session linger ~0.9 s (strikethrough + filled
    /// check) before sliding out, so completion is felt, not a blink.
    @State private var justCompleted: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tasks").edScreenTitle()
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

            groupingToggle
                .padding(.horizontal, 28)
                .padding(.top, 16)

            if useHierarchy {
                // SPACE mode always shows the spaces → projects cascade — even with
                // zero tasks — so a fresh account sees its structure. "all clear" is
                // kept only for the date-driven DUE mode (and the no-spaces fallback).
                spaceList
            } else if openTasks.isEmpty {
                ScrollView {
                    emptyContent
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
                .contentMargins(.bottom, 72, for: .scrollContent)
                .refreshable { await store.refresh() }
            } else {
                list
            }
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .sheet(item: $timing) { task in
            SetTimeSheet(task: task, day: task.dueDate ?? Date()) { updated in
                Task { await store.updateTask(updated) }
            }
        }
        .sheet(item: $detail) { detail in
            ItemDetailSheet(detail: detail).environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
    }

    /// Empty-state body: a spinner while loading, else the calm all-clear copy.
    /// DUE mode gets deadline-specific copy; the no-spaces SPACE fallback keeps
    /// the generic "all clear" text.
    @ViewBuilder
    private var emptyContent: some View {
        if store.loading {
            ProgressView().tint(MobileTheme.muted)
        } else if grouping == "due" {
            Text("No upcoming deadlines").edCapsLabel()
        } else {
            Text("all clear").edCapsLabel()
        }
    }

    // MARK: - Grouping toggle (two caps labels over a thin rule)

    private var groupingToggle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                segment("Space", value: "project")
                segment("Due", value: "due")
                Spacer()
            }
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
        }
    }

    private func segment(_ title: String, value: String) -> some View {
        Button { grouping = value } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.96).textCase(.uppercase)
                .foregroundStyle(grouping == value ? MobileTheme.ink : MobileTheme.faint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List (flat: Due buckets, or the no-spaces space fallback)

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.tasks) { task in
                        taskRow(task)
                    }
                } header: {
                    Text(group.title)
                        .edCapsLabel()
                        .textCase(nil)
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .refreshable { await store.refresh() }
    }

    // MARK: - Space list (hierarchical: space → project, fold-downs)

    private var spaceList: some View {
        List {
            ForEach(spaceGroups, id: \.spaceName) { group in
                Section {
                    if !collapsedSpaces.contains(group.spaceName) {
                        // No-project tasks lead; then a subgroup per project.
                        ForEach(group.looseTasks) { task in
                            taskRow(task)
                        }
                        ForEach(group.projectGroups, id: \.projectName) { pg in
                            projectSubheader(pg.projectName)
                            if pg.tasks.isEmpty {
                                emptyProjectHint
                            } else {
                                ForEach(pg.tasks) { task in
                                    taskRow(task)
                                }
                            }
                        }
                    }
                } header: {
                    spaceHeader(group)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .refreshable { await store.refresh() }
    }

    /// A collapsible space section header: a rotating chevron beside the caps name.
    private func spaceHeader(_ group: SpaceGroup) -> some View {
        let collapsed = collapsedSpaces.contains(group.spaceName)
        return Button {
            MobileTheme.Haptic.selection()
            withAnimation(MobileTheme.spring) {
                if collapsed { collapsedSpaces.remove(group.spaceName) }
                else { collapsedSpaces.insert(group.spaceName) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MobileTheme.faint)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Text(group.spaceName)
                    .edCapsLabel()
                    .textCase(nil)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A project subheader — smaller/fainter than the space header above it.
    private func projectSubheader(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.88)
            .textCase(.uppercase)
            .foregroundStyle(MobileTheme.faint)
            .listRowInsets(EdgeInsets(top: 10, leading: 28, bottom: 4, trailing: 28))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A muted placeholder shown under a project that has no open tasks yet.
    private var emptyProjectHint: some View {
        Text("No tasks yet")
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .listRowInsets(EdgeInsets(top: 2, leading: 28, bottom: 12, trailing: 28))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// One task row + its insets/separator/swipes — shared by both lists.
    private func taskRow(_ task: TaskItem) -> some View {
        row(task)
            .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(MobileTheme.hairline)
            .swipeActions(edge: .trailing) {
                // Only Atlas-native tasks are deletable; Google work-blocks aren't.
                if task.workBlockGoogleEventId == nil {
                    Button(role: .destructive) { delete(task) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Button { timing = task } label: {
                    Label("Set time", systemImage: "clock")
                }
                .tint(MobileTheme.muted)
            }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            CheckCircle(done: task.done, color: task.spaceColor) { toggle(task) }

            // Tapping the content (not the check-circle) opens the detail sheet.
            HStack(spacing: 12) {
                Text(task.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(task.done ? MobileTheme.faint : MobileTheme.ink)
                    .strikethrough(task.done, color: MobileTheme.faint)

                Spacer(minLength: 8)

                let due = TaskItem.dueLabel(for: task.dueDate)
                if !due.isEmpty {
                    let overdue = task.isOverdue(now: Date())
                    Text(due)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(overdue ? AtlasTheme.Colors.danger : MobileTheme.muted)
                }
            }
            .contentShape(Rectangle())
            // Tap opens detail; a 0.4 s long-press hands the task to drag-to-place on
            // the Schedule tab. Attached after the tap so a quick tap still opens detail;
            // the CheckCircle (its own button) and the row's swipe actions are unaffected.
            .onTapGesture { detail = .task(task) }
            .onLongPressGesture(minimumDuration: 0.4) { startPlacement(task) }
        }
    }

    // MARK: - Data

    private var filterSpace: Space? {
        guard let id = store.spaceFilter else { return nil }
        return store.snapshot.spaces.first { $0.id == id }
    }

    private func inFilter(_ spaceName: String) -> Bool {
        guard let name = filterSpace?.name else { return true }
        return spaceName.caseInsensitiveCompare(name) == .orderedSame
    }

    private var spaceNames: [String] { store.snapshot.spaces.map(\.name) }

    /// The space orphan tasks fall back to: the default space when it's real,
    /// else the first space. Nil only when there are no spaces at all.
    private var fallbackSpaceName: String? {
        guard let first = spaceNames.first else { return nil }
        if !defaultSpaceName.isEmpty,
           let match = spaceNames.first(where: { $0.caseInsensitiveCompare(defaultSpaceName) == .orderedSame }) {
            return match
        }
        return first
    }

    /// Show the space → project hierarchy only when grouping by space AND spaces exist;
    /// with zero spaces we fall back to the flat list.
    private var useHierarchy: Bool { grouping == "project" && !store.snapshot.spaces.isEmpty }

    private var openTasks: [TaskItem] {
        store.snapshot.tasks.compactMap { task in
            guard !task.done || justCompleted.contains(task.id) else { return nil }
            var remapped = task
            // Kill "No Space": a task whose space matches no real one adopts the
            // fallback space, so it never lands in an orphan bucket.
            if let fallback = fallbackSpaceName,
               !spaceNames.contains(where: { $0.caseInsensitiveCompare(task.spaceName) == .orderedSame }) {
                remapped.spaceName = fallback
            }
            guard inFilter(remapped.spaceName) else { return nil }
            return remapped
        }
    }

    private var groups: [(title: String, tasks: [TaskItem])] {
        if grouping == "due" {
            return TaskGrouping.byDueBucket(tasks: openTasks)
        }
        return TaskGrouping
            .bySpace(tasks: openTasks, spaceOrder: spaceNames)
            .map { (title: $0.spaceName, tasks: $0.tasks) }
    }

    /// One space's tasks split into no-project (loose) first, then a subgroup per project.
    struct SpaceGroup {
        let spaceName: String
        let looseTasks: [TaskItem]
        let projectGroups: [(projectName: String, tasks: [TaskItem])]
    }

    /// Hierarchical space → project groups, in snapshot (sort) order. ALL spaces
    /// render — even empty ones — so a fresh account sees its structure. Project rows
    /// come from the snapshot (so projects with zero tasks still appear), unioned with
    /// any project name that only exists on a task (never drop one). openTasks are
    /// already remapped, so every task matches exactly one real space.
    private var spaceGroups: [SpaceGroup] {
        let tasks = openTasks
        return store.snapshot.spaces.filter { inFilter($0.name) }.map { space in
            let inSpace = tasks.filter { $0.spaceName.caseInsensitiveCompare(space.name) == .orderedSame }
            let loose = sortedByDue(inSpace.filter { $0.projectName.isEmpty })
            let named = inSpace.filter { !$0.projectName.isEmpty }
            let snapshotProjectNames = store.snapshot.projects
                .filter { $0.spaceName.caseInsensitiveCompare(space.name) == .orderedSame }
                .map(\.name)
            // De-dupe case-insensitively (a snapshot project and a task's projectName
            // differing only in case must not produce two rows); snapshot casing wins.
            var displayNameByKey: [String: String] = [:]
            for name in snapshotProjectNames { displayNameByKey[name.lowercased()] = name }
            for name in named.map(\.projectName) where displayNameByKey[name.lowercased()] == nil {
                displayNameByKey[name.lowercased()] = name
            }
            let projectGroups = displayNameByKey.values
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { name in (projectName: name, tasks: sortedByDue(named.filter { $0.projectName.caseInsensitiveCompare(name) == .orderedSame })) }
            return SpaceGroup(spaceName: space.name, looseTasks: loose, projectGroups: projectGroups)
        }
    }

    /// Due date ascending (nil last), then title — mirrors TaskGrouping's ordering.
    private func sortedByDue(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (ad?, bd?):
                return ad != bd ? ad < bd : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        updated.completedAt = updated.done ? Date() : nil
        if updated.done {
            justCompleted.insert(task.id)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                _ = withAnimation(MobileTheme.spring) { justCompleted.remove(task.id) }
            }
        }
        Task { await store.setTaskDone(updated) }
    }

    private func delete(_ task: TaskItem) {
        Task { await store.deleteTask(id: task.id) }
    }

    /// Long-press → hand this task to the Schedule tab's drag-to-place flow.
    private func startPlacement(_ task: TaskItem) {
        MobileTheme.Haptic.tap()
        store.pendingPlacement = task
    }
}
