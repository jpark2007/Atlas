import SwiftUI
import AtlasCore

/// The shared result sheet for voice + typed capture. Everything here is ALREADY
/// committed (Phase 4 §3) — the sheet exists so a wrong guess is one tap from
/// right: Class ▾ · Type ▾ · Due ▾, thumb-sized, plus per-item Undo and
/// "Undo everything". Editorial: a titled block on the bg, rows separated by
/// hairlines — no card chrome.
struct CaptureResultCard: View {
    @EnvironmentObject private var store: MobileStore

    @Binding var items: [CommittedItem]
    /// The user's spaces WITH their projects nested (`MobileStore.contextSpaces`),
    /// so the Class menu can list real classes.
    let spaces: [Space]
    let onDone: () -> Void
    let onUndoAll: () -> Void

    @State private var editingDateID: UUID?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Added to Atlas").edScreenTitle()
                Text(items.count == 1 ? "1 item · tap a chip to fix it"
                                      : "\(items.count) items · tap a chip to fix one")
                    .edCapsLabel()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)

            List {
                ForEach($items) { $item in
                    let index = items.firstIndex { $0.id == item.id } ?? 0
                    row($item)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(MobileTheme.heroSpring.delay(Double(index) * 0.07),
                                   value: appeared)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { undo(item) } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 16) {
                if items.contains(where: \.wasNote) {
                    Text("A note is saved as a task you can tick off").edCapsLabel()
                }
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)

                Button(action: onUndoAll) {
                    Text("Undo everything")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appeared = true }
        .sheet(isPresented: datePickerPresented) {
            if let id = editingDateID, let i = items.firstIndex(where: { $0.id == id }) {
                CaptureDateSheet(
                    kind: items[i].kind,
                    date: items[i].date,
                    onApply: { setDate(items[i], $0) },
                    onClose: { editingDateID = nil })
            }
        }
    }

    // MARK: - Row

    private func row(_ item: Binding<CommittedItem>) -> some View {
        let value = item.wrappedValue
        return HStack(alignment: .top, spacing: 12) {
            // Space-color edge (spec §4): routing is visible at a glance.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color(for: value.spaceName))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(value.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)

                HStack(spacing: 8) {
                    classChip(value)
                    typeChip(value)
                    dueChip(value)
                }
            }
        }
    }

    // MARK: - Chips (34 pt tall, generous padding — thumb targets, not text links)

    private func classChip(_ item: CommittedItem) -> some View {
        Menu {
            if !classes.isEmpty {
                Section("Classes") {
                    ForEach(classes) { project in
                        Button(classLabel(project)) {
                            setSpace(item, spaceName: project.spaceName, projectName: project.name)
                        }
                    }
                }
            }
            Section("Spaces") {
                ForEach(spaces) { space in
                    Button(space.name) { setSpace(item, spaceName: space.name, projectName: "") }
                }
            }
        } label: {
            chip(item.projectName.isEmpty
                 ? (item.spaceName.isEmpty ? "Unfiled" : item.spaceName)
                 : item.projectName,
                 unsure: item.lowConfidence)
        }
    }

    private func typeChip(_ item: CommittedItem) -> some View {
        Menu {
            ForEach(CaptureItemType.allCases) { type in
                Button(type.label) { setType(item, type) }
            }
        } label: {
            chip(CaptureItemType.of(item).label, unsure: item.lowConfidence)
        }
        // Converting an item capture only ATTACHED to would delete something the
        // user already had, so the chip reads but doesn't change there.
        .disabled(item.isUpdate)
    }

    private func dueChip(_ item: CommittedItem) -> some View {
        Menu {
            Button("Today") { setDate(item, Self.startOfToday) }
            Button("Tomorrow") { setDate(item, Self.offsetDays(1)) }
            Button("Next week") { setDate(item, Self.offsetDays(7)) }
            Button("Pick a date…") { editingDateID = item.id }
            if item.kind == .task {
                Divider()
                Button("No date") { setDate(item, nil) }
            }
        } label: {
            chip(dateLabel(item), unsure: item.lowConfidence)
        }
    }

    /// The chip itself. A parse the model wasn't sure about gets a quiet dashed
    /// outline — a marker, never a dialog (Phase 4 §3).
    private func chip(_ text: String, unsure: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MobileTheme.faint)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(unsure ? MobileTheme.accent.opacity(0.6) : MobileTheme.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: unsure ? [3, 2] : []))
        )
        .contentShape(Rectangle())
    }

    // MARK: - Corrections (mutate the COMMITTED object, then the card)

    private func setSpace(_ item: CommittedItem, spaceName: String, projectName: String) {
        MobileTheme.Haptic.selection()
        switch item.kind {
        case .task:
            guard var task = store.snapshot.tasks.first(where: { $0.id == item.id }) else { return }
            task.spaceName = spaceName
            task.spaceID = spaces.first { $0.name == spaceName }?.id
            task.spaceColor = color(for: spaceName)
            task.projectName = projectName
            Task { await store.updateTask(task) }
        case .event:
            guard var event = store.snapshot.events.first(where: { $0.id == item.id }) else { return }
            event.spaceName = spaceName
            event.spaceID = spaces.first { $0.name == spaceName }?.id
            event.color = color(for: spaceName)
            Task { await store.updateEvent(event) }
        }
        patch(item) { $0.spaceName = spaceName; $0.projectName = projectName }
    }

    /// A task's due date moves directly; an event keeps its time of day and moves
    /// to that calendar day, because a stated time is sacred.
    private func setDate(_ item: CommittedItem, _ date: Date?) {
        MobileTheme.Haptic.selection()
        switch item.kind {
        case .task:
            guard var task = store.snapshot.tasks.first(where: { $0.id == item.id }) else { return }
            task.dueDate = date
            task.dueLabel = TaskItem.dueLabel(for: date)
            Task { await store.updateTask(task) }
            patch(item) { $0.date = date }
        case .event:
            guard let date,
                  var event = store.snapshot.events.first(where: { $0.id == item.id }) else { return }
            let cal = Calendar.current
            let length = event.end.timeIntervalSince(event.start)
            let time = cal.dateComponents([.hour, .minute], from: event.start)
            let moved = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                 second: 0, of: cal.startOfDay(for: date)) ?? date
            event.start = moved
            event.end = moved.addingTimeInterval(length)
            Task { await store.updateEvent(event) }
            patch(item) { $0.date = moved }
        }
        editingDateID = nil
    }

    /// There is no in-place conversion in the data model, so a type change deletes
    /// the committed object and creates the new one from the same fields.
    private func setType(_ item: CommittedItem, _ type: CaptureItemType) {
        guard !item.isUpdate, CaptureItemType.of(item) != type else { return }
        MobileTheme.Haptic.selection()
        let notes = carriedNotes(item)
        let space = spaces.first { $0.name.caseInsensitiveCompare(item.spaceName) == .orderedSame }
        let spaceName = space?.name ?? item.spaceName

        switch item.kind {
        case .task:  Task { await store.deleteTask(id: item.id) }
        case .event: Task { await store.deleteEvent(id: item.id) }
        }

        switch type {
        case .task, .deadline:
            let due = type == .deadline ? (item.date ?? Self.startOfToday) : nil
            let task = TaskItem(title: item.title,
                                dueLabel: TaskItem.dueLabel(for: due),
                                dueDate: due,
                                spaceColor: color(for: spaceName),
                                spaceName: spaceName,
                                projectName: item.projectName,
                                notes: notes)
            Task { await store.addTask(task) }
            replace(item, with: CommittedItem(id: task.id, kind: .task, title: task.title,
                                              spaceName: spaceName, projectName: item.projectName,
                                              date: due, lowConfidence: false, prior: nil))
        case .event:
            let start = item.date ?? Date()
            var event = CalendarEvent(title: item.title, subtitle: "",
                                      start: start, end: start.addingTimeInterval(3600),
                                      color: color(for: spaceName), spaceName: spaceName,
                                      notes: notes.isEmpty ? nil : notes,
                                      source: .atlas)
            event.spaceID = space?.id
            Task { await store.addEvent(event) }
            replace(item, with: CommittedItem(id: event.id, kind: .event, title: event.title,
                                              spaceName: spaceName, projectName: item.projectName,
                                              date: start, lowConfidence: false, prior: nil))
        }
    }

    /// Per-item Undo: something capture CREATED is deleted; a task it merely
    /// attached to is rolled back to what it was.
    private func undo(_ item: CommittedItem) {
        MobileTheme.Haptic.selection()
        if let prior = item.prior, item.kind == .task {
            if var task = store.snapshot.tasks.first(where: { $0.id == item.id }) {
                task.dueDate = prior.due
                task.dueLabel = TaskItem.dueLabel(for: prior.due)
                task.notes = prior.notes
                Task { await store.updateTask(task) }
            }
        } else {
            switch item.kind {
            case .task:  Task { await store.deleteTask(id: item.id) }
            case .event: Task { await store.deleteEvent(id: item.id) }
            }
        }
        items.removeAll { $0.id == item.id }
        if items.isEmpty { onUndoAll() }
    }

    // MARK: - Helpers

    private func carriedNotes(_ item: CommittedItem) -> String {
        switch item.kind {
        case .task:  return store.snapshot.tasks.first { $0.id == item.id }?.notes ?? ""
        case .event: return store.snapshot.events.first { $0.id == item.id }?.notes ?? ""
        }
    }

    private func patch(_ item: CommittedItem, _ change: (inout CommittedItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        change(&items[i])
        // A correction is the user's own choice — no longer an unsure guess.
        items[i].lowConfidence = false
    }

    private func replace(_ item: CommittedItem, with new: CommittedItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = new
    }

    private var classes: [Project] {
        spaces.flatMap(\.projects).filter(\.isClass)
    }

    private func classLabel(_ project: Project) -> String {
        guard let code = project.code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return project.name }
        return "\(code) · \(project.name)"
    }

    private func dateLabel(_ item: CommittedItem) -> String {
        guard let date = item.date else { return "No date" }
        return item.kind == .event
            ? CaptureResultCard.dayTime.string(from: date)
            : CaptureResultCard.day.string(from: date)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let dayTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"; return f
    }()

    private static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private static func offsetDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startOfToday) ?? startOfToday
    }

    private var datePickerPresented: Binding<Bool> {
        Binding(get: { editingDateID != nil },
                set: { if !$0 { editingDateID = nil } })
    }

    private func color(for spaceName: String) -> Color {
        spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }?.color
            ?? MobileTheme.accent
    }
}

/// The "Pick a date…" escape hatch behind the Due chip. Local state so Cancel
/// discards — Done is the only path that writes back.
private struct CaptureDateSheet: View {
    let kind: CommittedItem.Kind
    let date: Date?
    let onApply: (Date) -> Void
    let onClose: () -> Void

    @State private var day: Date
    @State private var setTime: Bool
    @State private var timeOfDay: Date

    private var isEvent: Bool { kind == .event }

    init(kind: CommittedItem.Kind, date: Date?,
         onApply: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        self.kind = kind
        self.date = date
        self.onApply = onApply
        self.onClose = onClose
        let base = date ?? Date()
        _day = State(initialValue: base)
        _timeOfDay = State(initialValue: base)
        // Events always carry a time; tasks only when their date has a clock time.
        let c = Calendar.current.dateComponents([.hour, .minute], from: base)
        _setTime = State(initialValue: kind == .event || c.hour != 0 || c.minute != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEvent ? "Event time" : "Due date").edScreenTitle()

            DatePicker("", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)

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
            }

            Button(action: apply) {
                Text("Done")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            Button { onClose() } label: {
                Text("Cancel").edCapsLabel()
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func apply() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: day)
        if setTime {
            let c = cal.dateComponents([.hour, .minute], from: timeOfDay)
            onApply(cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                             second: 0, of: base) ?? base)
        } else {
            onApply(base)
        }
    }
}
