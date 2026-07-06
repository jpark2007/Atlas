import SwiftUI
import AppKit
import AtlasCore

struct ProjectDetailView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var googleAuth: GoogleAuthService
    @Environment(\.openURL) private var openURL
    let project: Project

    @State private var isEditingOverview = false
    @State private var draftOverview = ""

    /// Add-link sheet toggle, and the last import/Quick-Look problem to surface calmly.
    @State private var presentAddLink = false
    @State private var referenceError: String?
    /// Non-nil while the in-app Drive picker sheet is up (carries the tokens the
    /// bundled page needs); dismissing it re-pulls the reference pool.
    @State private var drivePicker: DrivePickerSession?

    /// Editable starter sample-tasks for an empty project. Seeded once from
    /// `ProjectTemplate`; purely local (never persisted) — the user can edit or
    /// delete them so a new project shows useful scaffolding instead of blank.
    @State private var starterTasks: [String] = []
    @State private var didSeedStarter = false

    /// Note currently open in the editor sheet (nil = closed). A brand-new note is
    /// an unsaved draft pre-linked to this project.
    @State private var editingNote: Note?

    /// Live tasks tagged to this project.
    private var liveTasks: [TaskItem] {
        state.tasks
            .filter { $0.projectName == project.name && $0.spaceName == project.spaceName }
            .sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return $0.title < $1.title
                }
            }
    }

    /// Live events tagged to this project.
    private var liveEvents: [CalendarEvent] {
        state.events
            .filter { $0.spaceName == project.spaceName && ($0.projectID == project.id || $0.subtitle == project.name) }
            .sorted { $0.start < $1.start }
    }

    private var isEmptyProject: Bool {
        project.overview.isEmpty && liveTasks.isEmpty
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                // Main column
                VStack(alignment: .leading, spacing: 22) {
                    badges
                    titleBlock
                    overview
                    if !liveTasks.isEmpty  { liveTasksSection }
                    if !liveEvents.isEmpty { liveEventsSection }
                    if isEmptyProject { starterTemplate }
                    notesSection
                    referencesSection
                    if !project.pinned.isEmpty { pinned }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Linked references column
                if !project.backlinks.isEmpty {
                    linkedReferences.frame(width: 280)
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { seedStarterIfNeeded() }
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .frame(width: 560, height: 540)
                .background(AtlasTheme.Colors.bgDeep)
        }
        .sheet(isPresented: $presentAddLink) {
            AddLinkSheet(projectID: project.id)
        }
        // In-app Drive picker: on dismiss (import done or cancelled) re-pull the
        // pool so imported references show up immediately.
        .sheet(item: $drivePicker, onDismiss: { Task { await state.reloadReferences() } }) { session in
            DrivePickerSheet(projectID: project.id, session: session)
        }
    }

    // MARK: - Notes (WS-10 native foundation)

    /// Per-project notes. New notes are pre-linked to this project; once Google is
    /// connected they map to Google Docs inside this project's Drive folder
    /// (see docs/superpowers/specs — folder-per-project). The live sync is layered
    /// on later; this is the native structure it plugs into.
    private var notesSection: some View {
        let projectNotes = state.notes(in: project.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel("NOTES")
                Spacer()
                Button(action: newNote) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text("New").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .help("New note in this project")
            }

            if projectNotes.isEmpty {
                Text("No notes yet. Notes you add here live in this project — and, once Google is connected, sync to a Drive folder for \(project.name) as Google Docs.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projectNotes.enumerated()), id: \.element.id) { i, note in
                        Button { editingNote = note } label: { noteRow(note) }
                            .buttonStyle(.plain)
                        if i < projectNotes.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.hairline)
                        }
                    }
                }
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        let linked = note.googleDocId != nil
        return HStack(spacing: 12) {
            Image(systemName: linked ? "doc.text.fill" : "note.text")
                .font(.system(size: 14))
                .foregroundStyle(linked ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if linked {
                Text("Doc ↗").font(.system(size: 10, design: .rounded)).foregroundStyle(AtlasTheme.Colors.accentText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func newNote() {
        // Unsaved draft pre-linked to this project; NoteEditorView.commit() persists
        // it (updateNote inserts on no-match), so dismissing without Done leaves
        // nothing behind.
        var draft = Note(title: "", body: "", spaceName: project.spaceName, projectID: project.id)
        draft.spaceID = state.spaceID(named: project.spaceName)
        editingNote = draft
    }

    // MARK: - References (Docs → Notes import)

    /// The project's reference pool — Docs imported as editable notes, view-only
    /// Drive files, and external links (see docs/specs/2026-07-03-notes-import-design.md).
    /// "Import" opens the in-app Drive picker sheet (`DrivePickerSheet`); imported
    /// references surface when the sheet dismisses.
    private var referencesSection: some View {
        let refs = state.references(in: project.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                sectionLabel("REFERENCES")
                if !refs.isEmpty {
                    Text("\(refs.count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                referenceHeaderButton(icon: "arrow.down.doc", title: "Import") { importFromDrive() }
                    .help("Import Google Docs and files from Drive")
                referenceHeaderButton(icon: "link", title: "Add link") { presentAddLink = true }
                    .help("Attach an external link")
            }

            if let referenceError {
                Text(referenceError)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.danger)
            }

            if refs.isEmpty {
                Text("No references yet. Import Google Docs, PDFs, and files from Drive, or add a link — they live in this project and can attach to its tasks and events.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(refs.enumerated()), id: \.element.id) { i, ref in
                        ReferenceRowView(
                            reference: ref,
                            externalActionTitle: externalActionTitle(ref),
                            onTap: { openReference(ref) },
                            onOpenExternal: { openExternal(ref) },
                            onQuickLook: ref.kind == .file ? { quickLook(ref) } : nil,
                            onRemove: { state.removeReference(ref.id) }
                        )
                        if i < refs.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.hairline)
                        }
                    }
                }
            }
        }
    }

    private func referenceHeaderButton(icon: String, title: String,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AtlasTheme.Colors.accentText)
        }
        .buttonStyle(.plain)
    }

    /// Primary tap: link → open URL; file → Quick Look; doc-note → open its backing
    /// note if one exists locally, else open the Doc in Google.
    private func openReference(_ ref: Reference) {
        switch ref.kind {
        case .link:
            openExternal(ref)
        case .file:
            quickLook(ref)
        case .docNote:
            if let nid = ref.noteID, let note = state.notes.first(where: { $0.id == nid }) {
                editingNote = note
            } else {
                openExternal(ref)
            }
        }
    }

    /// The out-of-Atlas (browser) destination for a reference.
    private func externalURL(_ ref: Reference) -> URL? {
        switch ref.kind {
        case .link:
            return ref.url.flatMap { URL(string: $0) }
        case .docNote:
            return ref.driveFileId.flatMap { URL(string: "https://docs.google.com/document/d/\($0)/edit") }
        case .file:
            return ref.driveFileId.flatMap { URL(string: "https://drive.google.com/file/d/\($0)/view") }
        }
    }

    private func externalActionTitle(_ ref: Reference) -> String {
        switch ref.kind {
        case .link:    return "Open link"
        case .docNote: return "Open in Google Docs"
        case .file:    return "Open in Drive"
        }
    }

    private func openExternal(_ ref: Reference) {
        guard let url = externalURL(ref) else { return }
        openURL(url)
    }

    /// Quick Look a file reference — preview a cached copy if present, else best-effort
    /// download via the connected Google token; on failure fall back to opening in Drive.
    private func quickLook(_ ref: Reference) {
        referenceError = nil
        if let cached = ReferencePreviewLoader.cachedURL(for: ref) {
            ReferencePreviewController.shared.present(cached)
            return
        }
        Task { @MainActor in
            do {
                let url = try await ReferencePreviewLoader.download(ref, auth: googleAuth)
                ReferencePreviewController.shared.present(url)
            } catch {
                openExternal(ref)
            }
        }
    }

    private func importFromDrive() {
        guard let jwt = auth.session?.accessToken else {
            referenceError = "Sign in to Atlas to import from Drive."
            return
        }
        guard DrivePickerConfig.isConfigured else {
            referenceError = "Drive picker keys missing — add DRIVE_PICKER_API_KEY / _APP_ID to Config/Secrets.xcconfig."
            return
        }
        referenceError = nil
        Task { @MainActor in
            do {
                // The app's own drive.file token (native PKCE flow) — the picker
                // page runs with it directly; no Google sign-in in the webview.
                let token = try await googleAuth.validAccessToken()
                drivePicker = DrivePickerSession(googleAccessToken: token, supabaseJWT: jwt)
            } catch {
                referenceError = "Connect Google in Settings → Calendars to import from Drive."
            }
        }
    }

    /// Seed the editable starter sample-tasks once, for an empty project only.
    private func seedStarterIfNeeded() {
        guard !didSeedStarter, isEmptyProject else { return }
        starterTasks = ProjectTemplate.starter(for: project).sampleTasks
        didSeedStarter = true
    }

    // MARK: - Editable starter template (empty project)

    /// Shown only when `isEmptyProject`. A few editable sample-task placeholders
    /// the user can rewrite or delete. Purely local scaffolding — nothing here is
    /// persisted, so it's never auto-saved junk; it just keeps the page useful.
    private var starterTemplate: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel("STARTER TASKS")
                Text("editable suggestions — rewrite or remove")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
            }

            if starterTasks.isEmpty {
                Text("Cleared. Add an overview above to describe this project.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(starterTasks.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 14))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                            TextField("Task", text: $starterTasks[i])
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Spacer()
                            Button {
                                starterTasks.remove(at: i)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this suggestion")
                        }
                        .padding(.vertical, 9)
                        if i < starterTasks.count - 1 {
                            Divider().overlay(AtlasTheme.Colors.hairline)
                        }
                    }
                }
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 8) {
            tag(text: project.spaceName, color: project.spaceColor, filled: true)
            if project.isClass { tag(text: "Class", color: AtlasTheme.Colors.textSecondary, filled: false) }
            if project.canvasSynced {
                tag(text: "CANVAS SYNCED", color: AtlasTheme.Colors.accentText, filled: false)
            }
        }
    }

    private func tag(text: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 5) {
            if filled { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(text == text.uppercased() ? 0.8 : 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let code = project.code {
                    Text(code)
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                Text(project.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            HStack(spacing: 16) {
                if let m = project.meetingInfo { metaItem("calendar", m) }
                if let i = project.instructor { metaItem("person", i) }
                if project.canvasSynced { metaItem("folder", "Canvas + Drive", accent: true) }
            }
        }
    }

    private func metaItem(_ icon: String, _ text: String, accent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 12, design: .rounded))
        }
        .foregroundStyle(accent ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textSecondary)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionLabel("OVERVIEW")
                Spacer()
                if !isEditingOverview {
                    Button {
                        draftOverview = project.overview
                        isEditingOverview = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Edit overview")
                }
            }

            if isEditingOverview {
                overviewEditor
            } else if project.overview.isEmpty {
                Button {
                    // Empty project → pre-fill the editable template prompt so
                    // the user edits a starting point instead of a blank box.
                    draftOverview = isEmptyProject ? ProjectTemplate.starter(for: project).overview : ""
                    isEditingOverview = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("Add an overview…")
                            .font(.system(size: 13, design: .rounded))
                    }
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Text(project.overview)
                    .font(.system(size: 13, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
        }
    }

    private var overviewEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draftOverview.isEmpty {
                    Text("What is this project about?")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.leading, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftOverview)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .tint(AtlasTheme.Colors.accent)
                    .frame(minHeight: 90)
            }
            .padding(.vertical, 4)
            .atlasHairlineBelow()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { isEditingOverview = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    state.updateProjectOverview(
                        projectID: project.id,
                        overview: draftOverview.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingOverview = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Live tasks

    private var liveTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("TASKS")
                Text("\(liveTasks.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(liveTasks.enumerated()), id: \.element.id) { i, task in
                    liveTaskRow(task)
                    if i < liveTasks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
        }
    }

    private func liveTaskRow(_ task: TaskItem) -> some View {
        Button { state.route = .task(task.id) } label: {
            HStack(spacing: 12) {
                Button {
                    state.toggleTask(task.id)
                } label: {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .font(.system(size: 13, design: .rounded))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                Spacer()
                if !task.dueLabel.isEmpty {
                    Text(task.dueLabel)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live events

    private var liveEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("EVENTS")
                Text("\(liveEvents.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(liveEvents.enumerated()), id: \.element.id) { i, event in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(event.color)
                            .frame(width: 3, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text("\(event.timeLabel) · \(event.durationLabel)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    if i < liveEvents.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PINNED RESOURCES")
            HStack(spacing: 10) {
                ForEach(project.pinned) { res in
                    HStack(spacing: 8) {
                        Image(systemName: res.systemImage)
                            .font(.system(size: 12))
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(res.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text(res.source)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var linkedReferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Text("LINKED REFERENCES").atlasCapsLabel()
                Text("\(project.backlinks.count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }

            VStack(spacing: 0) {
                ForEach(Array(project.backlinks.enumerated()), id: \.element.id) { i, link in
                    HStack(spacing: 10) {
                        Circle().fill(link.color).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text(link.meta)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .padding(.vertical, 10)
                    if i < project.backlinks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }

            Text("Every task, event, and note that mentions this Class appears here automatically.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.top, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).atlasCapsLabel()
    }
}
