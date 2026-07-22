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
    @State private var presentInvite = false

    /// Inline title editing: click the name to edit, commit on Return or blur.
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    /// The project-color swatch popover anchored on the title dot.
    @State private var showColorPicker = false

    /// Add-link sheet toggle, and the last import/Quick-Look problem to surface calmly.
    @State private var presentAddLink = false
    @State private var referenceError: String?
    /// True while the onepick Drive import is running (browser open, waiting sheet up).
    @State private var isImporting = false
    /// The live loopback listener for the in-flight import, so Cancel can stop it.
    @State private var pickerListener: PickerRedirectListener?

    /// Editable starter sample-tasks for an empty project. Seeded once from
    /// `ProjectTemplate`; purely local (never persisted) — the user can edit or
    /// delete them so a new project shows useful scaffolding instead of blank.
    @State private var starterTasks: [String] = []
    @State private var didSeedStarter = false

    /// Note currently open in the editor sheet (nil = closed). A brand-new note is
    /// an unsaved draft pre-linked to this project.
    @State private var editingNote: Note?

    /// Whether the collapsed completed-tasks / past-events groups are expanded.
    @State private var showCompleted = false
    @State private var showPast = false

    /// All tasks tagged to this project, deadline-ordered.
    private var allTasks: [TaskItem] {
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

    /// Open tasks (plus just-checked ones still lingering) — the default list.
    private var liveTasks: [TaskItem] {
        allTasks.filter(state.isVisiblyPending)
    }

    /// Checked-off tasks behind the "N COMPLETED" reveal, newest finish first.
    private var completedTasks: [TaskItem] {
        allTasks
            .filter(state.isSettledDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// All events tagged to this project, in time order.
    private var allEvents: [CalendarEvent] {
        state.events
            .filter { $0.spaceName == project.spaceName && ($0.projectID == project.id || $0.subtitle == project.name) }
            .sorted { $0.start < $1.start }
    }

    /// Upcoming (or still in progress) events — the default list.
    private var liveEvents: [CalendarEvent] {
        allEvents.filter { $0.end >= state.now }
    }

    /// Elapsed events behind the "N PAST" reveal, most recent first.
    private var pastEvents: [CalendarEvent] {
        allEvents.filter { $0.end < state.now }.sorted { $0.start > $1.start }
    }

    private var isEmptyProject: Bool {
        project.overview.isEmpty && allTasks.isEmpty
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                // Main column
                VStack(alignment: .leading, spacing: 22) {
                    badges
                    titleBlock
                    if project.isClass { CanvasCoursePicker(project: project) }
                    overview
                    if !liveTasks.isEmpty || !completedTasks.isEmpty { liveTasksSection }
                    if !liveEvents.isEmpty || !pastEvents.isEmpty    { liveEventsSection }
                    if state.isShared(project) { teamSection }
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
        // Surface server-side reference/note changes (the cron flips pending→synced,
        // fills doc-note bodies, and re-pulls later Google edits) without a relaunch:
        // refresh on entry, then keep refreshing while an import is settling (fast) OR
        // any Doc-note is present (steady) — a Doc can change on Google's side any time,
        // so its rows' "Last synced" and content stay fresh while the project is open.
        // Stops when nothing can change server-side. Cancelled automatically on exit.
        .task(id: project.id) {
            await state.reloadReferences()
            while !Task.isCancelled {
                let refs = state.references(in: project.id)
                let hasPending  = refs.contains { $0.syncState == .pending }
                let hasDocNotes = refs.contains { $0.kind == .docNote }
                guard hasPending || hasDocNotes else { break }
                try? await Task.sleep(for: .seconds(hasPending ? 20 : 45))
                await state.reloadReferences()
            }
        }
        // Corner-card editor (not a modal sheet): the project stays visible behind
        // it; drag-resize and expand live in `NoteCardOverlay`.
        .overlay(alignment: .bottomTrailing) {
            if let note = editingNote {
                NoteCardOverlay(note: note) { editingNote = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: editingNote?.id)
        .sheet(isPresented: $presentAddLink) {
            AddLinkSheet(projectID: project.id)
        }
        // Onepick Drive import: a calm "waiting" sheet while the user chooses files
        // in the browser. The flow re-pulls the reference pool itself when it lands;
        // the sheet auto-dismisses when `isImporting` flips back to false.
        .sheet(isPresented: $isImporting) { importWaitingSheet }
    }

    /// Shown while the onepick browser round-trip is in flight.
    private var importWaitingSheet: some View {
        VStack(spacing: 18) {
            Text("Import from Drive")
                .atlasFont(size: 19, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            ProgressView().controlSize(.large)
            Text("Continue in your browser to choose files…")
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel") {
                pickerListener?.stop()
                pickerListener = nil
                isImporting = false
            }
            .buttonStyle(.plain)
            .atlasFont(size: 14, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
            .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 360)
        .background(AtlasTheme.Colors.bgBase)
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
                        Image(systemName: "plus").atlasFont(size: 11, weight: .semibold)
                        Text("New").atlasFont(size: 12, weight: .semibold, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .help("New note in this project")
            }
            .projectSectionHeader()

            if projectNotes.isEmpty {
                Text("No notes yet. Notes you add here live in this project — and, once Google is connected, sync to a Drive folder for \(project.name) as Google Docs.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
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
                .atlasFont(size: 15)
                .foregroundStyle(linked ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled note" : note.title)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if !note.body.isEmpty {
                    Text(note.previewText)
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if linked {
                Text("Doc ↗").atlasFont(size: 11, design: .rounded).foregroundStyle(AtlasTheme.Colors.accentText)
            }
            Image(systemName: "chevron.right")
                .atlasFont(size: 10, weight: .medium)
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
        draft.spaceID = project.spaceID
        editingNote = draft
    }

    // MARK: - References (Docs → Notes import)

    /// The project's reference pool — Docs imported as editable notes, view-only
    /// Drive files, and external links (see docs/specs/2026-07-03-notes-import-design.md).
    /// "Import" runs the onepick Drive flow (`importFromDrive()`) in the system
    /// browser; imported references surface when it lands.
    private var referencesSection: some View {
        let refs = state.references(in: project.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                sectionLabel("REFERENCES")
                if !refs.isEmpty {
                    Text("\(refs.count)")
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                referenceHeaderButton(icon: "arrow.down.doc", title: "Import") { importFromDrive() }
                    .help("Import Google Docs and files from Drive")
                referenceHeaderButton(icon: "link", title: "Add link") { presentAddLink = true }
                    .help("Attach an external link")
            }
            .projectSectionHeader()

            if let referenceError {
                HStack(spacing: 8) {
                    Text(referenceError)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.danger)
                    Button("Report this") { state.reportBug(prefillTitle: referenceError) }
                        .buttonStyle(.plain)
                        .atlasFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
            }

            if refs.isEmpty {
                Text("No references yet. Import Google Docs, PDFs, and files from Drive, or add a link — they live in this project and can attach to its tasks and events.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
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
                            onEditNote: ref.kind == .docNote ? { openReference(ref) } : nil,
                            onSyncNow: ref.kind == .docNote ? {
                                // Force a real Google pull for this reference first (best-effort),
                                // then reload to surface it — falls back to reload-only on failure.
                                _ = await ReferencePullClient(accessToken: { await auth.validAccessToken() }).pull(referenceID: ref.id)
                                await state.reloadReferences()
                            } : nil,
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
                Image(systemName: icon).atlasFont(size: 11, weight: .semibold)
                Text(title).atlasFont(size: 12, weight: .semibold, design: .rounded)
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

    /// Runs Google's desktop-picker (onepick) flow: open the top-level Google file
    /// chooser in the system browser (Safari-safe — no third-party cookies), capture
    /// the picked ids via a loopback listener (bounced through the public-HTTPS
    /// redirect), enrich them with Drive metadata, and POST the unchanged
    /// `{projectId, files[]}` contract to `drive-import`.
    private func importFromDrive() {
        guard auth.session != nil else {
            referenceError = "Sign in to Atlas to import from Drive."
            return
        }
        guard googleAuth.isConnected else {
            referenceError = "Connect Google in Settings → Calendars to import from Drive."
            return
        }
        guard googleAuth.hasDriveScope else {
            referenceError = "Reconnect Google in Settings to enable Drive import."
            return
        }
        guard DriveOnePickConfig.isConfigured else {
            referenceError = "Drive import isn't configured — set DRIVE_ONEPICK_REDIRECT_URI in Config/Secrets.xcconfig."
            return
        }
        referenceError = nil
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let listener = PickerRedirectListener()
                pickerListener = listener
                let port = try await listener.start()
                let nonce = UUID().uuidString
                let authURL = DriveOnePick.authorizationURL(
                    clientID: DriveOnePickConfig.webClientID,
                    redirectURI: DriveOnePickConfig.redirectURI,
                    state: "\(port).\(nonce)")
                NSWorkspace.shared.open(authURL)

                let ids = try await listener.waitForPickedFileIDs(expectedState: nonce)
                pickerListener = nil
                guard !ids.isEmpty else { return }

                let files = ids.map { PickedFile(id: $0) }
                // Mint the JWT only now: the interactive picker round-trip can outlive
                // the 1-hour token TTL, so a click-time capture arrives expired.
                guard let jwt = await auth.validAccessToken() else {
                    referenceError = "Your Atlas session expired — sign in again to finish the import."
                    return
                }
                let result = try await registerDriveImports(projectID: project.id, files: files, jwt: jwt)
                await state.reloadReferences()
                // Every picked file failed server-side enrichment (imported 0): surface it
                // rather than let the import vanish silently.
                if result.imported == 0 {
                    referenceError = "Couldn't import the selected file(s) — try reconnecting Google in Settings."
                }
            } catch is DriveOnePickError {
                // User cancelled or the wait timed out — nothing to surface.
                pickerListener = nil
            } catch {
                pickerListener = nil
                referenceError = "Drive import didn't finish — \(error.localizedDescription)"
                AtlasLog.append("Drive import failed: \(error.localizedDescription)")
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
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
            }
            .projectSectionHeader()

            if starterTasks.isEmpty {
                Text("Cleared. Add an overview above to describe this project.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(starterTasks.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: "circle.dashed")
                                .atlasFont(size: 15, weight: .medium)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                            TextField("Task", text: $starterTasks[i])
                                .textFieldStyle(.plain)
                                .atlasFont(size: 14, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Spacer()
                            Button {
                                starterTasks.remove(at: i)
                            } label: {
                                Image(systemName: "trash")
                                    .atlasFont(size: 12, weight: .medium)
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
            atlasTag(text: project.spaceName, color: project.spaceColor)
            if project.isClass { atlasTag(text: "Class", color: AtlasTheme.Colors.textSecondary) }
            if project.canvasSynced {
                atlasTag(text: "CANVAS SYNCED", color: AtlasTheme.Colors.accentText)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Color dot → popover recolor (mirrors the space page's dot).
                Button { showColorPicker = true } label: {
                    Circle().fill(projectDotColor).frame(width: 14, height: 14)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Change project color")
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    colorPickerPopover
                }

                if let code = project.code {
                    Text(code)
                        .atlasTitleSerif(size: 26)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                // Name — click to edit in place; commit on Return or blur.
                if isEditingName {
                    TextField("Project name", text: $draftName)
                        .textFieldStyle(.plain)
                        .atlasTitleSerif(size: 26)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .focused($nameFieldFocused)
                        .frame(maxWidth: 360)
                        .onSubmit(commitName)
                        .onChange(of: nameFieldFocused) { focused in
                            if !focused { commitName() }
                        }
                } else {
                    Text(project.name)
                        .atlasTitleSerif(size: 26)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .onTapGesture {
                            draftName = project.name
                            isEditingName = true
                            nameFieldFocused = true
                        }
                        .help("Click to rename")
                }
                Spacer()
                Button { addTaskToProject() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").atlasFont(size: 11, weight: .semibold)
                        Text("Add Task").atlasFont(size: 13, weight: .medium, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .help("Add a task to \(project.name)")
                Button {
                    presentInvite = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus").atlasFont(size: 11, weight: .semibold)
                        Text("Invite people").atlasFont(size: 13, weight: .medium, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .help("Invite someone to collaborate on this project")
                .sheet(isPresented: $presentInvite) {
                    InviteMemberSheet(projectId: project.id, projectName: project.name)
                }
            }
            HStack(spacing: 16) {
                if let m = project.meetingInfo { metaItem("calendar", m) }
                if let i = project.instructor { metaItem("person", i) }
                if project.canvasSynced { metaItem("folder", "Canvas + Drive", accent: true) }
            }
        }
    }

    /// The dot's fill: the project's own color when it set one, else the space color.
    private var projectDotColor: Color {
        if let token = project.colorToken { return ColorToken.color(for: token) }
        return project.spaceColor
    }

    /// PROJECT COLOR popover (mirrors the space page): an "inherit space color"
    /// swatch plus the four theme tokens. Picking a token tints this project's
    /// day/week-grid tiles and its sidebar dot; inherit clears back to the space color.
    private var colorPickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROJECT COLOR").atlasCapsLabel()
            // Inherit (default): hollow circle in the space color, selected when no token.
            Button {
                state.setProjectColorToken(projectID: project.id, token: nil)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(project.spaceColor, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(AtlasTheme.Colors.textPrimary,
                                        lineWidth: project.colorToken == nil ? 2.5 : 0)
                                .padding(-3)
                        )
                    Text("Inherit space color")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            AtlasColorGrid(selected: project.colorToken == nil ? nil : projectDotColor) { color in
                state.setProjectColorToken(projectID: project.id,
                                           token: ColorToken.token(for: color))
            }
        }
        .padding(16)
    }

    /// Persist the edited name (rename carries dependent tasks/events along) and
    /// leave edit mode. A blank or unchanged name is discarded by `renameProject`.
    private func commitName() {
        guard isEditingName else { return }
        isEditingName = false
        state.renameProject(id: project.id, to: draftName)
    }

    /// Open the shared Quick-Capture bar tagged to this project, so the task it
    /// creates lands here (and in this space) instead of being AI-routed.
    private func addTaskToProject() {
        state.captureContext = CaptureContext(spaceName: project.spaceName,
                                              projectName: project.name)
        state.presentCapture = true
    }

    private func metaItem(_ icon: String, _ text: String, accent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).atlasFont(size: 11)
            Text(text).atlasFont(size: 13, design: .rounded)
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
                            .atlasFont(size: 12, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Edit overview")
                }
            }
            .projectSectionHeader()

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
                            .atlasFont(size: 12)
                        Text("Add an overview…")
                            .atlasFont(size: 14, design: .rounded)
                    }
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Text(project.overview)
                    .atlasFont(size: 14, design: .rounded)
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
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.leading, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftOverview)
                    .atlasFont(size: 14, design: .rounded)
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
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    state.updateProjectOverview(
                        projectID: project.id,
                        overview: draftOverview.trimmingCharacters(in: .whitespacesAndNewlines))
                    isEditingOverview = false
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
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
                if !liveTasks.isEmpty {   // "TASKS 0" over a completed-only reveal reads as a bug
                    Text("\(liveTasks.count)")
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
            }
            .projectSectionHeader()
            VStack(spacing: 0) {
                ForEach(Array(liveTasks.enumerated()), id: \.element.id) { i, task in
                    liveTaskRow(task)
                    if i < liveTasks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
            if !completedTasks.isEmpty {
                RevealRow(count: completedTasks.count, noun: "COMPLETED", isOpen: $showCompleted)
                if showCompleted {
                    VStack(spacing: 0) {
                        ForEach(Array(completedTasks.enumerated()), id: \.element.id) { i, task in
                            liveTaskRow(task, trailingLabel: task.completedAt.map(LifecycleDate.short) ?? "")
                            if i < completedTasks.count - 1 {
                                Divider().overlay(AtlasTheme.Colors.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func liveTaskRow(_ task: TaskItem, trailingLabel: String? = nil) -> some View {
        Button { state.route = .task(task.id) } label: {
            HStack(spacing: 12) {
                Button {
                    withAnimation(AtlasTheme.taskCrossOut) { state.toggleTask(task.id) }
                } label: {
                    Image(systemName: task.done ? "checkmark.square.fill" : "square")
                        .atlasFont(size: 17)
                        .foregroundStyle(task.done ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .help(task.done ? "Mark not done" : "Mark done")

                Text(task.title)
                    .atlasFont(size: 14, design: .rounded)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                Spacer()
                let label = trailingLabel ?? task.dueLabel
                if !label.isEmpty {
                    Text(label)
                        .atlasMono(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Image(systemName: "chevron.right")
                    .atlasFont(size: 10, weight: .medium)
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
                if !liveEvents.isEmpty {
                    Text("\(liveEvents.count)")
                        .atlasMono(size: 10, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
            }
            .projectSectionHeader()
            VStack(spacing: 0) {
                ForEach(Array(liveEvents.enumerated()), id: \.element.id) { i, event in
                    LifecycleEventRow(event: event)
                    if i < liveEvents.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }
            if !pastEvents.isEmpty {
                RevealRow(count: pastEvents.count, noun: "PAST", isOpen: $showPast)
                if showPast {
                    VStack(spacing: 0) {
                        ForEach(Array(pastEvents.enumerated()), id: \.element.id) { i, event in
                            LifecycleEventRow(event: event, dimmed: true)
                            if i < pastEvents.count - 1 {
                                Divider().overlay(AtlasTheme.Colors.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Team (collab phase 3 — availability)

    private var teamSection: some View {
        TeamAvailabilityView(project: project)
            .task { await state.loadTeammateAvailability(forProject: project) }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PINNED RESOURCES")
                .projectSectionHeader()
            HStack(spacing: 10) {
                ForEach(project.pinned) { res in
                    HStack(spacing: 8) {
                        Image(systemName: res.systemImage)
                            .atlasFont(size: 13, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(res.title)
                                .atlasFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text(res.source)
                                .atlasFont(size: 11, weight: .medium, design: .rounded)
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
                Image(systemName: "link").atlasFont(size: 12, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Text("LINKED REFERENCES").atlasCapsLabel()
                Text("\(project.backlinks.count)")
                    .atlasMono(size: 11)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .projectSectionHeader()

            VStack(spacing: 0) {
                ForEach(Array(project.backlinks.enumerated()), id: \.element.id) { i, link in
                    HStack(spacing: 10) {
                        Circle().fill(link.color).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                                .atlasFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Text(link.meta)
                                .atlasFont(size: 11, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .atlasFont(size: 10, weight: .medium)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .padding(.vertical, 10)
                    if i < project.backlinks.count - 1 {
                        Divider().overlay(AtlasTheme.Colors.hairline)
                    }
                }
            }

            Text("Every task, event, and note that mentions this Class appears here automatically.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.top, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).atlasCapsLabel()
    }
}

private extension View {
    /// The shared section-header treatment (spec 3.2): the mono caps label already
    /// sits in the row; this makes it a full-width header with a hairline rule below,
    /// so every section reads with the same editorial mono+hairline heading.
    func projectSectionHeader() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
            .atlasHairlineBelow()
    }
}
