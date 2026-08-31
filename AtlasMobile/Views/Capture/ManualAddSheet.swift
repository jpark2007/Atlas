import SwiftUI
import AtlasCore

/// Bottom-sheet manual task entry — no AI. Title · Space · Tag · optional due
/// date · optional time. Commits through `store.addTask` with the real space
/// name/color and only real `TaskItem` fields (a timed task sets `scheduledAt`;
/// a due-only task sets `dueDate`, matching `AgendaBuilder`).
struct ManualAddSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

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
    @State private var isAllDay = false
    /// The day the event ends on — same as the start day unless it runs over, which is how
    /// a conference or a trip is entered.
    @State private var endDay = Date()
    @State private var durationMin = 60

    /// All-day has its own toggle in this sheet, so the ladder's 24-hour rung is dropped —
    /// one control per decision. (`EventDuration` keeps it for `ItemDetailSheet`, which
    /// must still be able to show an existing exactly-24-hour event.)
    private var durations: [Int] { EventDuration.options(including: durationMin).filter { $0 != 1440 } }

    /// Optional slot-press prefill (Wave-3 §w5): a preselected kind, the shown
    /// schedule day, and a pressed slot time. `nil` ⇒ a blank sheet, so the plain
    /// `ManualAddSheet()` call site keeps compiling unchanged.
    struct Prefill: Identifiable {
        let id = UUID()
        var kind: String = "task"     // "task" | "event"
        var day: Date?
        var minute: Int?              // minutes-from-midnight for the start / due time
    }

    init(prefill: Prefill? = nil) {
        guard let p = prefill else { return }        // all fields keep their @State defaults
        _mode = State(initialValue: p.kind)
        if let day = p.day {
            _dueDay = State(initialValue: day)
            _eventDay = State(initialValue: day)
            _endDay = State(initialValue: day)
            _hasDue = State(initialValue: true)      // a shown day means the task is due that day
        }
        if let minute = p.minute {
            let cal = Calendar.current
            let time = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                of: cal.startOfDay(for: Date())) ?? Date()
            _startTime = State(initialValue: time)   // event start
            _timeOfDay = State(initialValue: time)   // task due time
            _setTime = State(initialValue: true)
        }
    }

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
                    allDayToggle
                    startSection
                    field("Ends") { endDayPicker }
                    if !isAllDay {
                        field("Duration") { durationPicker }
                    }
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
        .onChange(of: eventDay) { oldDay, newDay in
            // Moving the start carries the span along; the end can never precede the start.
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: oldDay),
                                          to: cal.startOfDay(for: newDay)).day ?? 0
            if days != 0 { endDay = cal.date(byAdding: .day, value: days, to: endDay) ?? endDay }
            if endDay < cal.startOfDay(for: newDay) { endDay = newDay }
        }
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

    /// All-day switch — the same toggle row the task form's "Due date" uses.
    private var allDayToggle: some View {
        Toggle(isOn: $isAllDay.animation()) {
            Text("All day").edCapsLabel()
        }
        .tint(MobileTheme.ink)
        .padding(.vertical, 14)
        .edHairlineBelow()
    }

    /// Event start — day (graphical) + time (wheel); mirrors ItemDetailSheet. An all-day
    /// event carries no clock time, so it picks a day only. At regular width the two sit
    /// side by side: the iPad card is wide but short, and stacking them is what pushed
    /// Duration and the Add button below the fold.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start").edCapsLabel()
            if hSize == .regular && !isAllDay {
                HStack(alignment: .top, spacing: 20) {
                    dayPicker
                    timePicker.frame(width: 200)
                }
            } else {
                dayPicker
                if !isAllDay { timePicker.frame(maxWidth: .infinity) }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    private var dayPicker: some View {
        DatePicker("", selection: $eventDay, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .tint(MobileTheme.accentText)
    }

    private var timePicker: some View {
        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
    }

    /// The day the event ends — a compact date pill, so an event can run past its start day.
    private var endDayPicker: some View {
        DatePicker("", selection: $endDay,
                   in: Calendar.current.startOfDay(for: eventDay)...,
                   displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(MobileTheme.accentText)
    }

    private var durationPicker: some View {
        Menu {
            ForEach(durations, id: \.self) { m in
                Button { durationMin = m } label: {
                    if m == durationMin {
                        Label(EventDuration.label(m), systemImage: "checkmark")
                    } else {
                        Text(EventDuration.label(m))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(EventDuration.label(durationMin))
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
            let start: Date
            let end: Date
            if isAllDay {
                // An all-day event is a floating date, not an instant: both ends are UTC
                // midnight of the picked calendar day (`AllDayDate`), and the stored end is
                // EXCLUSIVE while the picker reads inclusively — so a Mon–Wed trip stores
                // Thursday.
                start = AllDayDate.anchor(forDayOf: eventDay, in: cal)
                let lastDay = AllDayDate.anchor(forDayOf: max(endDay, eventDay), in: cal)
                end = AllDayDate.utc.date(byAdding: .day, value: 1, to: lastDay) ?? start
            } else {
                let day = cal.startOfDay(for: eventDay)
                let c = cal.dateComponents([.hour, .minute], from: startTime)
                start = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: day) ?? day
                // Duration sets the clock time it ends at; the end day carries it onto a later
                // date, so a multi-day event is simply end > start on another day.
                end = EventDuration.end(start: start, minutes: durationMin,
                                        endDay: endDay, calendar: cal)
            }
            let event = CalendarEvent(
                title: clean, subtitle: "", start: start, end: end,
                color: space.color, spaceName: space.name,
                isAllDay: isAllDay, source: .atlas)
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
            projectID: store.projectID(spaceName: space.name,
                                       projectName: tag.trimmingCharacters(in: .whitespacesAndNewlines)),
            projectName: tag.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task { await store.addTask(task) }
        dismiss()
    }
}
