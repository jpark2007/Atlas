import SwiftUI
import AtlasCore

/// The single tap-to-edit sheet for a task or an event. Atlas-native items (any
/// task, or an `.atlas` event) are editable; external events (`.google`/`.apple`)
/// render read-only with their true source label. Editorial field style — a caps
/// label over a control, hairline below — mirrors `ManualAddSheet`.
struct ItemDetailSheet: View {

    /// What this sheet is showing. Identifiable so it drives `.sheet(item:)`.
    enum Detail: Identifiable {
        case task(TaskItem)
        case event(CalendarEvent)

        var id: UUID {
            switch self {
            case .task(let t):  return t.id
            case .event(let e): return e.id
            }
        }
    }

    let detail: Detail

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    // Shared editable fields
    @State private var title: String
    @State private var spaceName: String
    @State private var notes: String
    // Task-only
    @State private var projectName: String
    @State private var hasDue: Bool
    @State private var dueDay: Date
    @State private var setTime: Bool
    @State private var timeOfDay: Date
    // Event-only
    @State private var startDay: Date
    @State private var startTime: Date
    @State private var durationMin: Int

    @State private var showDeleteConfirm = false

    private let durations = [15, 30, 45, 60, 90, 120]

    init(detail: Detail) {
        self.detail = detail
        switch detail {
        case .task(let t):
            _title = State(initialValue: t.title)
            _spaceName = State(initialValue: t.spaceName)
            _notes = State(initialValue: t.notes)
            _projectName = State(initialValue: t.projectName)
            let due = t.dueDate
            let base = due ?? Date()
            _hasDue = State(initialValue: due != nil)
            _dueDay = State(initialValue: base)
            let c = Calendar.current.dateComponents([.hour, .minute], from: base)
            _setTime = State(initialValue: due != nil && (c.hour != 0 || c.minute != 0))
            _timeOfDay = State(initialValue: base)
            // Event fields unused for a task.
            _startDay = State(initialValue: Date())
            _startTime = State(initialValue: Date())
            _durationMin = State(initialValue: 60)
        case .event(let e):
            _title = State(initialValue: e.title)
            _spaceName = State(initialValue: e.spaceName)
            _notes = State(initialValue: e.notes ?? "")
            _startDay = State(initialValue: e.start)
            _startTime = State(initialValue: e.start)
            _durationMin = State(initialValue: max(15, Int(e.end.timeIntervalSince(e.start) / 60)))
            // Task fields unused for an event.
            _projectName = State(initialValue: "")
            _hasDue = State(initialValue: false)
            _dueDay = State(initialValue: Date())
            _setTime = State(initialValue: false)
            _timeOfDay = State(initialValue: Date())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(isTask ? "Task" : "Event")
                    .edScreenTitle()
                    .padding(.bottom, 24)

                if isEditable {
                    editableFields
                } else if let e = readOnlyEvent {
                    readOnlyFields(e)
                }

                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .confirmationDialog("Delete this \(isTask ? "task" : "event")?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
        }
    }

    // MARK: - Editable

    @ViewBuilder
    private var editableFields: some View {
        if isGoogleEvent {
            Text("Syncs with Google Calendar")
                .edCapsLabel()
                .padding(.bottom, 8)
        }

        field("Title") { titleField }
        field("Space") { spacePicker }

        if isTask {
            field("Project") { projectPicker }
            dueSection
        } else {
            startSection
            field("Duration") { durationPicker }
        }

        field("Notes") { notesEditor }
    }

    private var titleField: some View {
        TextField("", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
    }

    private var spacePicker: some View {
        Menu {
            ForEach(spaces) { space in
                Button {
                    spaceName = space.name
                    // If the picked project no longer belongs to the new space, drop it.
                    if !projectBelongsToSelectedSpace { projectName = "" }
                } label: {
                    if space.name.caseInsensitiveCompare(spaceName) == .orderedSame {
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
                    Text(spaceName.isEmpty ? "No space" : spaceName)
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

    /// Task due — day + optional time (ManualAddSheet's `dueSection` pattern).
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

    /// Event start — day (graphical) + time (wheel); events always carry a time.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start").edCapsLabel()
            DatePicker("", selection: $startDay, displayedComponents: .date)
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

    /// Project — a Menu of the selected space's projects plus "None". Mirrors the
    /// space picker; keeps the current value as the label even if it's off-list so
    /// we never silently drop a task's existing project.
    private var projectPicker: some View {
        Menu {
            Button { projectName = "" } label: {
                if projectName.isEmpty {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }
            ForEach(spaceProjects) { project in
                Button { projectName = project.name } label: {
                    if project.name.caseInsensitiveCompare(projectName) == .orderedSame {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(projectName.isEmpty ? "None" : projectName)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(projectName.isEmpty ? MobileTheme.faint : MobileTheme.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    private var notesEditor: some View {
        TextEditor(text: $notes)
            .scrollContentBackground(.hidden)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .frame(height: 100)
    }

    // MARK: - Read-only (external events)

    @ViewBuilder
    private func readOnlyFields(_ e: CalendarEvent) -> some View {
        Text("From \(e.source.displayName) — read-only")
            .edCapsLabel()
            .padding(.bottom, 8)
        labeledRow("Title", e.title)
        labeledRow("Space", e.spaceName)
        labeledRow("When", e.isAllDay ? "All-day" : startText(e.start))
        labeledRow("Duration", e.durationLabel)
        if let n = e.notes, !n.isEmpty {
            labeledRow("Notes", n)
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        field(label) {
            Text(value)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
            if isEditable {
                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
            }

            if canDelete {
                Button { showDeleteConfirm = true } label: {
                    Text("Delete")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            Button { dismiss() } label: {
                Text("Cancel")
                    .edCapsLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Field helper (editorial: caps label over a control, hairline below)

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).edCapsLabel()
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    // MARK: - Derived

    private var isTask: Bool { if case .task = detail { return true }; return false }

    private var isGoogleEvent: Bool {
        if case .event(let e) = detail, e.source == .google { return true }
        return false
    }

    /// Atlas and Google events edit the same way — server-side sync PATCHes Atlas
    /// edits back to Google and tombstones propagate deletes. Only Apple stays read-only.
    private var isEditable: Bool {
        switch detail {
        case .task:          return true
        case .event(let e):  return e.source == .atlas || e.source == .google
        }
    }

    private var canDelete: Bool {
        switch detail {
        case .task:          return true
        case .event(let e):  return e.source == .atlas || e.source == .google
        }
    }

    private var readOnlyEvent: CalendarEvent? {
        if case .event(let e) = detail, e.source == .apple { return e }
        return nil
    }

    private var spaces: [Space] { store.snapshot.spaces }
    private var selectedSpace: Space? {
        spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }
    }

    /// Projects belonging to the currently-selected space (case-insensitive), the
    /// same match `MobileStore.contextSpaces` uses to re-nest projects.
    private var spaceProjects: [Project] {
        store.snapshot.projects.filter {
            $0.spaceName.caseInsensitiveCompare(spaceName) == .orderedSame
        }
    }

    /// True when the picked project is empty or lives in the selected space.
    private var projectBelongsToSelectedSpace: Bool {
        projectName.isEmpty || spaceProjects.contains {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }
    }

    private func startText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }

    // MARK: - Commit

    private func save() {
        let cal = Calendar.current
        switch detail {
        case .task(let t):
            var updated = t
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let space = selectedSpace {
                updated.spaceName = space.name
                updated.spaceColor = space.color
            }
            updated.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.notes = notes
            if hasDue {
                let day = cal.startOfDay(for: dueDay)
                if setTime {
                    let c = cal.dateComponents([.hour, .minute], from: timeOfDay)
                    updated.dueDate = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day)
                } else {
                    updated.dueDate = day
                }
            } else {
                updated.dueDate = nil
            }
            updated.dueLabel = TaskItem.dueLabel(for: updated.dueDate)
            Task { await store.updateTask(updated) }

        case .event(let e):
            var updated = e
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let space = selectedSpace {
                updated.spaceName = space.name
                updated.color = space.color
            }
            updated.notes = notes.isEmpty ? nil : notes
            let day = cal.startOfDay(for: startDay)
            let c = cal.dateComponents([.hour, .minute], from: startTime)
            let start = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? e.start
            updated.start = start
            updated.end = start.addingTimeInterval(Double(durationMin) * 60)
            Task { await store.updateEvent(updated) }
        }
        MobileTheme.Haptic.success()
        dismiss()
    }

    private func performDelete() {
        switch detail {
        case .task(let t):  Task { await store.deleteTask(id: t.id) }
        case .event(let e): Task { await store.deleteEvent(id: e.id) }
        }
        dismiss()
    }
}
