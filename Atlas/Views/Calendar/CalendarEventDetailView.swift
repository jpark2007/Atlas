import SwiftUI
import AtlasCore

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
    @State private var showRefPicker = false
    @State private var referenceSelection: Set<UUID> = []

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
    /// References attach to `events(id)`, so only a persisted Atlas event qualifies —
    /// external items are rebuilt each sync (unstable ids) and a work-block's id lives
    /// in `tasks`, not `events` (manage those on the task's detail page).
    private var canAttachReferences: Bool { !isReadOnly && !isWorkBlock && item.source == .atlas }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if isReadOnly { lockBanner }
                fields
                if canLinkNote { linkedNoteSection }
                if canAttachReferences { referencesSection }
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
        .sheet(isPresented: $showRefPicker, onDismiss: syncEventAttachments) {
            AttachReferencePicker(projectID: item.projectID, selection: $referenceSelection)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").atlasFont(size: 12, weight: .semibold)
                        Text("Back").atlasFont(size: 13, weight: .medium, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                sourceBadge
            }
            if isReadOnly {
                Text(title)
                    .atlasFont(size: 29, weight: .bold, design: .rounded)
                    .tracking(-0.4)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            } else {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 29, weight: .bold, design: .rounded)
                    .tracking(-0.4)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
            }
        }
    }

    private var sourceBadge: some View {
        let label: String
        let color: Color
        if isReadOnly && item.isRecurring {
            label = "Recurring · \(item.source.displayName)"; color = AtlasTheme.Colors.textMuted
        } else if isWorkBlock {
            label = "Planned work"; color = AtlasTheme.Colors.accentText
        } else {
            label = item.source.displayName
            color = item.source == .atlas ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.school
        }
        return atlasTag(text: label, color: color)
    }

    private var lockBanner: some View {
        let msg = item.isRecurring
            ? "Recurring event — edit the series in \(item.source.displayName)."
            : "Read-only — from \(item.source.displayName)."
        return HStack(spacing: 8) {
            Image(systemName: "lock.fill").atlasFont(size: 12)
            Text(msg).atlasFont(size: 13, design: .rounded)
        }
        .foregroundStyle(AtlasTheme.Colors.textMuted)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasHairlineBelow()
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldGroup("STARTS") {
                DatePicker("", selection: $start,
                           displayedComponents: item.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).disabled(isReadOnly)
                    .tint(AtlasTheme.Colors.accentText)
            }
            if !item.isAllDay {
                fieldGroup("ENDS") {
                    DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().datePickerStyle(.field).disabled(isReadOnly)
                        .tint(AtlasTheme.Colors.accentText)
                }
            }
            fieldGroup("DESCRIPTION") {
                if isReadOnly {
                    Text(descriptionText.isEmpty ? "—" : descriptionText)
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextEditor(text: $descriptionText)
                        .atlasFont(size: 14, design: .rounded)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .tint(AtlasTheme.Colors.accent)
                }
            }
            if !isReadOnly {
                Button(action: save) {
                    Text("Save")
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                        )
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 16)
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
                        Image(systemName: "doc.text").atlasFont(size: 12)
                        Text(linkedNoteTitle).atlasFont(size: 13, weight: .medium, design: .rounded)
                        Image(systemName: "chevron.down").atlasFont(size: 10)
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

    // MARK: - References

    private var referencesSection: some View {
        fieldGroup("REFERENCES") {
            VStack(alignment: .leading, spacing: 0) {
                let refs = state.references(forEvent: item.id)
                if refs.isEmpty {
                    Text("No references attached.")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                } else {
                    ForEach(refs) { ref in
                        ReferenceListRow(reference: ref) {
                            state.detachReference(ref.id, fromEvent: item.id)
                        }
                    }
                }
                Button {
                    referenceSelection = Set(state.references(forEvent: item.id).map(\.id))
                    showRefPicker = true
                } label: {
                    Label("Add reference", systemImage: "plus")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .padding(.top, refs.isEmpty ? 0 : 10)
            }
        }
    }

    /// Applies the picker's selection to the event's attachments (diff → attach/detach).
    private func syncEventAttachments() {
        let current = Set(state.references(forEvent: item.id).map(\.id))
        for added in referenceSelection.subtracting(current) {
            state.attachReference(added, toEvent: item.id)
        }
        for removed in current.subtracting(referenceSelection) {
            state.detachReference(removed, fromEvent: item.id)
        }
    }

    // MARK: - Footer actions

    private var footer: some View {
        HStack(spacing: 16) {
            if !isReadOnly {
                Button(action: deleteOrUnschedule) {
                    Label(isWorkBlock ? "Unschedule" : "Delete",
                          systemImage: isWorkBlock ? "tray.and.arrow.down" : "trash")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.danger)
            }
            if let pid = item.projectID, state.project(pid) != nil {
                Button { state.calendarDetailItem = nil; state.route = .project(pid) } label: {
                    Label("Open Project", systemImage: "folder").atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            if let nid = noteID, let n = state.notes.first(where: { $0.id == nid }) {
                Button { openNote(n) } label: {
                    Label("Open Note", systemImage: "arrow.up.right.square").atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(_ label: String,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).atlasCapsLabel()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasHairlineBelow()
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
