import SwiftUI
import AtlasCore

/// Step one of drag-to-place scheduling (Wave-3 Task 6 §3). A medium-detent list
/// of the open, unscheduled tasks — space-filter respected, dated tasks first —
/// so the user can pick one to drop onto the hour grid. Picking calls `onPick`
/// (which flips Schedule into grid mode with a floating chip) and dismisses.
struct PlaceTaskSheet: View {
    let onPick: (TaskItem) -> Void
    /// Slot context: when the sheet is opened by a long-press on an empty grid slot,
    /// this is the pressed time (minutes-from-midnight). Shown in the header and used
    /// by the caller to spawn the chip / prefill ManualAddSheet at that time.
    var slotMinute: Int? = nil
    /// Quick actions — create an event / task right here (caller decides prefill).
    var onNewEvent: () -> Void = {}
    var onNewTask: () -> Void = {}

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Place a task").edScreenTitle()
                    if let m = slotMinute {
                        Text(slotCaps(m))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.88).textCase(.uppercase)
                            .foregroundStyle(MobileTheme.ink)
                    } else {
                        Text("Pick one to drop on the grid").edCapsLabel().textCase(nil)
                    }
                }
                Spacer()
                Button { dismiss() } label: { Text("Cancel").edCapsLabel() }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)

            // Create-here actions — pinned above the task groups.
            VStack(spacing: 10) {
                quickAction("New event", systemImage: "calendar", action: onNewEvent)
                quickAction("New task", systemImage: "checklist", action: onNewTask)
            }
            .padding(.horizontal, 28).padding(.bottom, 16)

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

    /// Editorial outlined row — icon + label + a trailing plus, matching the sheet.
    private func quickAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MobileTheme.muted)
            }
            .padding(.vertical, 13).padding(.horizontal, 18)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "AT 3:15 PM" — the pressed slot time for the header.
    private func slotCaps(_ minute: Int) -> String {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let date = cal.date(bySettingHour: (minute / 60) % 24, minute: minute % 60, second: 0, of: base) ?? base
        let f = DateFormatter()
        f.dateFormat = minute % 60 == 0 ? "h a" : "h:mm a"
        return "AT " + f.string(from: date)
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
