import SwiftUI

/// Full-page detail / edit view for a calendar item — opened by clicking any tile or agenda
/// row. One surface for Atlas events, scheduled-task work-blocks, and read-only external
/// items; the mode is read from the item's own flags (never inferred). A work-block IS a
/// task, so editing one writes through to the task (and its Google mirror), never `events`.
struct CalendarEventDetailView: View {
    @EnvironmentObject var state: AppState
    let item: CalendarEvent

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var descriptionText: String
    @State private var noteID: UUID?
    @State private var editingNote: Note?

    init(item: CalendarEvent) {
        self.item = item
        _title = State(initialValue: item.title)
        _start = State(initialValue: item.start)
        _end = State(initialValue: item.end)
        _descriptionText = State(initialValue: item.notes ?? "")
        _noteID = State(initialValue: item.noteID)
    }

    // MARK: - Mode (from the item's own flags)

    private var isWorkBlock: Bool { item.isWorkBlock || state.tasks.contains { $0.id == item.id } }
    private var isReadOnly: Bool { item.isReadOnly }
    /// Note-linking has a durable home only for Atlas events + work-blocks (external events
    /// are rebuilt every sync and never persisted).
    private var canLinkNote: Bool { !isReadOnly && (isWorkBlock || item.source == .atlas) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if isReadOnly { lockBanner }
                fields
                if canLinkNote { linkedNoteSection }
                footer
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .frame(width: 560, height: 540)
                .background(AtlasTheme.Colors.bgDeep)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                sourceBadge
            }
            if isReadOnly {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            } else {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
        }
    }

    private var sourceBadge: some View {
        let label: String
        let color: Color
        if isReadOnly && item.isRecurring {
            label = "Recurring · \(item.source.displayName)"; color = AtlasTheme.Colors.textMuted
        } else if isWorkBlock {
            label = "Planned work"; color = AtlasTheme.Colors.accent
        } else {
            label = item.source.displayName
            color = item.source == .atlas ? AtlasTheme.Colors.accent : AtlasTheme.Colors.school
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private var lockBanner: some View {
        let msg = item.isRecurring
            ? "Recurring event — edit the series in \(item.source.displayName)."
            : "Read-only — from \(item.source.displayName)."
        return HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 11))
            Text(msg).font(.system(size: 12))
        }
        .foregroundStyle(AtlasTheme.Colors.textMuted)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AtlasTheme.Colors.bgElevated.opacity(0.6)))
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldGroup("STARTS") {
                DatePicker("", selection: $start,
                           displayedComponents: item.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).disabled(isReadOnly)
            }
            if !item.isAllDay {
                fieldGroup("ENDS") {
                    DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().datePickerStyle(.field).disabled(isReadOnly)
                }
            }
            fieldGroup("DESCRIPTION") {
                if isReadOnly {
                    Text(descriptionText.isEmpty ? "—" : descriptionText)
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextEditor(text: $descriptionText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
            }
            if !isReadOnly {
                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.bgDeep)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AtlasTheme.Colors.accent))
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Linked note

    private var linkedNoteSection: some View {
        fieldGroup("LINKED NOTE") {
            HStack(spacing: 8) {
                Menu {
                    Button("None") { noteID = nil }
                    Divider()
                    ForEach(state.notes) { note in
                        Button(note.title) { noteID = note.id }
                    }
                    Divider()
                    Button("New note…") {
                        let n = state.addNote(title: title.isEmpty ? "Untitled note" : title)
                        noteID = n.id
                        editingNote = n
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 11))
                        Text(linkedNoteTitle).font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                .menuStyle(.borderlessButton)
                if noteID != nil {
                    Button { noteID = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
            }
        }
    }

    private var linkedNoteTitle: String {
        if let id = noteID, let n = state.notes.first(where: { $0.id == id }) { return n.title }
        return "Tag a note…"
    }

    // MARK: - Footer actions

    private var footer: some View {
        HStack(spacing: 16) {
            if !isReadOnly {
                Button(action: deleteOrUnschedule) {
                    Label(isWorkBlock ? "Unschedule" : "Delete",
                          systemImage: isWorkBlock ? "tray.and.arrow.down" : "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.danger)
            }
            if let pid = item.projectID, state.project(pid) != nil {
                Button { state.calendarDetailItem = nil; state.route = .project(pid) } label: {
                    Label("Open Project", systemImage: "folder").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accent)
            }
            if let nid = noteID, let n = state.notes.first(where: { $0.id == nid }) {
                Button { openNote(n) } label: {
                    Label("Open Note", systemImage: "arrow.up.right.square").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accent)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(_ label: String,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
        }
    }

    private func close() {
        state.calendarDetailItem = nil
        state.route = .calendar
    }

    private func save() {
        let finalEnd: Date
        if item.isAllDay {
            let dayStart = Calendar.current.startOfDay(for: start)
            finalEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            finalEnd = end > start ? end : start.addingTimeInterval(3600)
        }
        let desc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : descriptionText

        if isWorkBlock {
            let dur = max(1, Int(finalEnd.timeIntervalSince(start) / 60))
            state.updateScheduledTask(id: item.id, title: title, start: start,
                                      durationMin: dur, notes: desc, noteID: noteID)
        } else {
            var updated = item
            updated.title = title
            updated.start = start
            updated.end = finalEnd
            updated.notes = desc
            updated.noteID = noteID
            state.updateEvent(updated)
        }
        close()
    }

    private func deleteOrUnschedule() {
        if isWorkBlock { state.unscheduleTask(id: item.id) }
        else { state.deleteEvent(id: item.id) }
        close()
    }

    private func openNote(_ note: Note) {
        if let pid = note.projectID, state.project(pid) != nil {
            state.calendarDetailItem = nil
            state.route = .project(pid)
        } else {
            editingNote = note   // loose note → open its editor directly
        }
    }
}
