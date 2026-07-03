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
    @State private var time: Date
    @State private var pickedDay: Date

    init(task: TaskItem, day: Date, onSet: @escaping (TaskItem) -> Void) {
        self.task = task
        self.day = day
        self.onSet = onSet
        _time = State(initialValue: task.scheduledAt ?? Date())          // seed from an existing time
        _pickedDay = State(initialValue: task.scheduledAt ?? day)        // default to the shown day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set a time").edScreenTitle()
                    Text(task.title).edCapsLabel()
                }
                Spacer()
                Button { dismiss() } label: { Text("Cancel").edCapsLabel() }
                    .buttonStyle(.plain)
            }

            DatePicker("", selection: $pickedDay, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(MobileTheme.accentText)

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

            Button(action: clearTime) {
                Text("Clear time")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .frame(maxWidth: .infinity)
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

    /// Set `scheduledAt` to the picked day at the chosen clock time.
    private func commit() {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: time)
        var updated = task
        updated.scheduledAt = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0,
                                       of: cal.startOfDay(for: pickedDay))
        onSet(updated)
        dismiss()
    }

    /// Clear the scheduled time — returns the task to "needs a time" (keeps its due date).
    private func clearTime() {
        var updated = task
        updated.scheduledAt = nil
        onSet(updated)
        dismiss()
    }
}
