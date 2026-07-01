import SwiftUI
import AtlasCore

/// Give a due-but-untimed task a time. Sets `scheduledAt` (the field AgendaBuilder
/// reads to place a task on the timeline) to the task's due day at the chosen
/// clock time — no invented fields — and hands the updated task back to persist.
struct SetTimeSheet: View {
    let task: TaskItem
    let day: Date
    let onSet: (TaskItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set a time").edScreenTitle()
                Text(task.title).edCapsLabel()
            }

            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Button(action: commit) {
                Text("Add to the day")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func commit() {
        let cal = Calendar.current
        let base = task.dueDate ?? day
        let c = cal.dateComponents([.hour, .minute], from: time)
        let scheduledAt = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0,
                                   of: cal.startOfDay(for: base))
        var updated = task
        updated.scheduledAt = scheduledAt
        onSet(updated)
        dismiss()
    }
}
