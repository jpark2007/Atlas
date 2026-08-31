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
    /// The last day the event covers, read INCLUSIVELY — an all-day Mon–Wed event shows
    /// Wednesday here even though it is stored with an exclusive Thursday end.
    @State private var endDay: Date
    @State private var durationMin: Int

    @State private var showDeleteConfirm = false

    /// Includes the event's own length even when it's off the ladder, so a synced
    /// 3h event stays selectable instead of being truncated by the first tap.
    private var durations: [Int] { EventDuration.options(including: durationMin) }

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
            _endDay = State(initialValue: Date())
            _durationMin = State(initialValue: 60)
        case .event(let e):
            _title = State(initialValue: e.title)
            _spaceName = State(initialValue: e.spaceName)
            _notes = State(initialValue: e.notes ?? "")
            // The day picker shows the date the event *reads* as. For an all-day event that
            // is its bucket date, not its UTC-midnight anchor (which reads as the day before).
            _startDay = State(initialValue: e.bucketDate(in: .current))
            _startTime = State(initialValue: e.start)
            // A timed event splits into a clock length + the day its end lands on; an all-day
            // one is stored with an EXCLUSIVE end, so the last day it covers is the day before.
            let split = EventDuration.split(start: e.start, end: e.end, calendar: .current)
            _endDay = State(initialValue: e.isAllDay
                            ? AllDayDate.localDay(of: AllDayDate.utc.date(byAdding: .day, value: -1, to: e.end) ?? e.end,
                                                  calendar: .current)
                            : split.endDay)
            _durationMin = State(initialValue: split.minutes)
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
        .onChange(of: startDay) { oldStart, newStart in
            // Moving an event carries its span along, and the end can never precede the start.
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: oldStart),
                                          to: cal.startOfDay(for: newStart)).day ?? 0
            if days != 0 { endDay = cal.date(byAdding: .day, value: days, to: endDay) ?? endDay }
            if endDay < cal.startOfDay(for: newStart) { endDay = newStart }
        }
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
        } else if isCanvasTask {
            // Canvas owns title + due (re-sync overwrites only those); scheduling,
            // notes, space and project stay user-editable. Same copy the Mac uses.
            Text("From Canvas — synced automatically. Schedule it; title and dates update from your feed.")
                .edCapsLabel()
                .padding(.bottom, 8)
        }

        if isCanvasTask {
            labeledRow("Title", title)
        } else {
            field("Title") { titleField }
        }
        field("Space") { spacePicker }

        if isTask {
            field("Project") { projectPicker }
            if isCanvasTask {
                labeledRow("Due date", canvasDueDisplay)
            } else {
                dueSection
            }
        } else {
            startSection
            field("Ends") { endDayPicker }
            if isAllDayEvent {
                labeledRow("Duration", "All-day")
            } else {
                field("Duration") { durationPicker }
            }
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

    /// Event start — day (graphical) + time (wheel). An all-day event has no
    /// clock time, so it picks a day only.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start").edCapsLabel()
            DatePicker("", selection: $startDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)
            if !isAllDayEvent {
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    /// The last day the event covers — a compact date pill, so a conference or a trip can
    /// run past its start day. Inclusive: picking Wednesday means the event ends Wednesday.
    private var endDayPicker: some View {
        DatePicker("", selection: $endDay,
                   in: Calendar.current.startOfDay(for: startDay)...,
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
        if e.source == .canvas {
            // Canvas events are fully read-only (like Apple). Verbatim Mac copy.
            Text("From Canvas — synced automatically. Schedule it; title and dates update from your feed.")
                .edCapsLabel()
                .padding(.bottom, 8)
        } else {
            Text("From \(e.source.displayName) — shown, not editable")
                .edCapsLabel()
                .padding(.bottom, 8)
        }
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

    private var isAllDayEvent: Bool {
        if case .event(let e) = detail, e.isAllDay { return true }
        return false
    }

    private var isGoogleEvent: Bool {
        if case .event(let e) = detail, e.source == .google { return true }
        return false
    }

    /// A Canvas-synced task (assignment): title + due are server-owned and lock,
    /// everything else stays editable (mirrors Mac `TaskDetailView.isCanvasTask`).
    private var isCanvasTask: Bool {
        if case .task(let t) = detail { return t.canvasUID != nil }
        return false
    }

    /// Locked-due text for a Canvas task — date label plus clock time when the due
    /// carries one (mirrors Mac `TaskDetailView.dueChipLabel`).
    private var canvasDueDisplay: String {
        guard case .task(let t) = detail, let due = t.dueDate else { return "No due date" }
        let cal = Calendar.current
        let h = cal.component(.hour, from: due), m = cal.component(.minute, from: due)
        guard h != 0 || m != 0 else { return t.dueLabel }
        let f = DateFormatter(); f.dateFormat = m == 0 ? "h a" : "h:mm a"
        return "\(t.dueLabel) · \(f.string(from: due))"
    }

    /// Atlas and Google events edit the same way — server-side sync PATCHes Atlas
    /// edits back to Google and tombstones propagate deletes. Apple and Canvas
    /// events stay read-only.
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

    /// External read-only events render the labeled read-only fields. Apple and
    /// Canvas are both fully read-only (Canvas is server-owned via its ICS feed).
    private var readOnlyEvent: CalendarEvent? {
        if case .event(let e) = detail, e.source == .apple || e.source == .canvas { return e }
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
            updated.projectID = store.projectID(spaceName: updated.spaceName,
                                                projectName: updated.projectName)
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
            if e.isAllDay {
                // All-day events carry no clock time — stamping one would turn them into a
                // timed block. Both ends are re-anchored to UTC midnight of the picked day
                // (`AllDayDate`), and the picked end day is INCLUSIVE, so the stored end —
                // which is exclusive — is the day after it.
                let start = AllDayDate.anchor(forDayOf: startDay, in: cal)
                let lastDay = AllDayDate.anchor(forDayOf: max(endDay, startDay), in: cal)
                updated.start = start
                updated.end = AllDayDate.utc.date(byAdding: .day, value: 1, to: lastDay) ?? start
            } else {
                let day = cal.startOfDay(for: startDay)
                let c = cal.dateComponents([.hour, .minute], from: startTime)
                let start = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? e.start
                updated.start = start
                // Duration sets the clock time it ends at; the end day carries it onto a
                // later date, so a multi-day event is simply end > start on another day.
                updated.end = EventDuration.end(start: start, minutes: durationMin,
                                                endDay: endDay, calendar: cal)
            }
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
