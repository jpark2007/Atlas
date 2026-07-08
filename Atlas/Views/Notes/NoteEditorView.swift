import SwiftUI
import AtlasCore

/// The constrained Atlas notes editor (WS-10). A focused rich-text view over a
/// `RichDoc` whose ONLY styling is the allowed subset:
///   • Block levels: Heading / Sub-heading / Normal — each with custom AtlasTheme
///     typography.
///   • Inline marks: bold / italic / underline (applied per focused block).
///   • Lists: bulleted / numbered.
/// Nothing else. The backing Google Doc is the styling master; this editor maps
/// onto that subset (see `GoogleDocsMapper`). Edits a working copy and commits on
/// Done — `init(note:onDone:)` is preserved so existing hosts keep compiling.
struct NoteEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The two-way Google-Doc write-back surface. Nil until `integrate` injects one
    /// (the concrete impl is a Supabase edge function — see `DocNoteWriteBack`).
    @Environment(\.docNoteWriteBack) private var writeBackService
    /// Pauses the doc-note freshness poll while the app is backgrounded (see `pollKey`).
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: Note
    @State private var doc: RichDoc
    @FocusState private var focusedBlock: UUID?
    /// True while a write-back is in flight — disables Done to avoid double-submits.
    @State private var isPushing = false
    /// Set when the write-back guard reports the Doc changed in Google since our pull.
    @State private var showStaleConflict = false
    /// `updatedAt` of the note version currently loaded in the editor — the baseline a
    /// cron pull is compared against, so we react only to versions newer than ours.
    @State private var baselineUpdatedAt: Date?
    /// True once the user edited title/body/formatting since load — gates whether a
    /// freshly-synced Google version silently replaces the buffer (clean) or only
    /// surfaces a banner (dirty), so unsaved work is never clobbered.
    @State private var isDirty = false
    /// Set when a newer synced version arrived while the buffer was dirty.
    @State private var newerVersionAvailable = false
    /// True while a manual "Sync now" reload is in flight.
    @State private var isSyncingNow = false

    /// Per-tab Google Doc sync (beta). OFF ⇒ behavior is identical to single-tab today:
    /// tabs never load, the switcher never renders, and saves take the legacy whole-file path.
    @AppStorage("notes.perTabDocsSync.enabled") private var perTabSyncEnabled = false
    /// Loaded tabs for a multi-tab Doc note (empty for single-tab docs or flag OFF). When
    /// non-empty the editor is in per-tab mode: `doc` holds ONE tab, saves are tab-scoped.
    @State private var docTabs: [DocNoteTab] = []
    /// The tab whose `bodyMD` is currently loaded into `doc`.
    @State private var selectedTab: DocNoteTab?
    /// Per-tab dirty flag — the analogue of `isDirty` for the selected tab's body, so a
    /// save/switch only pushes a tab the user actually edited (incl. style-only edits).
    @State private var tabDirty = false
    /// Legacy whole-file write refused because the Doc has tabs (flag OFF path).
    @State private var showMultitabNotice = false
    /// Per-tab write refused because the tab's live content is beyond the editable vocabulary.
    @State private var showTabReadOnlyNotice = false

    private let onDone: ((Note) -> Void)?
    /// Overlay hosts (the corner note card) can't rely on `dismiss` — it only works
    /// in real presentations (sheets). They pass a close callback instead.
    private let onDismiss: (() -> Void)?
    /// True when the host owns the frame + card chrome (background/border/size);
    /// the editor then fills the space it's given instead of its fixed 560-wide card.
    private let chromeless: Bool

    init(note: Note, chromeless: Bool = false,
         onDone: ((Note) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _draft = State(initialValue: note)
        _doc = State(initialValue: RichDoc.fromPlainText(note.body))
        self.chromeless = chromeless
        self.onDone = onDone
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            if chromeless {
                core
            } else {
                core
                    .frame(width: 560)
                    .frame(minHeight: 420)
                    .background(AtlasTheme.Colors.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                    )
            }
        }
        // Markdown bodies — a linked Doc-note (always Markdown) or a rich native
        // note — parse structurally; legacy plain natives keep the plain-text
        // path from `init`. `isMarkdownBody` is the single rule (it covers a
        // Doc-note even before `state.references` has loaded, via googleDocId).
        .onAppear {
            // Adopt the freshest persisted version (the passed snapshot can predate a
            // cron pull), parse a Markdown body, and set the baseline.
            if let live = liveNote { draft = live }
            if draft.isMarkdownBody || docReference != nil {
                doc = RichDoc.fromMarkdown(draft.body)
            }
            baselineUpdatedAt = liveNote?.updatedAt ?? draft.updatedAt
        }
        // Per-tab mode (flag ON + multi-tab Doc): load the tabs and switch `doc` to the
        // first tab's body. Single-tab Docs and flag OFF fall through untouched — `docTabs`
        // stays empty and every path below behaves exactly as it does today.
        .task {
            guard perTabSyncEnabled, let ref = docReference else { return }
            let tabs = await state.loadDocTabs(referenceID: ref.id)
            guard tabs.count > 1 else { return }
            docTabs = tabs
            let first = tabs[0]
            selectedTab = first
            doc = RichDoc.fromMarkdown(first.bodyMD)
        }
        // Keep an OPEN Doc-note fresh without navigating away: pull the latest from the
        // Atlas cloud on a gentle cadence (the cron writes Google→DB every ~5 min; this
        // surfaces it into `state.notes`). Native notes have nothing to pull — Doc-only.
        // Keyed on `pollKey` so it only runs in the foreground (pauses while backgrounded).
        .task(id: pollKey) {
            guard docReference != nil, scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await state.reloadReferences()
            }
        }
        // A cron pull bumps the backing note's updatedAt; reconcile it into the editor.
        .onChange(of: liveNote?.updatedAt) { _, _ in reconcileSyncedVersion() }
        .confirmationDialog("This Doc changed in Google Docs",
                            isPresented: $showStaleConflict, titleVisibility: .visible) {
            Button("Overwrite Google Doc", role: .destructive) {
                if let ref = docReference, let service = writeBackService {
                    isPushing = true
                    Task { await push(ref: ref, service: service, overwrite: true) }
                }
            }
            Button("Keep Google's version") {
                // Discard local edits; the cron re-pulls the newer Doc into the note.
                closeHost()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your edits and the Google Doc have diverged. Overwrite replaces the Doc with your version; keeping Google's discards your local edits.")
        }
        .alert("This Doc has multiple tabs", isPresented: $showMultitabNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Atlas kept your local copy but didn't push it — enable per-tab sync in Settings → General, or edit this Doc in Google Docs.")
        }
        .alert("Tab is read-only", isPresented: $showTabReadOnlyNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This tab's content (table, image, or rich formatting) can only be edited in Google Docs.")
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: titleBinding)
                .textFieldStyle(.plain)
                .atlasTitleSerif(size: 17)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

            if let ref = docReference { docBadgeRow(ref) }
            if newerVersionAvailable { newerVersionBanner }

            if !docTabs.isEmpty {
                AtlasSegmentedPicker(
                    options: docTabs,
                    label: { $0.displayTitle(in: docTabs) },
                    selection: Binding(
                        get: { selectedTab ?? docTabs[0] },
                        set: { switchTab(to: $0) }
                    )
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                if let tab = selectedTab, !tab.writable {
                    readOnlyTabBanner(tab)
                }
            }

            styleBar
                .disabled(tabReadOnly)

            Divider().overlay(AtlasTheme.Colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(doc.blocks.enumerated()), id: \.element.id) { index, block in
                        blockRow(index: index, block: block)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 200)
            .disabled(tabReadOnly)

            Divider().overlay(AtlasTheme.Colors.border)

            footer
        }
    }

    // MARK: - Linked Google Doc

    /// The `.docNote` reference backing this note, if any — the source of the linked
    /// badge, last-synced, "Open in Google Docs", and the write-back target.
    private var docReference: Reference? {
        state.references.first { $0.kind == .docNote && $0.noteID == draft.id }
    }

    private var docURL: URL? { docReference?.externalURL }

    /// True when the selected multi-tab Doc tab is read-only — locks the style bar and
    /// block editors. `false` for single-tab / flag-OFF (no `selectedTab`).
    private var tabReadOnly: Bool { selectedTab.map { !$0.writable } ?? false }

    /// The tab a per-tab save targets. `nil` for single-tab / flag-OFF (the legacy
    /// whole-file write-back path); the selected tab's id in per-tab mode.
    private var activeTabId: String? { docTabs.isEmpty ? nil : selectedTab?.tabId }

    /// The persisted note this editor backs, looked up live so a cron pull is observable
    /// (the passed `note` is a value snapshot that never updates on its own).
    private var liveNote: Note? { state.notes.first { $0.id == draft.id } }

    /// Re-keys the freshness poll on the note AND the app's scene phase, so backgrounding
    /// cancels the loop (the `scenePhase == .active` guard returns early) and returning to
    /// the foreground restarts it — the poll never runs off-screen.
    private var pollKey: String { "\(draft.id.uuidString)-\(scenePhase)" }

    /// A subtle linked badge + LIVE sync state, a "Sync now" refresh, and the "Open in
    /// Google Docs" escape hatch.
    private func docBadgeRow(_ ref: Reference) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.accentText)
            atlasTag(text: "Google Doc", color: AtlasTheme.Colors.accentText)
            syncSubtitleView(ref)
            Spacer()
            syncNowButton
            if let url = docURL {
                Button { openURL(url) } label: {
                    HStack(spacing: 3) {
                        Text("Open in Google Docs")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    /// Live "Last synced Xm ago" — `Text(_:style:.relative)` self-updates, so it never
    /// freezes at render. Non-synced states keep their static one-liner.
    @ViewBuilder
    private func syncSubtitleView(_ ref: Reference) -> some View {
        switch ref.syncState {
        case .synced:
            if let d = ref.lastSyncedAt {
                lastSyncedText(d)
                    .font(AtlasTheme.Font.small())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                Text("· Synced")
                    .font(AtlasTheme.Font.small())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        case .stale:
            Text("· Changed in Google — save to overwrite")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.accentText)
        case .error:
            Text("· Sync error")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        case .pending:
            Text("· Not yet synced")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// "Last synced …" guarded so a near-now or clock-skewed-future timestamp reads
    /// "just now" rather than the signed-relative "in 3 sec ago".
    private func lastSyncedText(_ d: Date) -> Text {
        d.timeIntervalSinceNow < -1
            ? Text("· Last synced ") + Text(d, style: .relative) + Text(" ago")
            : Text("· Last synced just now")
    }

    /// On-demand freshness: re-reads the Atlas cloud (which the cron keeps in step with
    /// Drive). It can't force a Google pull — `google-sync` is service-role-only + a
    /// global tick — so this surfaces the last cron result immediately instead.
    private var syncNowButton: some View {
        Button {
            guard !isSyncingNow else { return }
            isSyncingNow = true
            Task { await state.reloadReferences(); isSyncingNow = false }
        } label: {
            Group {
                if isSyncingNow {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSyncingNow)
        .help("Sync now — check for the latest synced version")
    }

    /// Shown when a newer Google version synced while the buffer was dirty: we keep the
    /// user's edits (never clobber) and offer an explicit Reload. Pressing Done instead
    /// still trips the write-back staleness guard, so either path is safe.
    private var newerVersionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("A newer version synced from Google — your edits are kept.")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
            Button { if let live = liveNote { loadFresh(live) } } label: {
                Text("Reload")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .help("Discard local edits and load Google's version")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(AtlasTheme.Colors.warning.opacity(0.08))
    }

    /// Shown for a read-only tab (table/image/rich formatting Atlas can't safely rewrite):
    /// editing is locked and the escape hatch deep-links to THIS tab in Google Docs.
    /// Mirrors `newerVersionBanner`'s warning-tint styling.
    private func readOnlyTabBanner(_ tab: DocNoteTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.doc")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("This tab has content Atlas can't safely edit\(tab.readonlyReason.map { " (\($0))" } ?? "") — read-only here.")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
            Button {
                if let ref = docReference, let fileId = ref.driveFileId,
                   let url = URL(string: "https://docs.google.com/document/d/\(fileId)/edit?tab=\(tab.tabId)") {
                    openURL(url)
                }
            } label: {
                Text("Open in Google Docs")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .help("Edit this tab in Google Docs")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(AtlasTheme.Colors.warning.opacity(0.08))
    }

    /// Switch the editor to another tab, saving the current tab first if it was edited
    /// (fire-and-forget; the editor stays open regardless of the push outcome). Reloads
    /// the target tab's Markdown into `doc` and clears the per-tab dirty flag.
    private func switchTab(to tab: DocNoteTab) {
        guard tab.id != selectedTab?.id else { return }
        if tabDirty, let current = selectedTab, current.writable, let ref = docReference {
            let markdown = doc.markdown
            let service = writeBackService
            Task { _ = try? await service?.writeBack(reference: ref, markdown: markdown, tabId: current.tabId, overwrite: false) }
        }
        selectedTab = tab
        doc = RichDoc.fromMarkdown(tab.bodyMD)
        tabDirty = false
    }

    /// React to a cron pull that advanced the backing note past our loaded baseline.
    /// Clean buffer → adopt Google's version live. Dirty buffer → keep the user's work
    /// and only raise the banner.
    private func reconcileSyncedVersion() {
        guard docReference != nil, let live = liveNote,
              let baseline = baselineUpdatedAt, live.updatedAt > baseline else { return }
        if isDirty { newerVersionAvailable = true } else { loadFresh(live) }
    }

    /// Replace the buffer with a freshly-synced note version (clean auto-refresh, or the
    /// explicit Reload). Always a Doc-note here, so parse the Markdown body.
    private func loadFresh(_ live: Note) {
        draft = live
        doc = RichDoc.fromMarkdown(live.body)
        baselineUpdatedAt = live.updatedAt
        isDirty = false
        newerVersionAvailable = false
    }

    // MARK: - Style bar (the only styling Atlas allows)

    private var styleBar: some View {
        HStack(spacing: 6) {
            levelButton("Heading", kind: .heading)
            levelButton("Sub-heading", kind: .subheading)
            levelButton("Normal", kind: .normal)

            Divider().frame(height: 16).overlay(AtlasTheme.Colors.border)

            markButton("bold", mark: .bold)
            markButton("italic", mark: .italic)
            markButton("underline", mark: .underline)

            Divider().frame(height: 16).overlay(AtlasTheme.Colors.border)

            listButton("list.bullet", kind: .bulleted)
            listButton("list.number", kind: .numbered)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func levelButton(_ title: String, kind: RichDoc.BlockKind) -> some View {
        let active = isActiveKind(kind)
        return Button { doc.setKind(kind, at: activeIndex); isDirty = true; tabDirty = true } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active ? AtlasTheme.Colors.textPrimary : Color.clear,
                                      lineWidth: AtlasTheme.rule)
                )
        }
        .buttonStyle(.plain)
    }

    private func markButton(_ systemImage: String, mark: RichDoc.InlineMarks) -> some View {
        let active = isActiveMark(mark)
        return Button { doc.toggleMark(mark, at: activeIndex); isDirty = true; tabDirty = true } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                .frame(width: 24, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active ? AtlasTheme.Colors.textPrimary : Color.clear,
                                      lineWidth: AtlasTheme.rule)
                )
        }
        .buttonStyle(.plain)
    }

    private func listButton(_ systemImage: String, kind: RichDoc.BlockKind) -> some View {
        let active = isActiveKind(kind)
        return Button { doc.toggleListKind(kind, at: activeIndex); isDirty = true; tabDirty = true } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                .frame(width: 24, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active ? AtlasTheme.Colors.textPrimary : Color.clear,
                                      lineWidth: AtlasTheme.rule)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Block row

    @ViewBuilder
    private func blockRow(index: Int, block: RichDoc.Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if block.kind.isList {
                Text(listGlyph(for: index, block: block))
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(minWidth: 18, alignment: .trailing)
            }
            TextField("", text: textBinding(for: index), axis: .vertical)
                .textFieldStyle(.plain)
                .font(font(for: block.kind))
                .bold(block.uniformMarks.contains(.bold))
                .italic(block.uniformMarks.contains(.italic))
                .underline(block.uniformMarks.contains(.underline))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .focused($focusedBlock, equals: block.id)
                .onSubmit { addBlockAfter(index) }
        }
    }

    private func listGlyph(for index: Int, block: RichDoc.Block) -> String {
        block.kind == .numbered ? "\(numberOrdinal(at: index))." : "•"
    }

    /// Ordinal within the contiguous run of numbered blocks ending at `index`.
    private func numberOrdinal(at index: Int) -> Int {
        var ordinal = 1
        var i = index - 1
        while i >= 0, doc.blocks[i].kind == .numbered {
            ordinal += 1
            i -= 1
        }
        return ordinal
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(docReference == nil
                 ? "Saved in Atlas · constrained editor"
                 : "Two-way with Google Doc")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
            Button { addBlockAfter(doc.blocks.count - 1) } label: {
                Label("Block", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            Button(action: commit) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPushing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Editing helpers

    /// The block the style bar acts on — the focused block, else the last block.
    private var activeIndex: Int {
        if let id = focusedBlock, let index = doc.blocks.firstIndex(where: { $0.id == id }) {
            return index
        }
        return max(0, doc.blocks.count - 1)
    }

    private func isActiveKind(_ kind: RichDoc.BlockKind) -> Bool {
        doc.blocks.indices.contains(activeIndex) && doc.blocks[activeIndex].kind == kind
    }

    private func isActiveMark(_ mark: RichDoc.InlineMarks) -> Bool {
        doc.blocks.indices.contains(activeIndex) && doc.blocks[activeIndex].uniformMarks.contains(mark)
    }

    /// Title edits flow through this so a user change flips `isDirty` — a plain
    /// `$draft.title` binding couldn't, and `.onChange(of:)` can't tell a user edit
    /// from a programmatic `loadFresh`.
    private var titleBinding: Binding<String> {
        Binding(
            get: { draft.title },
            set: { draft.title = $0; isDirty = true })
    }

    private func textBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { doc.blocks.indices.contains(index) ? doc.blocks[index].text : "" },
            set: { newValue in
                guard doc.blocks.indices.contains(index) else { return }
                doc.blocks[index].setText(newValue)
                isDirty = true
                tabDirty = true
            })
    }

    private func addBlockAfter(_ index: Int) {
        let newID = doc.insertBlock(after: index)
        isDirty = true
        tabDirty = true
        DispatchQueue.main.async { focusedBlock = newID }
    }

    private func font(for kind: RichDoc.BlockKind) -> Font {
        switch kind {
        case .heading:    return .system(size: 22, weight: .bold, design: .rounded)
        case .subheading: return .system(size: 17, weight: .semibold, design: .rounded)
        case .normal, .bulleted, .numbered: return AtlasTheme.Font.body()
        }
    }

    /// Close whichever host is presenting us — the corner card (`onDismiss`) or a
    /// sheet (`dismiss`). Exclusive on purpose: calling `dismiss` with no active
    /// presentation walks SwiftUI's fallback chain and closes the whole WINDOW.
    private func closeHost() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    private func commit() {
        doc.normalize()
        if let ref = docReference {
            commitDocNote(ref)
        } else {
            // Native notes save Markdown too, so headings/marks/lists persist.
            // A legacy plain body converts here, on its first edit.
            var updated = draft
            updated.body = doc.markdown
            updated.bodyFormat = .md
            state.updateNote(updated)
            onDone?(updated)
            closeHost()
        }
    }

    /// Save path for a linked Doc-note: persist the Markdown body locally, then push
    /// to Google through the write-back guard. With no service wired yet the local
    /// save still lands and the cron reconciles later.
    private func commitDocNote(_ ref: Reference) {
        // Per-tab mode: notes.body is a cron-owned preview, so a single tab's Markdown must
        // never persist over it. A read-only or unedited tab has nothing to push — just close.
        if !docTabs.isEmpty {
            if tabReadOnly || !tabDirty {
                closeHost()
                return
            }
            guard let service = writeBackService else { closeHost(); return }
            isPushing = true
            Task { await push(ref: ref, service: service, overwrite: false) }
            return
        }
        // Single-tab / flag-OFF: legacy whole-file path, unchanged.
        guard let service = writeBackService else {
            persistDocNoteBody()
            closeHost()
            return
        }
        isPushing = true
        Task { await push(ref: ref, service: service, overwrite: false) }
    }

    @MainActor
    private func push(ref: Reference, service: DocNoteWriteBack, overwrite: Bool) async {
        defer { isPushing = false }
        do {
            switch try await service.writeBack(reference: ref, markdown: doc.markdown, tabId: activeTabId, overwrite: overwrite) {
            case .written(let modifiedTime):
                // Sync the in-memory baseline to what the server just re-stored, so a
                // second save this session doesn't compare against a now-stale time.
                if let modifiedTime { state.markReferenceSynced(ref.id, modifiedTime: modifiedTime) }
                // Single-tab persists the whole-note Markdown; a multi-tab Doc's notes.body is
                // the cron-owned preview the server refreshes, so one tab must not overwrite it.
                if docTabs.isEmpty { persistDocNoteBody() }
                closeHost()
            case .changedInGoogle:
                showStaleConflict = true   // surface refresh/overwrite; stay open
            case .multitabUnsupported:
                // Legacy whole-file path (flag OFF) refused because the Doc grew tabs: keep the
                // local copy and tell the user nothing was pushed. Stay open behind the alert.
                persistDocNoteBody()
                showMultitabNotice = true
            case .tabReadOnly:
                // Server re-verified this tab as read-only since our pull (it gained rich
                // content in Google). Don't clobber the preview; surface the notice, stay open.
                showTabReadOnlyNotice = true
            }
        } catch {
            // Never lose the single-tab user's work: keep the local Markdown copy and close;
            // the cron will push it on the next tick. Multi-tab keeps the cron preview intact.
            if docTabs.isEmpty { persistDocNoteBody() }
            closeHost()
        }
    }

    /// Stores the RichDoc as Markdown — the two-way transport form — so a linked
    /// Doc-note's structure survives the round-trip (native notes stay plain text).
    private func persistDocNoteBody() {
        var updated = draft
        updated.body = doc.markdown
        updated.bodyFormat = .md   // the stored body IS Markdown — keep the stamp honest
        state.updateNote(updated)
        // Advance the baseline past our OWN write so `reconcileSyncedVersion` doesn't read
        // this editor's save as a "newer version synced from Google" and false-banner. Safe
        // today because every save closes the card, but this guards a future keep-open save.
        baselineUpdatedAt = liveNote?.updatedAt ?? updated.updatedAt
        onDone?(updated)
    }
}

// MARK: - Write-back surface (integrate wires a concrete impl)

/// The outcome of a Google-Doc write-back attempt.
enum DocWriteBackOutcome: Equatable {
    /// Guard passed; the Doc was rewritten from the note's Markdown. Carries Drive's
    /// new `modifiedTime` (the re-baselined value the server stored) so the client can
    /// refresh its in-memory reference and not false-trip the guard on a rapid re-save.
    case written(modifiedTime: Date?)
    /// Drive moved past our stored `modifiedTime` — surface refresh/overwrite rather
    /// than blind-writing (the design doc's staleness guard).
    case changedInGoogle
    /// Legacy whole-file write refused: the Doc has tabs. Enable per-tab sync
    /// (Settings) or edit in Google Docs.
    case multitabUnsupported(tabCount: Int)
    /// Per-tab write refused: the tab's live content is beyond the editable
    /// vocabulary (table/image/rich formatting).
    case tabReadOnly(reason: String?)
}

/// Narrow client surface for the two-way Google-Doc write-back the design doc mandates:
/// a Supabase edge function takes the note's Markdown + the reference's expected
/// `modifiedTime`, performs the guard, and converts Markdown → Doc via Drive update.
/// No concrete impl exists yet — `integrate` injects one via `\.docNoteWriteBack`.
protocol DocNoteWriteBack {
    /// Push `markdown` to the Doc backing `reference`. `overwrite` skips the guard
    /// (used after the user chose "Overwrite Google Doc" on a stale conflict).
    /// `tabId` scopes a per-tab write for multi-tab Docs; `nil` is the legacy whole-file path.
    func writeBack(reference: Reference, markdown: String, tabId: String?, overwrite: Bool) async throws -> DocWriteBackOutcome
}

private struct DocNoteWriteBackKey: EnvironmentKey {
    static let defaultValue: DocNoteWriteBack? = nil
}

extension EnvironmentValues {
    var docNoteWriteBack: DocNoteWriteBack? {
        get { self[DocNoteWriteBackKey.self] }
        set { self[DocNoteWriteBackKey.self] = newValue }
    }
}
