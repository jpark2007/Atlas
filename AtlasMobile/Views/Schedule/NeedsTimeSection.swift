import SwiftUI
import AtlasCore

/// The "Needs a time" block: tasks due on the shown day with no time yet (date-only
/// due — clock-timed deadlines render on the timeline/grid instead). Row tap opens
/// detail; the "set time" chip sets a time; the header's "PLACE" button starts the
/// drag-to-place flow. Renders as a `List` section (list mode) or a compact strip
/// pinned above the hour grid (`compact`).
struct NeedsTimeSection: View {
    let tasks: [TaskItem]
    let onSetTime: (TaskItem) -> Void
    let onOpen: (TaskItem) -> Void
    let onPlace: () -> Void
    /// Long-press (0.4 s) a row → start drag-to-place for that task.
    let onLongPress: (TaskItem) -> Void
    var compact: Bool = false

    var body: some View {
        if !tasks.isEmpty {
            if compact { compactBody } else { listSection }
        }
    }

    private var listSection: some View {
        Section {
            ForEach(tasks) { task in
                row(task)
                    .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(MobileTheme.hairline)
            }
        } header: {
            header.padding(.horizontal, 28).padding(.top, 8)
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 4)
            ForEach(tasks.prefix(3)) { task in
                row(task)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .edHairlineBelow()
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(MobileTheme.hairline).frame(height: 1) }
    }

    private var header: some View {
        HStack {
            Text("Needs a time · \(tasks.count)")
                .edCapsLabel()
                .textCase(nil)
            Spacer()
            Button { onPlace() } label: {
                Text("Place")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(task.spaceColor).frame(width: 9, height: 9)
            Text(task.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            Spacer()
            // The "set time" chip is its own tap target; the rest of the row opens detail.
            Button { onSetTime(task) } label: {
                HStack(spacing: 6) {
                    Text("set time")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(0.84).textCase(.uppercase)
                        .foregroundStyle(MobileTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        // Tap opens detail; a 0.4 s long-press starts placement (haptic in-gesture).
        .onTapGesture { onOpen(task) }
        .onLongPressGesture(minimumDuration: 0.4) {
            MobileTheme.Haptic.tap()
            onLongPress(task)
        }
    }
}
