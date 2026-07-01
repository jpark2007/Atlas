import SwiftUI
import AtlasCore

/// Bottom-sheet manual task entry — no AI. Title · Space · Tag · optional due
/// date · optional time. Commits through `store.addTask` with the real space
/// name/color and only real `TaskItem` fields (a timed task sets `scheduledAt`;
/// a due-only task sets `dueDate`, matching `AgendaBuilder`).
struct ManualAddSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var tag = ""
    @State private var spaceID: UUID?
    @State private var hasDue = false
    @State private var dueDay = Date()
    @State private var setTime = false
    @State private var timeOfDay = Date()

    private var spaces: [Space] { store.snapshot.spaces }
    private var selectedSpace: Space? { spaces.first { $0.id == spaceID } ?? spaces.first }
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedSpace != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("New task").edScreenTitle()
                    .padding(.bottom, 24)

                field("Title") {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accent)
                }

                field("Space") { spacePicker }

                field("Tag") {
                    TextField("Optional", text: $tag)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accent)
                }

                dueSection

                Button(action: add) {
                    Text("Add task")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.4)
                .padding(.top, 28)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .onAppear { if spaceID == nil { spaceID = store.spaceFilter ?? spaces.first?.id } }
    }

    // MARK: - Pieces

    /// A caps-labelled row with a hairline underneath — the editorial field style.
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).edCapsLabel()
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    private var spacePicker: some View {
        Menu {
            ForEach(spaces) { space in
                Button { spaceID = space.id } label: {
                    Label(space.name, systemImage: space.id == selectedSpace?.id ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let space = selectedSpace {
                    Circle().fill(space.color).frame(width: 9, height: 9)
                    Text(space.name)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                } else {
                    Text("No spaces")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $hasDue.animation()) {
                Text("Due date").edCapsLabel()
            }
            .tint(MobileTheme.ink)
            .padding(.vertical, 14)
            .edHairlineBelow()

            if hasDue {
                DatePicker("", selection: $dueDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(MobileTheme.accentText)
                    .padding(.vertical, 8)

                Toggle(isOn: $setTime.animation()) {
                    Text("Set a time").edCapsLabel()
                }
                .tint(MobileTheme.ink)
                .padding(.vertical, 14)
                .edHairlineBelow()

                if setTime {
                    DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Commit

    private func add() {
        guard let space = selectedSpace else { return }
        let cal = Calendar.current
        var due: Date?
        var scheduledAt: Date?
        if hasDue {
            let day = cal.startOfDay(for: dueDay)
            due = day
            if setTime {
                let c = cal.dateComponents([.hour, .minute], from: timeOfDay)
                scheduledAt = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: day)
            }
        }
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueLabel: TaskItem.dueLabel(for: due),
            scheduledAt: scheduledAt,
            dueDate: due,
            spaceColor: space.color,
            spaceName: space.name,
            projectName: tag.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task { await store.addTask(task) }
        dismiss()
    }
}
