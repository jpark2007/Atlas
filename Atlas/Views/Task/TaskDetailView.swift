import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject var state: AppState
    let task: TaskItem

    /// Live copy of the task so edits are reactive.
    private var live: TaskItem {
        state.tasks.first { $0.id == task.id } ?? task
    }

    @State private var notesDraft: String = ""
    @State private var isEditingNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metaRow
                projectPicker
                notesSection
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { notesDraft = live.notes }
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
        HStack(spacing: 20) {
            if !live.dueLabel.isEmpty {
                metaChip(icon: "calendar", label: "Due \(dueChipLabel)")
            }
            if let at = live.scheduledAt {
                metaChip(icon: "clock", label: "Scheduled \(shortDate(at))")
            }
            if live.done {
                metaChip(icon: "checkmark.circle", label: "Completed")
            }
        }
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
                Text("NOTES")
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
                    Text("Add notes…")
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
                    Text("Write notes, links, context…")
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
