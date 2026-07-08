import SwiftUI
import AtlasCore

struct TaskDetailView: View {
    @EnvironmentObject var state: AppState
    let task: TaskItem

    /// Live copy of the task so edits are reactive.
    private var live: TaskItem {
        state.tasks.first { $0.id == task.id } ?? task
    }

    @State private var notesDraft: String = ""
    @State private var isEditingNotes = false
    @State private var isEditingDueDate = false
    @State private var dueDateDraft: Date? = nil
    @State private var dueHover = false
    @State private var showRefPicker = false
    @State private var referenceSelection: Set<UUID> = []
    /// Note currently open in the corner-card editor (nil = closed). Same overlay
    /// host mechanism as `ProjectDetailView` — clicking the linked note opens it here.
    @State private var editingNote: Note?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metaRow
                spacePicker
                projectPicker
                notesSection
                linkedNoteSection
                referencesSection
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { notesDraft = live.notes }
        .sheet(isPresented: $isEditingDueDate) { dueDateEditor }
        .sheet(isPresented: $showRefPicker, onDismiss: syncTaskAttachments) {
            AttachReferencePicker(projectID: taskProjectID, selection: $referenceSelection)
        }
        // Corner-card note editor (not a modal sheet): the task stays visible behind
        // it. Mirrors `ProjectDetailView`'s overlay host so a linked note edits in place.
        .overlay(alignment: .bottomTrailing) {
            if let note = editingNote {
                NoteCardOverlay(note: note) { editingNote = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: editingNote?.id)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                state.toggleTask(live.id)
            } label: {
                Image(systemName: live.done ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 24)
                    .foregroundStyle(live.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(live.title)
                    .atlasFont(size: 29, weight: .bold, design: .rounded)
                    .tracking(-0.4)
                    .strikethrough(live.done)
                    .foregroundStyle(live.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !live.spaceName.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(live.spaceColor)
                            .frame(width: 7, height: 7)
                        Text(live.spaceName)
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(live.spaceColor)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: Meta

    /// "Today" / "Today · 5:00 PM" — appends the due time when the due date carries one.
    private var dueChipLabel: String {
        guard let due = live.dueDate else { return live.dueLabel }
        let cal = Calendar.current
        let h = cal.component(.hour, from: due), m = cal.component(.minute, from: due)
        guard h != 0 || m != 0 else { return live.dueLabel }
        let tf = DateFormatter(); tf.dateFormat = m == 0 ? "h a" : "h:mm a"
        return "\(live.dueLabel) · \(tf.string(from: due))"
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            // Space the task belongs to.
            if !live.spaceName.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(live.spaceColor).frame(width: 7, height: 7)
                    Text(live.spaceName).atlasFont(size: 13, weight: .medium, design: .rounded)
                }
                .foregroundStyle(live.spaceColor)
            }
            // Due date — tap to edit (set/change/clear, with a time).
            Button {
                dueDateDraft = live.dueDate ?? Date()
                isEditingDueDate = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").atlasFont(size: 12)
                    Text(live.dueLabel.isEmpty ? "Set due date" : "Due \(dueChipLabel)")
                        .atlasMono(size: 12, weight: .medium)
                }
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                        .fill(Color.black.opacity(dueHover ? 0.05 : 0))
                )
            }
            .buttonStyle(.plain)
            .onHover { dueHover = $0 }
            if let at = live.scheduledAt {
                metaChip(icon: "clock", label: "Scheduled \(shortDate(at))")
            }
            if live.done {
                atlasTag(text: "Completed", color: AtlasTheme.Colors.accent)
            }
            assigneeChip
            Spacer()
        }
    }

    /// Claim/assigned state for shared-project tasks — an unclaimed task shows a
    /// "Claim task" affordance; once claimed, an "Assigned" indicator.
    @ViewBuilder
    private var assigneeChip: some View {
        if live.isClaimable {
            Button {
                Task { await state.claimTask(live.id) }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .strokeBorder(AtlasTheme.Colors.textMuted.opacity(0.5), lineWidth: 1)
                        .frame(width: 12, height: 12)
                    Text("Claim task")
                }
                .atlasFont(size: 13, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
        } else if live.assigneeID != nil {
            atlasTag(text: "Assigned", color: AtlasTheme.Colors.accent)
            // A future task can resolve assigneeID -> ProfileRow.displayName once a
            // member-profile cache exists; showing "Assigned" (not a raw UUID) is
            // the correct minimal behavior for now.
        }
    }

    /// Popover-style date+time editor for the task's due date.
    private var dueDateEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Due date")
                .atlasFont(size: 18, weight: .bold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            DatePicker("", selection: Binding(
                get: { dueDateDraft ?? Date() },
                set: { dueDateDraft = $0 }
            ), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(AtlasTheme.Colors.accentText)
            HStack {
                Button("Clear") {
                    state.setDueDate(taskId: task.id, date: nil)
                    isEditingDueDate = false
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.danger)
                Spacer()
                Button("Cancel") { isEditingDueDate = false }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Button("Save") {
                    state.setDueDate(taskId: task.id, date: dueDateDraft)
                    isEditingDueDate = false
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(AtlasTheme.Colors.bgBase)
    }

    private func metaChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .atlasFont(size: 12)
            Text(label)
                .atlasMono(size: 12)
        }
        .foregroundStyle(AtlasTheme.Colors.textSecondary)
    }

    // MARK: Space picker

    private var spacePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPACE").atlasCapsLabel()

            Menu {
                ForEach(state.spaces) { space in
                    Button(space.name) {
                        state.setTaskSpace(taskId: live.id, spaceName: space.name)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(live.spaceColor)
                        .frame(width: 8, height: 8)
                    Text(live.spaceName.isEmpty ? "None" : live.spaceName)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                    Image(systemName: "chevron.down")
                        .atlasFont(size: 10, weight: .semibold)
                }
                .foregroundStyle(live.spaceName.isEmpty
                                 ? AtlasTheme.Colors.textMuted
                                 : live.spaceColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Project picker

    private var projectPicker: some View {
        let spaceProjects = state.spaces
            .first { $0.name == live.spaceName }?.projects ?? []

        return VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT").atlasCapsLabel()

            Menu {
                Button("None") {
                    state.setTaskProject(taskId: live.id, projectName: "")
                }
                if !spaceProjects.isEmpty {
                    Divider()
                    ForEach(spaceProjects) { project in
                        Button(project.name) {
                            state.setTaskProject(taskId: live.id, projectName: project.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .atlasFont(size: 12)
                    Text(live.projectName.isEmpty ? "None" : live.projectName)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                    Image(systemName: "chevron.down")
                        .atlasFont(size: 10, weight: .semibold)
                }
                .foregroundStyle(live.projectName.isEmpty
                                 ? AtlasTheme.Colors.textMuted
                                 : AtlasTheme.Colors.accentText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DESCRIPTION").atlasCapsLabel()
                Spacer()
                if !isEditingNotes {
                    Button {
                        notesDraft = live.notes
                        isEditingNotes = true
                    } label: {
                        Image(systemName: "pencil")
                            .atlasFont(size: 12)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditingNotes {
                notesEditor
            } else if live.notes.isEmpty {
                Button {
                    notesDraft = ""
                    isEditingNotes = true
                } label: {
                    Text("Add a description…")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Text(live.notes)
                    .atlasFont(size: 14, design: .rounded)
                    .lineSpacing(4)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if notesDraft.isEmpty {
                    Text("Add description, context, links…")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.leading, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notesDraft)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .tint(AtlasTheme.Colors.accent)
                    .frame(minHeight: 120)
            }
            .padding(.vertical, 4)
            .atlasHairlineBelow()

            HStack {
                Spacer()
                Button("Cancel") {
                    notesDraft = live.notes
                    isEditingNotes = false
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    state.updateTaskNotes(taskId: live.id, notes: notesDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingNotes = false
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }

    // MARK: Linked note

    /// The note this task is tagged to, if the tag still resolves. Global-notes
    /// scope — mirrors the calendar event detail, not the project-scoped references
    /// below (`noteID` and `ReferenceAttachment` are two independent systems).
    private var linkedNote: Note? {
        guard let id = live.noteID else { return nil }
        return state.notes.first { $0.id == id }
    }

    private var linkedNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINKED NOTE").atlasCapsLabel()
            HStack(spacing: 8) {
                if let note = linkedNote {
                    // Primary click: open the note in the in-app corner-card editor.
                    Button { editingNote = note } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").atlasFont(size: 12)
                            Text(note.title.isEmpty ? "Untitled note" : note.title)
                                .atlasFont(size: 13, weight: .medium, design: .rounded)
                        }
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    }
                    .buttonStyle(.plain)
                    // Secondary: re-tag to a different note.
                    notePickerMenu {
                        Image(systemName: "chevron.down").atlasFont(size: 10)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    // Unlink.
                    Button { setNoteID(nil) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                } else {
                    notePickerMenu {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").atlasFont(size: 12)
                            Text("Tag a note…").atlasFont(size: 13, weight: .medium, design: .rounded)
                            Image(systemName: "chevron.down").atlasFont(size: 10)
                        }
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    }
                }
                Spacer()
            }
        }
    }

    /// The note-picking menu — None / every note / New note… — mirroring
    /// `CalendarEventDetailView.linkedNoteSection`. `New note…` creates a global
    /// note, links it, and opens it in the corner-card editor.
    @ViewBuilder
    private func notePickerMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            Button("None") { setNoteID(nil) }
            Divider()
            ForEach(state.notes) { note in
                Button(note.title.isEmpty ? "Untitled note" : note.title) { setNoteID(note.id) }
            }
            Divider()
            Button("New note…") {
                let n = state.addNote(title: live.title.isEmpty ? "Untitled note" : live.title)
                setNoteID(n.id)
                editingNote = n
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Link (or clear) the task's tagged note and persist it.
    private func setNoteID(_ id: UUID?) {
        state.setTaskNote(taskId: live.id, noteID: id)
    }

    // MARK: References

    /// The task's project UUID — resolved from its space + project names, since
    /// `TaskItem` links to a project by name. References are project-scoped.
    private var taskProjectID: UUID? {
        state.spaces.first { $0.name == live.spaceName }?
            .projects.first { $0.name == live.projectName }?.id
    }

    private var referencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REFERENCES").atlasCapsLabel()
                Spacer()
                Button {
                    referenceSelection = Set(state.references(forTask: live.id).map(\.id))
                    showRefPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .atlasFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            let refs = state.references(forTask: live.id)
            if refs.isEmpty {
                Text("No references attached.")
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                ForEach(refs) { ref in
                    ReferenceListRow(reference: ref) {
                        state.detachReference(ref.id, fromTask: live.id)
                    }
                }
            }
        }
    }

    /// Applies the picker's selection to the task's attachments (diff → attach/detach).
    private func syncTaskAttachments() {
        let current = Set(state.references(forTask: live.id).map(\.id))
        for added in referenceSelection.subtracting(current) {
            state.attachReference(added, toTask: live.id)
        }
        for removed in current.subtracting(referenceSelection) {
            state.detachReference(removed, fromTask: live.id)
        }
    }
}
