import SwiftUI
import AtlasCore

/// Bottom-sheet manual task entry — no AI. Title · Space · Tag · optional due
/// date · optional time. Commits through `store.addTask` with the real space
/// name/color and only real `TaskItem` fields (a timed task sets `scheduledAt`;
/// a due-only task sets `dueDate`, matching `AgendaBuilder`).
struct ManualAddSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode = "task"        // "task" | "event"
    @State private var title = ""
    @State private var tag = ""
    @State private var spaceID: UUID?
    @State private var hasDue = false
    @State private var dueDay = Date()
    @State private var setTime = false
    @State private var timeOfDay = Date()
    // Event-only
    @State private var eventDay = Date()
    @State private var startTime = Date()
    @State private var durationMin = 60

    private let durations = [15, 30, 45, 60, 90, 120]

    private var spaces: [Space] { store.snapshot.spaces }
    private var selectedSpace: Space? { spaces.first { $0.id == spaceID } ?? spaces.first }
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedSpace != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mode == "task" ? "New task" : "New event").edScreenTitle()
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Cancel").edCapsLabel()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 18)

                modeToggle
                    .padding(.bottom, 16)

                field("Title") {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accent)
                }

                field("Space") { spacePicker }

                if mode == "task" {
                    field("Tag") {
                        TextField("Optional", text: $tag)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .tint(MobileTheme.accent)
                    }

                    dueSection
                } else {
                    startSection
                    field("Duration") { durationPicker }
                }

                Button(action: add) {
                    Text(mode == "task" ? "Add task" : "Add event")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.4)
                .padding(.top, 28)

                if spaces.isEmpty {
                    Text("Create a space on your Mac first — tasks need a home.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .onAppear { if spaceID == nil { spaceID = store.spaceFilter ?? spaces.first?.id } }
    }

    // MARK: - Pieces

    /// Task | Event segment — same caps-label-over-a-rule style as TasksView's toggle.
    private var modeToggle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                segment("Task", value: "task")
                segment("Event", value: "event")
                Spacer()
            }
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
        }
    }

    private func segment(_ title: String, value: String) -> some View {
        Button {
            MobileTheme.Haptic.selection()
            withAnimation(MobileTheme.spring) { mode = value }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.96).textCase(.uppercase)
                .foregroundStyle(mode == value ? MobileTheme.ink : MobileTheme.faint)
        }
        .buttonStyle(.plain)
    }

    /// Event start — day (graphical) + time (wheel); mirrors ItemDetailSheet.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start").edCapsLabel()
            DatePicker("", selection: $eventDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)
            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    private var durationPicker: some View {
        Menu {
            ForEach(durations, id: \.self) { m in
                Button { durationMin = m } label: {
                    if m == durationMin {
                        Label("\(m) min", systemImage: "checkmark")
                    } else {
                        Text("\(m) min")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("\(durationMin) min")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

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
                    if space.id == selectedSpace?.id {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Text(space.name)
                    }
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
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current

        if mode == "event" {
            let day = cal.startOfDay(for: eventDay)
            let c = cal.dateComponents([.hour, .minute], from: startTime)
            let start = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: day) ?? day
            let end = start.addingTimeInterval(Double(durationMin) * 60)
            let event = CalendarEvent(
                title: clean, subtitle: "", start: start, end: end,
                color: space.color, spaceName: space.name, source: .atlas)
            Task { await store.addEvent(event) }
            dismiss()
            return
        }

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
            title: clean,
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
