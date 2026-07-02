import SwiftUI
import AtlasCore

/// The Tasks tab (spec §4.3): all open tasks under a Project | Due grouping toggle.
/// Reuses the shared `TaskGrouping` (same buckets as the Mac). Honors the shared
/// space filter; check off inline; swipe to set a time or delete.
struct TasksView: View {
    @EnvironmentObject private var store: MobileStore

    @AppStorage("tasksGrouping") private var grouping = "project"   // "project" | "due"
    @State private var timing: TaskItem?

    /// Rows checked off in this session linger ~0.9 s (strikethrough + filled
    /// check) before sliding out, so completion is felt, not a blink.
    @State private var justCompleted: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks").edScreenTitle()
                .padding(.horizontal, 28)
                .padding(.top, 12)

            groupingToggle
                .padding(.horizontal, 28)
                .padding(.top, 16)

            if groups.isEmpty {
                ScrollView {
                    Text("all clear")
                        .edCapsLabel()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
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
    }

    // MARK: - Grouping toggle (two caps labels over a thin rule)

    private var groupingToggle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                segment("Project", value: "project")
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

    // MARK: - List

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.tasks) { task in
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
        .refreshable { await store.refresh() }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            CheckCircle(done: task.done, color: task.spaceColor) { toggle(task) }

            Text(task.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(task.done ? MobileTheme.faint : MobileTheme.ink)
                .strikethrough(task.done, color: MobileTheme.faint)

            Spacer(minLength: 8)

            let due = TaskItem.dueLabel(for: task.dueDate)
            if !due.isEmpty {
                Text(due)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
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

    private var openTasks: [TaskItem] {
        store.snapshot.tasks.filter {
            (!$0.done || justCompleted.contains($0.id)) && inFilter($0.spaceName)
        }
    }

    private var groups: [(title: String, tasks: [TaskItem])] {
        if grouping == "due" {
            return TaskGrouping.byDueBucket(tasks: openTasks)
        }
        return TaskGrouping
            .bySpace(tasks: openTasks, spaceOrder: store.snapshot.spaces.map(\.name))
            .map { (title: $0.spaceName, tasks: $0.tasks) }
    }

    // MARK: - Actions

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        if updated.done {
            justCompleted.insert(task.id)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                _ = withAnimation(MobileTheme.spring) { justCompleted.remove(task.id) }
            }
        }
        Task { await store.updateTask(updated) }
    }

    private func delete(_ task: TaskItem) {
        Task { await store.deleteTask(id: task.id) }
    }
}
