import SwiftUI
import AtlasCore

/// The "Needs a time" block pinned above the timeline: tasks due on the shown day
/// with no time yet. Tapping a row opens `SetTimeSheet`. Rendered as a `List`
/// section so it sits in the same scroll as the timeline.
struct NeedsTimeSection: View {
    let tasks: [TaskItem]
    let onSetTime: (TaskItem) -> Void

    var body: some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    Button { onSetTime(task) } label: { row(task) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                }
            } header: {
                Text("Needs a time · \(tasks.count)")
                    .edCapsLabel()
                    .textCase(nil)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(task.spaceColor).frame(width: 9, height: 9)
            Text(task.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            Spacer()
            Text("set time")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(0.84).textCase(.uppercase)
                .foregroundStyle(MobileTheme.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MobileTheme.faint)
        }
    }
}
