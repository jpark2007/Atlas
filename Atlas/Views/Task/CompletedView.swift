import SwiftUI
import AtlasCore

/// Everything you've finished, grouped by project with the freshest work first.
/// Reached from ⌘K ("Completed tasks") — deliberately not a sidebar item.
/// Un-checking a row here reopens the task and it returns to its pending lists.
struct CompletedView: View {
    @EnvironmentObject var state: AppState

    /// One project's worth of finished tasks. `latest` orders the groups.
    private struct Group: Identifiable {
        let title: String
        let tasks: [TaskItem]
        let latest: Date
        var id: String { title }
    }

    private var groups: [Group] {
        let done = state.tasks.filter { $0.done }
        let byProject = Dictionary(grouping: done) { task in
            task.projectName.isEmpty ? (task.spaceName.isEmpty ? "Unfiled" : task.spaceName)
                                     : task.projectName
        }
        return byProject.map { title, tasks in
            let sorted = tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return Group(title: title,
                         tasks: sorted,
                         latest: sorted.first?.completedAt ?? .distantPast)
        }
        .sorted { $0.latest > $1.latest }
    }

    var body: some View {
        // Grouping is O(n log n) over all done tasks — run it once per render.
        let groups = self.groups
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(total: groups.reduce(0) { $0 + $1.tasks.count })
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in groupSection(group) }
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    private func header(total: Int) -> some View {
        HStack(spacing: 12) {
            Text("Completed")
                .atlasTitleSerif(size: 26)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Text("\(total) tasks")
                .atlasMono(size: 12)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    private func groupSection(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title.uppercased()).atlasCapsLabel()
            VStack(spacing: 0) {
                ForEach(Array(group.tasks.enumerated()), id: \.element.id) { i, task in
                    row(task)
                    if i < group.tasks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        Button { state.route = .task(task.id) } label: {
            HStack(spacing: 12) {
                Button {
                    state.toggleTask(task.id)   // reopen — row returns to pending lists
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .atlasFont(size: 17)
                        .foregroundStyle(AtlasTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Mark not done")

                Text(task.title)
                    .atlasFont(size: 14, design: .rounded)
                    .strikethrough(true)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                if let at = task.completedAt {
                    Text(LifecycleDate.short(at))
                        .atlasMono(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Image(systemName: "chevron.right")
                    .atlasFont(size: 10, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.square")
                .atlasFont(size: 31, weight: .light)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text("Nothing completed yet.")
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
