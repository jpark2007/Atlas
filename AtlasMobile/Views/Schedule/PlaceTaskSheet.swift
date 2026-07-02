import SwiftUI
import AtlasCore

/// Step one of drag-to-place scheduling (Wave-3 Task 6 §3). A medium-detent list
/// of the open, unscheduled tasks — space-filter respected, dated tasks first —
/// so the user can pick one to drop onto the hour grid. Picking calls `onPick`
/// (which flips Schedule into grid mode with a floating chip) and dismisses.
struct PlaceTaskSheet: View {
    let onPick: (TaskItem) -> Void

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Place a task").edScreenTitle()
                    Text("Pick one to drop on the grid").edCapsLabel().textCase(nil)
                }
                Spacer()
                Button { dismiss() } label: { Text("Cancel").edCapsLabel() }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)

            if placeable.isEmpty {
                Text("Nothing to place")
                    .edCapsLabel()
                    .padding(.horizontal, 28).padding(.top, 28)
                Spacer()
            } else {
                List {
                    ForEach(placeable) { task in
                        Button { onPick(task); dismiss() } label: { row(task) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(MobileTheme.hairline)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(task.spaceColor).frame(width: 9, height: 9)
            Text(task.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            Spacer()
            // Recompute so a clock-timed deadline always shows its time (e.g. "Fri 5 PM").
            let label = TaskItem.dueLabel(for: task.dueDate)
            if !label.isEmpty {
                Text(label).edCapsLabel().textCase(nil).fixedSize()
            }
        }
        .contentShape(Rectangle())
    }

    /// Open, unscheduled, space-filtered tasks in three groups — needs-a-time
    /// (date-only due), then deadlines (clock-timed due), then no-date — each group
    /// sorted by due date then title. Scheduling work time for a deadline is the point.
    private var placeable: [TaskItem] {
        store.snapshot.tasks
            .filter { !$0.done && $0.scheduledAt == nil && inFilter($0.spaceName) }
            .sorted { a, b in
                let ga = group(a), gb = group(b)
                if ga != gb { return ga < gb }
                if let ad = a.dueDate, let bd = b.dueDate, ad != bd { return ad < bd }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    /// 0 = needs-a-time (date-only due), 1 = deadline (clock-timed due), 2 = no-date.
    private func group(_ t: TaskItem) -> Int {
        guard let due = t.dueDate else { return 2 }
        let c = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0 ? 1 : 0
    }

    private func inFilter(_ spaceName: String) -> Bool {
        guard let id = store.spaceFilter,
              let space = store.snapshot.spaces.first(where: { $0.id == id }) else { return true }
        return spaceName.caseInsensitiveCompare(space.name) == .orderedSame
    }
}
