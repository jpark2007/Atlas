import SwiftUI
import AtlasCore

/// One class, on the phone: the term chip, when and where it meets, who teaches it, the
/// syllabus "Class info" card, then its work and its notes.
///
/// On the Mac these last two are the ordinary project sections of the class page; the
/// phone has no project page, so the hub carries them — same content, one screen.
struct ClassHubView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let classID: UUID

    @State private var presentMeetingEditor = false
    @State private var presentSyllabusScan = false
    @State private var editingNote: Note?
    @State private var detail: ItemDetailSheet.Detail?
    @State private var showArchiveConfirm = false

    /// Read live from the snapshot so an edit made in a sheet is reflected on return.
    private var project: Project? {
        store.snapshot.projects.first { $0.id == classID }
    }

    private var term: Term? {
        project?.termID.flatMap { id in store.terms.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                // The class was archived or deleted from under us — say so rather than
                // rendering an empty shell.
                Text("This class isn't here anymore.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .navigationTitle(project?.name ?? "Class")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Scan a syllabus") { presentSyllabusScan = true }
                    Button(project?.meetingPattern.isEmpty == false ? "Edit meeting times" : "Add meeting times") {
                        presentMeetingEditor = true
                    }
                    Button("Put this class away", role: .destructive) { showArchiveConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
        }
        .sheet(isPresented: $presentMeetingEditor) {
            if let project {
                MeetingPatternSheet(project: project).environmentObject(store)
            }
        }
        .sheet(isPresented: $presentSyllabusScan) {
            if let project {
                SyllabusScanSheet(project: project).environmentObject(store)
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(note: note).environmentObject(store)
        }
        .sheet(item: $detail) { detail in
            ItemDetailSheet(detail: detail).environmentObject(store)
        }
        .confirmationDialog("Put this class away?", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
            Button("Put it away", role: .destructive) {
                store.setClassArchived(projectID: classID, archived: true)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves the class list. Nothing is deleted — its notes and work stay searchable.")
        }
    }

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chips(project)
                meetingBlock(project)
                classInfoBlock(project)
                workBlock(project)
                notesBlock(project)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 72)
        }
        .refreshable { await store.refresh() }
    }

    // MARK: - Chips

    private func chips(_ project: Project) -> some View {
        HStack(spacing: 8) {
            if let term {
                chip(term.name, color: MobileTheme.muted)
            } else {
                // A class with no term is the migration case — say so instead of hiding it.
                chip("No semester", color: MobileTheme.warning)
            }
            if let code = project.code, !code.isEmpty {
                chip(code, color: MobileTheme.faint)
            }
            if project.archivedAt != nil {
                chip("Put away", color: MobileTheme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                .strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Meetings

    private func meetingBlock(_ project: Project) -> some View {
        section("Meets", action: (project.meetingPattern.isEmpty ? "Add times" : "Edit",
                                 { presentMeetingEditor = true })) {
            if project.meetingPattern.isEmpty {
                Text("Atlas doesn't know when this class meets, so it isn't on your calendar yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(project.meetingPattern.enumerated()), id: \.offset) { _, block in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .medium))
                        Text(MeetingPatternFormat.describe(block))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        if let location = block.location, !location.isEmpty {
                            Text("· \(location)")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(MobileTheme.muted)
                }
            }
            if let instructor = project.instructor, !instructor.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person").font(.system(size: 12, weight: .medium))
                    Text(instructor).font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MobileTheme.muted)
            }
            if let note = project.meetingInfo, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Class info card

    @ViewBuilder
    private func classInfoBlock(_ project: Project) -> some View {
        if let info = project.classInfo, !SyllabusDraft.isEmpty(info) {
            section("Class info", action: ("Rescan", { presentSyllabusScan = true })) {
                if !info.gradeWeights.isEmpty { infoGroup("How it's graded", info.gradeWeights) }
                if !info.policies.isEmpty { infoGroup("Policies", info.policies) }
                if let hours = info.officeHours, !hours.isEmpty { infoGroup("Office hours", [hours]) }
            }
        } else {
            section("Class info", action: nil) {
                Text("Scan your syllabus to fill this in — grade weights, late policy, office hours.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { presentSyllabusScan = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder").font(.system(size: 14, weight: .semibold))
                        Text("Scan a syllabus").font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                        .strokeBorder(MobileTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    /// Static syllabus facts, in the syllabus's own words. Explicitly NOT grade tracking:
    /// nothing here is computed, and Atlas never asks what you scored.
    private func infoGroup(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Text("·").font(.system(size: 14))
                    Text(line)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(MobileTheme.muted)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Work

    private func workBlock(_ project: Project) -> some View {
        let items = openWork(project)
        return section("Work", action: nil) {
            if items.isEmpty {
                Text("Nothing due yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            } else {
                ForEach(items) { task in
                    HStack(spacing: 12) {
                        CheckCircle(done: task.done, color: task.spaceColor) { toggle(task) }
                        Text(task.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                        Spacer(minLength: 8)
                        let due = TaskItem.dueLabel(for: task.dueDate)
                        if !due.isEmpty {
                            Text(due)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(task.isOverdue(now: Date())
                                                 ? AtlasTheme.Colors.danger : MobileTheme.muted)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { detail = .task(task) }
                    .padding(.vertical, 10)
                    .edHairlineBelow()
                }
            }
        }
    }

    /// This class's open tasks, soonest deadline first (undated last).
    private func openWork(_ project: Project) -> [TaskItem] {
        store.snapshot.tasks
            .filter { !$0.done && $0.projectName.caseInsensitiveCompare(project.name) == .orderedSame }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x != y ? x < y : a.title < b.title
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.title < b.title
                }
            }
    }

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        updated.completedAt = updated.done ? Date() : nil
        Task { await store.setTaskDone(updated) }
    }

    // MARK: - Notes

    private func notesBlock(_ project: Project) -> some View {
        let notes = store.snapshot.notes
            .filter { $0.projectID == project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        return section("Notes", action: nil) {
            if notes.isEmpty {
                Text("No notes for this class yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            } else {
                ForEach(notes) { note in
                    HStack(spacing: 8) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .lineLimit(1)
                        if note.isExternal {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingNote = note }
                    .padding(.vertical, 12)
                    .edHairlineBelow()
                }
            }
        }
    }

    // MARK: - Section chrome

    /// A caps-labelled band with an optional trailing action — the class page's one shape.
    private func section<C: View>(_ title: String,
                                  action: (String, () -> Void)?,
                                  @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).edCapsLabel()
                Spacer()
                if let action {
                    Button(action: action.1) {
                        Text(action.0)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(.bottom, 30)
    }
}
