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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metaRow
                spacePicker
                projectPicker
                notesSection
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { notesDraft = live.notes }
        .sheet(isPresented: $isEditingDueDate) { dueDateEditor }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                state.toggleTask(live.id)
            } label: {
                Image(systemName: live.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(live.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(live.title)
                    .font(.system(size: 24, weight: .bold))
                    .strikethrough(live.done)
                    .foregroundStyle(live.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !live.spaceName.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(live.spaceColor)
                            .frame(width: 7, height: 7)
                        Text(live.spaceName)
                            .font(.system(size: 12, weight: .medium))
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
        HStack(spacing: 12) {
            // Space the task belongs to.
            if !live.spaceName.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(live.spaceColor).frame(width: 7, height: 7)
                    Text(live.spaceName).font(.system(size: 12))
                }
                .foregroundStyle(live.spaceColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                .clipShape(Capsule())
            }
            // Due date — tap to edit (set/change/clear, with a time).
            Button {
                dueDateDraft = live.dueDate ?? Date()
                isEditingDueDate = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 11))
                    Text(live.dueLabel.isEmpty ? "Set due date" : "Due \(dueChipLabel)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            if let at = live.scheduledAt {
                metaChip(icon: "clock", label: "Scheduled \(shortDate(at))")
            }
            if live.done {
                metaChip(icon: "checkmark.circle", label: "Completed")
            }
        }
    }

    /// Popover-style date+time editor for the task's due date.
    private var dueDateEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Due date")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            DatePicker("", selection: Binding(
                get: { dueDateDraft ?? Date() },
                set: { dueDateDraft = $0 }
            ), displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
            .labelsHidden()
            HStack {
                Button("Clear") {
                    state.setDueDate(taskId: task.id, date: nil)
                    isEditingDueDate = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button("Cancel") { isEditingDueDate = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Button("Save") {
                    state.setDueDate(taskId: task.id, date: dueDateDraft)
                    isEditingDueDate = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(AtlasTheme.Colors.accent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(AtlasTheme.Colors.bgCard)
    }

    private func metaChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 12))
        }
        .foregroundStyle(AtlasTheme.Colors.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(Capsule())
    }

    // MARK: Space picker

    private var spacePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPACE")
                .font(AtlasTheme.Font.sectionLabel())
                .tracking(0.8)
                .foregroundStyle(AtlasTheme.Colors.textMuted)

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
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(live.spaceName.isEmpty
                                 ? AtlasTheme.Colors.textMuted
                                 : live.spaceColor)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            Text("PROJECT")
                .font(AtlasTheme.Font.sectionLabel())
                .tracking(0.8)
                .foregroundStyle(AtlasTheme.Colors.textMuted)

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
                        .font(.system(size: 11))
                    Text(live.projectName.isEmpty ? "None" : live.projectName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(live.projectName.isEmpty
                                 ? AtlasTheme.Colors.textMuted
                                 : AtlasTheme.Colors.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DESCRIPTION")
                    .font(AtlasTheme.Font.sectionLabel())
                    .tracking(0.8)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                if !isEditingNotes {
                    Button {
                        notesDraft = live.notes
                        isEditingNotes = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
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
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Text(live.notes)
                    .font(.system(size: 13))
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
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notesDraft)
                    .font(.system(size: 13))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 120)
            }
            .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    notesDraft = live.notes
                    isEditingNotes = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    state.updateTaskNotes(taskId: live.id, notes: notesDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingNotes = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.accent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}
