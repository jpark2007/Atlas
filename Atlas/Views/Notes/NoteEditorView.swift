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
    /// On-demand "Sync now" pull. Nil until `integrate` injects one (the concrete impl
    /// is the `reference-pull` edge function — see `ReferencePullClient`).
    @Environment(\.referencePull) private var referencePull
    /// Pauses the doc-note freshness poll while the app is backgrounded (see `pollKey`).
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.atlasTextScale) private var textScale

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
    /// Re-hosted inline images for this note (all tabs), looked up by `objectId` when a
    /// block's text is an `![image:<id>]` placeholder. Empty for notes without images.
    @State private var docImages: [DocNoteImage] = []
    /// Ids of blocks that are FROZEN ISLANDS — `!>`-marked lines (tables, non-round-trip
    /// images, positioned-image tethers) the server splices AROUND on save. Captured at
    /// seed time by `seedDoc` from the RAW source line, never by live text matching, so a
    /// user who types "!> " into an editable block doesn't freeze their own work. These
    /// blocks render display-only; everything else stays editable.
    @State private var frozenBlockIDs: Set<UUID> = []
    /// Per-tab dirty flag — the analogue of `isDirty` for the selected tab's body, so a
    /// save/switch only pushes a tab the user actually edited (incl. style-only edits).
    @State private var tabDirty = false
    /// Legacy whole-file write refused because the Doc has tabs (flag OFF path).
    @State private var showMultitabNotice = false
    /// Per-tab write refused because the tab's live content is beyond the editable vocabulary.
    @State private var showTabReadOnlyNotice = false
    /// Write refused because the note's first pull hasn't landed yet (server belt).
    @State private var showNotSyncedNotice = false

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
                seedDoc(draft.body)
            }
            baselineUpdatedAt = liveNote?.updatedAt ?? draft.updatedAt
        }
        // Per-tab mode (flag ON + multi-tab Doc): load the tabs and switch `doc` to the
        // first tab's body. Single-tab Docs and flag OFF fall through untouched — `docTabs`
        // stays empty and every path below behaves exactly as it does today.
        .task {
            guard perTabSyncEnabled, docReference != nil else { return }
            // Images are keyed by note, so load them even for single-tab Docs (their
            // placeholders live in `notes.body`). Tabs only re-seat `doc` when >1.
            docImages = await state.loadDocImages(noteID: draft.id)
            let tabs = await state.loadDocTabs(noteID: draft.id)
            guard tabs.count > 1 else { return }
            docTabs = tabs
            let first = tabs[0]
            selectedTab = first
            seedDoc(first.bodyMD)
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
        .alert("Note not synced yet", isPresented: $showNotSyncedNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This note hasn't finished its first sync — try again in a moment.")
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
                // The switcher's intrinsic width grows with tab count/length; left
                // unbounded it drags the whole editor column wider than the card and
                // clips the leading edge. A horizontal scroller lets it exceed the
                // card width by scrolling instead of forcing it.
                ScrollView(.horizontal, showsIndicators: false) {
                    AtlasSegmentedPicker(
                        options: docTabs,
                        label: { $0.displayTitle(in: docTabs) },
                        selection: Binding(
                            get: { selectedTab ?? docTabs[0] },
                            set: { switchTab(to: $0) }
                        )
                    )
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 6)
            }
            // One banner at most — a pending first-sync lock outranks a read-only
            // tab, which outranks the (non-blocking) dropped-styling advisory.
            if syncPending {
                pendingSyncBanner
            } else if let tab = selectedTab, !tab.writable {
                readOnlyTabBanner(tab)
            } else if let tab = selectedTab, tab.droppedStyling {
                droppedStylingBanner
            }

            styleBar
                .disabled(tabReadOnly || syncPending)

            Divider().overlay(AtlasTheme.Colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(renderSegments) { segment in
                        switch segment {
                        case let .block(index, block):
                            blockRow(index: index, block: block)
                        case let .table(_, lines):
                            PipeTableView(rows: parsePipeTable(lines: lines))
                        case let .frozen(_, display):
                            frozenRow(display: display)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 200)
            // NOTE: editing is locked per-TextField (blockRow), not on this whole
            // subtree — a container-level .disabled would also swallow link taps
            // and context menus in read-only tabs.

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

    /// The Google-Docs deep link the "Edit Link" affordance opens: per-tab
    /// (`…/edit?tab=<tabId>`, mirroring `readOnlyTabBanner`'s construction) when in
    /// per-tab mode, else the plain doc URL. Link editing lives in Google Docs only.
    private var docDeepLinkURL: URL? {
        guard let ref = docReference, let fileId = ref.driveFileId else { return docURL }
        if let tabId = activeTabId {
            return URL(string: "https://docs.google.com/document/d/\(fileId)/edit?tab=\(tabId)")
        }
        return docURL
    }

    /// True when the selected multi-tab Doc tab is read-only — locks the style bar and
    /// block editors. `false` for single-tab / flag-OFF (no `selectedTab`).
    private var tabReadOnly: Bool { selectedTab.map { !$0.writable } ?? false }

    /// True while a linked Doc-note's first pull hasn't landed — editing is locked (no
    /// content to edit yet, and no baseline to write against). Clears once the cron (or
    /// "Sync now") pulls and flips the reference to `.synced`.
    private var syncPending: Bool { docReference?.syncState == .pending }

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
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            atlasTag(text: "Google Doc", color: AtlasTheme.Colors.accentText)
            syncSubtitleView(ref)
            Spacer()
            syncNowButton
            if let url = docURL {
                Button { openURL(url) } label: {
                    HStack(spacing: 3) {
                        Text("Open in Google Docs")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                        Image(systemName: "arrow.up.right").atlasFont(size: 10, weight: .semibold)
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
                    .atlasFont(size: 12, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                Text("· Synced")
                    .atlasFont(size: 12, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        case .stale:
            Text("· Changed in Google — save to overwrite")
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.accentText)
        case .error:
            Text("· Sync error")
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        case .pending:
            Text("· Not yet synced")
                .atlasFont(size: 12, weight: .medium)
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
            Task {
                // Force a real Google pull for this reference first (best-effort); the
                // reload then surfaces it. Falls back to reload-only when the client is
                // nil, there's no linked reference, or the pull fails.
                if let ref = docReference { _ = await referencePull?.pull(referenceID: ref.id) }
                await state.reloadReferences()
                isSyncingNow = false
            }
        } label: {
            Group {
                if isSyncingNow {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .atlasFont(size: 12, weight: .semibold)
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
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("A newer version synced from Google — your edits are kept.")
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
            Button { if let live = liveNote { loadFresh(live) } } label: {
                Text("Reload")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
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
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("This tab has content Atlas can't safely edit\(tab.readonlyReason.map { " (\($0))" } ?? "") — read-only here.")
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)   // wrap, never force width
            Spacer()
            Button {
                if let ref = docReference, let fileId = ref.driveFileId,
                   let url = URL(string: "https://docs.google.com/document/d/\(fileId)/edit?tab=\(tab.tabId)") {
                    openURL(url)
                }
            } label: {
                Text("Open in Google Docs")
                    .atlasFont(size: 12, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .help("Edit this tab in Google Docs")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(AtlasTheme.Colors.warning.opacity(0.08))
    }

    /// Non-blocking advisory for a WRITABLE tab whose text color/highlight (and
    /// similar cosmetic styles) were stripped on import — editing works normally.
    /// Mirrors `readOnlyTabBanner`'s warning-tint styling.
    private var droppedStylingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintpalette")
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("Text color / highlight from Google Docs isn't shown here — it's kept in Google unless you edit this tab in Atlas.")
                .atlasFont(size: 12)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)   // wrap, never force width
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(AtlasTheme.Colors.warning.opacity(0.08))
    }

    /// Shown while a linked Doc-note's first pull hasn't landed (`sync_state == pending`):
    /// editing is locked until the content arrives. Mirrors `readOnlyTabBanner`'s
    /// warning-tint styling; "Sync now" forces a pull (same path as `syncNowButton`).
    private var pendingSyncBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Text("First sync in progress — content loads shortly.")
                .atlasFont(size: 11)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
            Button {
                guard !isSyncingNow else { return }
                isSyncingNow = true
                Task {
                    if let ref = docReference { _ = await referencePull?.pull(referenceID: ref.id) }
                    await state.reloadReferences()
                    isSyncingNow = false
                }
            } label: {
                Text("Sync now")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
            .disabled(isSyncingNow)
            .help("Check for the first synced version")
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
            // Island-safe: escape any user block that fakes an `!>` marker before the push.
            let markdown = tabMarkdownForSave
            let service = writeBackService
            Task { _ = try? await service?.writeBack(reference: ref, markdown: markdown, tabId: current.tabId, overwrite: false) }
        }
        selectedTab = tab
        seedDoc(tab.bodyMD)
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
        if !docTabs.isEmpty, docReference != nil {
            // Per-tab mode: notes.body is the cron-owned concatenated preview —
            // reload the tab rows and re-seat the current tab instead of parsing
            // the preview into the buffer.
            Task {
                let tabs = await state.loadDocTabs(noteID: draft.id)
                guard tabs.count > 1 else { return }
                docTabs = tabs
                let current = tabs.first(where: { $0.tabId == selectedTab?.tabId }) ?? tabs[0]
                selectedTab = current
                seedDoc(current.bodyMD)
            }
        } else {
            seedDoc(live.body)
        }
        baselineUpdatedAt = live.updatedAt
        isDirty = false
        tabDirty = false
        newerVersionAvailable = false
    }

    /// Seed the editor buffer from a tab's RAW Markdown, recording which resulting blocks
    /// are frozen islands. The RAW line drives the decision: we split with the SAME rule
    /// `fromMarkdown` uses (empty ⇒ `[""]`, else split on "\n") so `lines[i]` lines up with
    /// `doc.blocks[i]`, then mark every block whose source line is `"!>"` or begins `"!> "`.
    /// Tracking identity at seed time (not by re-inspecting live text) is deliberate — a
    /// user typing "!> " into an editable block must NOT freeze it.
    private func seedDoc(_ markdown: String) {
        doc = RichDoc.fromMarkdown(markdown)
        let lines = markdown.isEmpty ? [""] : markdown.components(separatedBy: "\n")
        frozenBlockIDs = Set(zip(lines, doc.blocks).compactMap { line, block in
            (line == "!>" || line.hasPrefix("!> ")) ? block.id : nil
        })
    }

    /// The current tab's Markdown, made island-safe for a per-tab save: any block the user
    /// authored that LOOKS like an island line (`"!>"` / `"!> …"`) but wasn't seeded as one
    /// is backslash-escaped, mirroring the server's `escapeLeadingMarker`, so user text can
    /// never fabricate an island the write splice would mis-align on. Genuinely frozen
    /// blocks pass through untouched (they ARE islands the server matches). Defensive: if a
    /// block's text somehow spans lines and the counts diverge, fall back to raw Markdown.
    private var tabMarkdownForSave: String {
        let markdown = doc.markdown
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count == doc.blocks.count else { return markdown }
        return zip(lines, doc.blocks).map { line, block -> String in
            if !frozenBlockIDs.contains(block.id), line == "!>" || line.hasPrefix("!> ") {
                return "\\" + line
            }
            return line
        }.joined(separator: "\n")
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
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
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
                .atlasFont(size: 13, weight: .semibold)
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
                .atlasFont(size: 13, weight: .semibold)
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

    /// One item in the render plan: an ordinary editable block (with its real index), a
    /// folded pipe-table grid, or a frozen island (display-only content the write splices
    /// around — a non-round-trip image or a positioned-image tether paragraph).
    private enum BlockSegment: Identifiable {
        case block(index: Int, block: RichDoc.Block)
        case table(id: UUID, lines: [String])
        case frozen(block: RichDoc.Block, display: String)

        var id: String {
            switch self {
            case let .block(_, block):  return "b-\(block.id.uuidString)"
            case let .table(id, _):     return "t-\(id.uuidString)"
            case let .frozen(block, _): return "f-\(block.id.uuidString)"
            }
        }
    }

    /// The block-level render plan, one walk for editable AND read-only tabs:
    ///   • A run of consecutive FROZEN blocks whose (marker-stripped) text starts with `|`
    ///     folds into one read-only table grid — the frozen-island form a table now takes
    ///     in a WRITABLE tab (the write splices around it).
    ///   • Legacy: in a read-only tab, UNMARKED consecutive pipe lines (old-format rows
    ///     still in the DB from before frozen islands) fold the same way.
    ///   • Any other frozen block is a `.frozen` island — display-only.
    ///   • Everything else is an editable `.block` carrying its REAL index into
    ///     `doc.blocks` (indices must stay exact for `textBinding(for:)`).
    private var renderSegments: [BlockSegment] {
        let blocks = doc.blocks
        var segments: [BlockSegment] = []
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            if frozenBlockIDs.contains(block.id) {
                let display = strippedIslandText(block.text)
                if display.hasPrefix("|") {
                    // Consecutive frozen pipe lines are one table island: strip each
                    // marker so the grid renders identically to the read-only path.
                    let startID = block.id
                    var lines: [String] = []
                    while i < blocks.count, frozenBlockIDs.contains(blocks[i].id),
                          strippedIslandText(blocks[i].text).hasPrefix("|") {
                        lines.append(strippedIslandText(blocks[i].text))
                        i += 1
                    }
                    segments.append(.table(id: startID, lines: lines))
                } else {
                    segments.append(.frozen(block: block, display: display))
                    i += 1
                }
            } else if tabReadOnly, isPipeLine(block.text) {
                let startID = block.id
                var lines: [String] = []
                while i < blocks.count, !frozenBlockIDs.contains(blocks[i].id),
                      isPipeLine(blocks[i].text) {
                    lines.append(blocks[i].text)
                    i += 1
                }
                segments.append(.table(id: startID, lines: lines))
            } else {
                segments.append(.block(index: i, block: block))
                i += 1
            }
        }
        return segments
    }

    private func isPipeLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    /// A frozen-island line's text with its `!> ` marker stripped (bare `!>` ⇒ ""). Non-
    /// island text is returned unchanged — callers only pass frozen blocks.
    private func strippedIslandText(_ text: String) -> String {
        if text == "!>" { return "" }
        if text.hasPrefix("!> ") { return String(text.dropFirst(3)) }
        return text
    }

    @ViewBuilder
    private func blockRow(index: Int, block: RichDoc.Block) -> some View {
        // An `![image:<id>]` block renders as the actual re-hosted image (both editable
        // and read-only tabs). The block stays in `doc.blocks`, so deleting it removes
        // the image on save — intentional.
        if let objectId = imagePlaceholderObjectId(block.text) {
            imageBlock(objectId: objectId, placeholder: block.text)
        } else if (tabReadOnly || focusedBlock != block.id),
                  let detected = detectLinks(in: block.text) {
            // Display-tier link rendering: a NON-focused block (or any block in a
            // read-only tab) with links shows styled, clickable text instead of the raw
            // `[text](url)`. Focusing the row (tap) swaps back to the TextField showing
            // the raw markdown — editable tabs only; read-only tabs stay styled. The
            // underlying block text is never changed (round-trip-safe).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if block.kind.isList {
                    Text(listGlyph(for: index, block: block))
                        .atlasFont(size: 14, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(minWidth: 18, alignment: .trailing)
                }
                LinkableBlockText(
                    attributed: detected.attributed,
                    links: detected.links,
                    font: font(for: block.kind),
                    bold: block.uniformMarks.contains(.bold),
                    italic: block.uniformMarks.contains(.italic),
                    underline: block.uniformMarks.contains(.underline),
                    onActivate: { focusedBlock = block.id },
                    docDeepLink: docDeepLinkURL
                )
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if block.kind.isList {
                    Text(listGlyph(for: index, block: block))
                        .atlasFont(size: 14, weight: .medium)
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
                    .disabled(tabReadOnly || syncPending)
            }
        }
    }

    /// The re-hosted image for an `![image:<objectId>]` placeholder, or the literal
    /// placeholder text when no image row exists (older pull, or the fetch never landed).
    @ViewBuilder
    private func imageBlock(objectId: String, placeholder: String) -> some View {
        if let image = docImages.first(where: { $0.objectId == objectId }) {
            DocImageBlockView(image: image,
                              download: { try await state.downloadDocImage(path: $0) },
                              placeholder: placeholder)
        } else {
            Text(placeholder)
                .atlasFont(size: 13)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// A frozen island: display-only content the write splices around, so it can only be
    /// changed in Google Docs. Never focusable/editable — no TextField, no onActivate. An
    /// `![image:id]` island reuses `imageBlock` so a frozen image looks identical to a
    /// writable one; anything else is static styled text sized to blend in with an
    /// editable normal block.
    @ViewBuilder
    private func frozenRow(display: String) -> some View {
        if let objectId = imagePlaceholderObjectId(display) {
            imageBlock(objectId: objectId, placeholder: display)
                .help("Locked — this content can only be changed in Google Docs")
        } else {
            Text(display)
                .atlasFont(size: 13)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Locked — this content can only be changed in Google Docs")
        }
    }

    /// The object id in an `![image:<id>]` line (trimmed), else nil. Mirrors the
    /// edge function's `^!\[image:([^\]]+)\]$` placeholder grammar.
    private func imagePlaceholderObjectId(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let prefix = "![image:"
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("]") else { return nil }
        let id = trimmed.dropFirst(prefix.count).dropLast()
        return id.isEmpty || id.contains("]") ? nil : String(id)
    }

    /// Wrapper so `blockRow` reads cleanly; the parsing itself is the file-scope
    /// `detectMarkdownLinks` (kept free of `self` so it stays trivially testable).
    private func detectLinks(in raw: String) -> (attributed: AttributedString, links: [DetectedLink])? {
        detectMarkdownLinks(in: raw)
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
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
            Button { addBlockAfter(doc.blocks.count - 1) } label: {
                Label("Block", systemImage: "plus")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(tabReadOnly || syncPending)
            Button(action: commit) {
                Text("Done")
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
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
        case .heading:    return .system(size: 24 * textScale, weight: .bold, design: .rounded)
        case .subheading: return .system(size: 19 * textScale, weight: .semibold, design: .rounded)
        case .normal, .bulleted, .numbered: return .system(size: 14 * textScale, weight: .regular, design: .rounded)
        }
    }

    /// Close whichever host is presenting us — the corner card (`onDismiss`) or a
    /// sheet (`dismiss`). Exclusive on purpose: calling `dismiss` with no active
    /// presentation walks SwiftUI's fallback chain and closes the whole WINDOW.
    private func closeHost() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    private func commit() {
        // Pending first-sync: editing was locked, so there's nothing to push — just close.
        if syncPending { closeHost(); return }
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
            // Per-tab writes go out island-safe (escape user-faked markers); the legacy
            // whole-file path (activeTabId == nil) keeps the plain Markdown.
            let outgoing = activeTabId != nil ? tabMarkdownForSave : doc.markdown
            switch try await service.writeBack(reference: ref, markdown: outgoing, tabId: activeTabId, overwrite: overwrite) {
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
            case .notSynced:
                // Server belt: the note's first pull hasn't landed. The editor locks pending
                // notes, but a race (pending cleared between load and save) can still reach
                // here — surface the notice, stay open.
                showNotSyncedNotice = true
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

// MARK: - Link detection (display-tier)

/// A single hyperlink found in a block's raw text: the resolved `URL` plus the text
/// shown for it (the markdown label, or the URL itself for a bare link).
struct DetectedLink: Identifiable {
    let id = UUID()
    let url: URL
    let displayText: String
}

/// Scans `raw` for markdown `[text](url)` spans and bare `http(s)://…` URLs, producing
/// a styled `AttributedString` — link spans get the `.link` attribute (so a tap opens
/// the browser via `openURL`), accent color, and an underline; the `[…](…)` syntax
/// collapses to just its label — plus the ordered links for the context menu. Returns
/// `nil` when the text has no usable links (the caller then keeps the plain TextField).
/// Display-tier only: the block's underlying text is never modified.
func detectMarkdownLinks(in raw: String) -> (attributed: AttributedString, links: [DetectedLink])? {
    let pattern = #"\[([^\]]+)\]\(([^)\s]+)\)|(https?://[^\s]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return nil }

    var attributed = AttributedString()
    var links: [DetectedLink] = []
    var cursor = 0
    let trailingPunct = Set(".,;:!?)]}".unicodeScalars)

    for match in matches {
        if match.range.location > cursor {
            attributed += AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
        }
        cursor = match.range.location + match.range.length

        var displayText: String
        var urlString: String
        var trailing = ""
        if match.range(at: 1).location != NSNotFound {            // markdown form
            displayText = ns.substring(with: match.range(at: 1))
            urlString = ns.substring(with: match.range(at: 2))
        } else {                                                  // bare URL
            urlString = ns.substring(with: match.range(at: 3))
            // A bare URL commonly absorbs sentence punctuation ("see https://x.com.");
            // trim it off the link and re-emit it as plain text after the span.
            while let last = urlString.unicodeScalars.last, trailingPunct.contains(last) {
                urlString.unicodeScalars.removeLast()
            }
            trailing = String(ns.substring(with: match.range).dropFirst(urlString.count))
            displayText = urlString
        }

        if let url = URL(string: urlString), url.scheme != nil {
            var span = AttributedString(displayText)
            span.link = url
            span.foregroundColor = AtlasTheme.Colors.accentText
            span.underlineStyle = .single
            attributed += span
            links.append(DetectedLink(url: url, displayText: displayText))
            if !trailing.isEmpty { attributed += AttributedString(trailing) }
        } else {
            // Not a usable URL — emit the literal match unchanged.
            attributed += AttributedString(ns.substring(with: match.range))
        }
    }
    if cursor < ns.length {
        attributed += AttributedString(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
    }
    return links.isEmpty ? nil : (attributed, links)
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
    /// Write refused: the note's first pull hasn't landed yet (`sync_state == pending`),
    /// so there's no content/baseline to write against — retry once it syncs.
    case notSynced
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

private struct ReferencePullKey: EnvironmentKey {
    static let defaultValue: ReferencePullClient? = nil
}

extension EnvironmentValues {
    var referencePull: ReferencePullClient? {
        get { self[ReferencePullKey.self] }
        set { self[ReferencePullKey.self] = newValue }
    }
}
