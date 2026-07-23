import SwiftUI
import AtlasCore
import AppKit
import EventKit
import TipKit

/// Full-page Settings route (General / Integrations / Metrics). Opened by the sidebar gear.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    /// Multi-feed connect client (`calendar_feeds`) — Canvas + generic ICS feeds.
    @EnvironmentObject private var feeds: FeedService
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var googleAuth: GoogleAuthService

    /// Space new / quick-captured tasks fall into when none is inferred.
    @AppStorage("tasks.defaultSpaceName") private var defaultTaskSpace: String = "Personal"

    /// Arc-style sidebar behavior — "always" pins it; "hover" hides it until the
    /// cursor touches the left edge (RootView owns the overlay mechanics).
    @AppStorage("sidebar.mode") private var sidebarMode: String = "always"

    /// Beta flag: multi-tab Google Docs edit tab-by-tab (the editor reads this key).
    @AppStorage("notes.perTabDocsSync.enabled") private var perTabSyncEnabled = false

    /// User-adjustable global text scale — same AppStorage key AtlasApp injects into the environment.
    @AppStorage("appearance.textScale") private var textScale: Double = 1.0

    // MARK: – Canvas server-sync state
    @State private var canvasFeedURL = ""
    @State private var canvasSpaceName = "School"
    @State private var canvasWorking = false
    @State private var canvasError: String? = nil
    // (Canvas destination-space is now edited inline on its connected feed row.)

    // MARK: – Generic ICS feed connect state
    @State private var icsName = ""
    @State private var icsURL = ""
    @State private var icsSpaceName = ""
    @State private var icsWorking = false
    @State private var icsError: String? = nil
    /// The feed currently being re-spaced / disconnected (its row shows a spinner), plus
    /// a shared per-row error.
    @State private var feedRowWorking: UUID? = nil
    @State private var feedRowError: String? = nil

    // MARK: – Shortcut recorder state
    @State private var recordingAction: ShortcutAction? = nil
    @State private var conflictWarning: String? = nil
    @State private var recordMonitor: Any? = nil

    // MARK: – Calendar sync state
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    // Atlas→Apple mirror. DEVICE-LOCAL (never synced — EventKit ids are per-device), so
    // these keys are intentionally NOT wired into `pushSyncedSettings()`.
    @AppStorage("calendar.apple.writeback") private var appleWritebackEnabled: Bool = false
    @AppStorage("calendar.apple.writeback.calendarId") private var appleWritebackCalendarId: String = ""
    @State private var appleWritableCalendars: [(id: String, title: String)] = []
    @State private var appleAccessGranted: Bool = false
    @State private var appleAccessChecked: Bool = false

    // MARK: – Google multi-account (CALENDARS) state
    /// A connect/PATCH/DELETE is in flight — disables the Add button + detail actions.
    @State private var googleWorking = false
    @State private var googleError: String? = nil
    /// The connection whose detail sheet (rename / reconnect / disconnect) is open.
    @State private var detailConnection: GoogleConnection? = nil
    @State private var detailRename = ""
    /// The open connection's calendars (per-calendar selection, 0036), loaded when the
    /// detail sheet appears. `detailCalendarsLoading` gates the initial spinner.
    @State private var detailCalendars: [GoogleConnectionCalendar] = []
    @State private var detailCalendarsLoading = false
    /// The "name it + pick a space" sheet after a successful Add-account OAuth.
    @State private var showAddGoogleSheet = false
    @State private var pendingGrant: GoogleAuthService.GrantedAccount? = nil
    @State private var newAccountName = ""
    @State private var newAccountSpace = ""

    // MARK: – Notes & Docs (dedicated Drive/Docs Google login)
    /// The singleton `google_docs_connections` row, nil ⇒ no explicit Docs login.
    @State private var docsConnection: AtlasDB.GoogleDocsConnection? = nil
    @State private var docsWorking = false
    @State private var docsError: String? = nil

    // MARK: – Delete-account state
    @State private var showDeleteAccountConfirm = false
    @State private var deletingAccount = false
    @State private var deleteAccountError: String? = nil

    // MARK: – Profile name (nickname → dashboard greeting; profiles.display_name)
    @State private var nicknameField = ""
    @State private var nicknameSeeded = false

    private let ekService = EventKitService()

    // MARK: - Onboarding tips
    @State private var connectTip = AtlasTips.ConnectSource()
    @State private var perCalTip = AtlasTips.PerCalendarPicker()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").atlasFont(size: 26, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button { state.presentGraph = true } label: {
                    BrandLogo(size: 18).opacity(0.85)
                }
                .buttonStyle(.plain)
                .help("Open relationship graph")
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            AtlasSegmentedPicker(
                options: SettingsSection.allCases,
                label: { $0.title },
                selection: $state.settingsSection
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 14)

            Divider().overlay(AtlasTheme.Colors.border)

            sectionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { refreshAppleAccessStatus() }
        .onDisappear { stopRecording(); commitNickname() }
        // Push each synced preference (debounced) when the user changes it. Only
        // user-initiated changes push — never launch — so a fresh device can't
        // clobber the server. (sidebar.mode is pushed from RootView, which observes
        // the same key, so it isn't repeated here.)
        .onChange(of: defaultTaskSpace)      { _, _ in state.pushSyncedSettings() }
        .onChange(of: appleDefaultSpace)     { _, _ in state.pushSyncedSettings() }
        .onChange(of: textScale)             { _, _ in state.pushSyncedSettings() }
        .onChange(of: perTabSyncEnabled)     { _, _ in state.pushSyncedSettings() }
    }

    /// Body for the selected settings section. Metrics renders the full `MetricsView`
    /// (which has its own ScrollView); the others share a scrolling settings stack.
    @ViewBuilder
    private var sectionContent: some View {
        switch state.settingsSection {
        case .general:
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    account
                    Divider().overlay(AtlasTheme.Colors.border)
                    appearanceSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    tasksSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    sidebarSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    shortcutsSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    helpSection
                    Spacer(minLength: 8)
                }
                .padding(28)
            }
        case .integrations:
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    integrations
                    Divider().overlay(AtlasTheme.Colors.border)
                    calendarFeedsSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    calendarsSection
                    Spacer(minLength: 8)
                }
                .padding(28)
            }
        case .history:
            CaptureHistorySection()
        case .metrics:
            MetricsView()
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("ACCOUNT")
            HStack(spacing: 12) {
                Circle().fill(AtlasTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(AtlasTheme.Colors.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(identityTitle).atlasFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(identitySubtitle).atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                if case .offline = auth.state {
                    Button("Sign in") { auth.signOut() } // returns to gate
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.accentText)
                } else {
                    Button("Sign out") {
                        // Clear the settings-sync cache + synced keys AND every Google
                        // credential (singleton + per-connection keychain slots) so a next
                        // sign-in on a shared device starts clean — no cross-account leak.
                        state.settingsSync.reset()
                        googleAuth.disconnect()
                        auth.signOut()
                    }
                    .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.danger)
                }
            }
            // Editable first name / nickname — feeds the dashboard greeting. Persists
            // to profiles.display_name (server-synced). Seeded once from the profile;
            // saved on submit and when Settings closes if changed.
            if auth.state != .offline {
                VStack(alignment: .leading, spacing: 6) {
                    label("YOUR NAME")
                    input("First name or nickname", text: $nicknameField)
                        .frame(maxWidth: 280)
                        .onSubmit { commitNickname() }
                    Text("Used to greet you on the dashboard. Leave blank for a plain greeting.")
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .onAppear {
                    if !nicknameSeeded { nicknameField = state.nickname; nicknameSeeded = true }
                }
            }

            if auth.state != .offline {
                HStack(spacing: 10) {
                    Button { showDeleteAccountConfirm = true } label: {
                        Text(deletingAccount ? "Deleting account…" : "Delete account…")
                            .font(.system(size: 12, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .disabled(deletingAccount)
                    if let err = deleteAccountError {
                        Text(err).font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.danger)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete your Atlas account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) { performDeleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases your account and all your Atlas data — spaces, projects, tasks, events and notes. This can't be undone.")
        }
    }

    /// Fires the `delete-account` edge function, then either drops to the sign-in
    /// gate (success) or surfaces an inline error (failure).
    private func performDeleteAccount() {
        deleteAccountError = nil
        deletingAccount = true
        Task { @MainActor in
            let error = await auth.deleteAccount()
            deletingAccount = false
            deleteAccountError = error
            if error == nil {
                state.settingsSync.reset()   // same clean-slate as sign-out
                googleAuth.disconnect()      // clear all Google keychain credentials
            }
        }
    }

    // MARK: – Calendar feeds (Canvas + generic ICS — server-side sync)

    /// Subscribed calendar feeds live in `calendar_feeds` and sync server-side (migration
    /// 0012+ · `feeds-connect` + the feed cron): each feed's capability URL is Vaulted once,
    /// then assignments/events flow in with every Atlas client closed. Canvas is offered as
    /// the suggested first-class feed; any other calendar joins by its ICS link. Connected
    /// feeds read back from `state.calendarFeeds` (refreshed on appear + after each action).
    private var calendarFeedsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                label("CALENDAR FEEDS")
                Text("Import assignments and events on a server schedule — no need to keep Atlas open. These calendars are read-only in Atlas.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }

            // ── Canvas — the suggested first-class feed ──────────────────
            if !hasActiveCanvasFeed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .foregroundStyle(AtlasTheme.Colors.school)
                        Text("Canvas")
                            .atlasFont(size: 14, weight: .semibold, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    }
                    canvasConnectForm(repaste: canvasFeedRow?.status == "revoked")
                }
            }

            // ── Add any calendar by ICS link ─────────────────────────────
            icsConnectForm

            // ── Connected feeds (Canvas + ICS) ───────────────────────────
            if !connectedFeeds.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CONNECTED")
                        .atlasMono(size: 10, weight: .semibold).tracking(1.2)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                    ForEach(connectedFeeds) { feed in
                        feedRow(feed)
                    }
                    if let err = feedRowError {
                        errorRow(err).padding(.horizontal, 12)
                    }
                }
            }
        }
        .task { await state.refreshCalendarFeeds() }
    }

    /// The `calendar_feeds` row for the user's Canvas feed (any status), if any.
    private var canvasFeedRow: CalendarFeedRow? {
        state.calendarFeeds.first { $0.feedType == "canvas" }
    }
    /// A non-revoked Canvas feed exists — hides the Canvas connect card (it lists below).
    private var hasActiveCanvasFeed: Bool {
        state.calendarFeeds.contains { $0.feedType == "canvas" && $0.isServerOwned }
    }
    /// Feeds to list under "Connected" — every non-revoked feed (Canvas + ICS).
    private var connectedFeeds: [CalendarFeedRow] {
        state.calendarFeeds.filter { $0.isServerOwned }
    }

    /// "Add calendar (ICS link)" — display name + ICS URL + destination space, reusing the
    /// Canvas connect card's visual template. Connects a generic `ics`-type feed.
    @ViewBuilder
    private var icsConnectForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Text("Add calendar (ICS link)")
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }

            input("Calendar name (e.g. Schoology)", text: $icsName)
            input("https://…/calendar.ics", text: $icsURL)

            if !state.spaces.isEmpty {
                HStack {
                    Text("Items land in")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Spacer()
                    Picker("ICS space", selection: $icsSpaceName) {
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                    .onAppear {
                        if !state.spaces.contains(where: { $0.name == icsSpaceName }) {
                            icsSpaceName = state.spaces.first?.name ?? ""
                        }
                    }
                }
            }

            if let err = icsError {
                Text(err).atlasFont(size: 12, design: .rounded).foregroundStyle(AtlasTheme.Colors.danger)
            }

            Button { connectICS() } label: {
                Text(icsWorking ? "Adding…" : "Add calendar")
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                    )
            }
            .buttonStyle(.plain)
            .disabled(icsWorking)

            Text("Add any calendar by link. Most apps can share one as a private ‘ICS’ or ‘iCal’ link (it usually ends in .ics). In Schoology: Calendar → iCal/Calendar Feed. Paste the link and pick which space its items land in — Atlas checks it for updates automatically. These calendars are read-only in Atlas.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// One connected feed (Canvas or ICS): icon + name + type badge, a status line
    /// (last-synced / error), an inline destination-space picker (PATCH) and Disconnect
    /// (DELETE). Mirrors the Google / Canvas connected-row idioms.
    @ViewBuilder
    private func feedRow(_ feed: CalendarFeedRow) -> some View {
        let isCanvas = feed.feedType == "canvas"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: isCanvas ? "graduationcap.fill" : "calendar")
                    .foregroundStyle(isCanvas ? AtlasTheme.Colors.school : AtlasTheme.Colors.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(feed.displayName)
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(isCanvas ? "CANVAS" : "ICS")
                            .atlasMono(size: 9, weight: .semibold).tracking(1)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                    }
                    Text(feedStatusSubtitle(feed))
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(feedStatusColor(feed))
                }
                Spacer()
                if feedRowWorking == feed.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Disconnect") { disconnectFeed(feed) }
                        .buttonStyle(.plain)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.danger)
                }
            }

            if !state.spaces.isEmpty {
                HStack {
                    Text("Items land in")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Spacer()
                    Picker("Feed space", selection: Binding(
                        get: { feed.spaceName ?? "" },
                        set: { updateFeedSpace(feed, to: $0) }
                    )) {
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                    .disabled(feedRowWorking == feed.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .atlasHairlineBelow()
    }

    private func feedStatusSubtitle(_ feed: CalendarFeedRow) -> String {
        if feed.status == "error" {
            return feed.lastError ?? "Sync paused — Atlas will retry automatically."
        }
        if let synced = feed.lastSyncedDate {
            return "Last synced \(Self.relativeSync(from: synced))."
        }
        return "Connected — first sync runs shortly."
    }

    private func feedStatusColor(_ feed: CalendarFeedRow) -> Color {
        feed.status == "error" ? AtlasTheme.Colors.warning : AtlasTheme.Colors.green
    }

    @ViewBuilder
    private func canvasConnectForm(repaste: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if repaste {
                Text("Your Canvas feed link expired — paste a fresh one to resume.")
                    .atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.warning)
            }

            input("https://school.instructure.com/feeds/calendars/…ics", text: $canvasFeedURL)

            if !state.spaces.isEmpty {
                HStack {
                    Text("Items land in")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Spacer()
                    Picker("Canvas space", selection: $canvasSpaceName) {
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                    .onAppear {
                        // Seed to "School" (spec default) if present, else the first space.
                        if !state.spaces.contains(where: { $0.name == canvasSpaceName }) {
                            canvasSpaceName = state.spaces.contains(where: { $0.name == "School" })
                                ? "School"
                                : (state.spaces.first?.name ?? "School")
                        }
                    }
                }
            }

            if let err = canvasError {
                Text(err).atlasFont(size: 12, design: .rounded).foregroundStyle(AtlasTheme.Colors.danger)
            }

            Button { connectCanvas() } label: {
                Text(canvasWorking ? "Connecting…" : "Connect Canvas")
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                    )
            }
            .buttonStyle(.plain)
            .disabled(canvasWorking)

            Text("Canvas → Calendar → Calendar Feed (copy the .ics link)")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    /// Connects Canvas as a `canvas`-type feed (`feeds-connect`), preserving the paste-feed
    /// UX. The server keeps Canvas's assignment→task + course routing for canvas-type feeds.
    private func connectCanvas() {
        let feed = canvasFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AtlasCore.CanvasService.isValidFeedURL(feed) else {
            canvasError = "That doesn't look like a Canvas feed link. Copy it from Canvas → Calendar → Calendar Feed."
            return
        }
        guard let jwt = auth.session?.accessToken else {
            canvasError = "Sign in to Atlas to connect Canvas."
            return
        }
        canvasError = nil
        canvasWorking = true
        Task {
            do {
                try await feeds.connect(feedUrl: feed, feedType: "canvas",
                                        displayName: "Canvas", spaceName: canvasSpaceName, jwt: jwt)
                await state.refreshCalendarFeeds()
                await AtlasTipEvents.connectedSource.donate()
                AtlasTips.ConnectSource.hasConnection = true
                canvasFeedURL = ""   // don't retain the capability URL in the field
            } catch {
                canvasError = "Couldn't connect Canvas. Check the link and your connection, then try again."
            }
            canvasWorking = false
        }
    }

    /// Connects a generic ICS calendar as an `ics`-type feed (`feeds-connect`). Read-only
    /// events only — no task/course routing.
    private func connectICS() {
        let name = icsName.trimmingCharacters(in: .whitespaces)
        let url = icsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            icsError = "Give this calendar a name so you can tell it apart."
            return
        }
        guard FeedService.isValidICSURL(url) else {
            icsError = "That doesn't look like a calendar link. It should start with https and usually ends in .ics."
            return
        }
        guard let jwt = auth.session?.accessToken else {
            icsError = "Sign in to Atlas to add a calendar."
            return
        }
        icsError = nil
        icsWorking = true
        Task {
            do {
                try await feeds.connect(feedUrl: url, feedType: "ics",
                                        displayName: name, spaceName: icsSpaceName, jwt: jwt)
                await state.refreshCalendarFeeds()
                await AtlasTipEvents.connectedSource.donate()
                AtlasTips.ConnectSource.hasConnection = true
                icsName = ""; icsURL = ""   // don't retain the capability URL
            } catch {
                icsError = "Couldn't add that calendar. Check the link and your connection, then try again."
            }
            icsWorking = false
        }
    }

    /// Re-routes a feed's unmatched items to a new space (PATCH `feeds-connect`). No-ops when
    /// the space is unchanged or empty. Refreshes on success.
    private func updateFeedSpace(_ feed: CalendarFeedRow, to newName: String) {
        guard newName != (feed.spaceName ?? ""), !newName.isEmpty else { return }
        guard let jwt = auth.session?.accessToken else {
            feedRowError = "Sign in to Atlas to change where this calendar lands."
            return
        }
        feedRowError = nil
        feedRowWorking = feed.id
        Task {
            do {
                try await feeds.updateFeed(id: feed.id, spaceName: newName, jwt: jwt)
                await state.refreshCalendarFeeds()
            } catch {
                feedRowError = "Couldn't change the space. Check your connection and try again."
            }
            feedRowWorking = nil
        }
    }

    /// Disconnects a feed (DELETE `feeds-connect`) → revoked server-side, dropped locally.
    private func disconnectFeed(_ feed: CalendarFeedRow) {
        guard let jwt = auth.session?.accessToken else {
            feedRowError = "Sign in to Atlas to disconnect this calendar."
            return
        }
        feedRowError = nil
        feedRowWorking = feed.id
        Task {
            do {
                try await feeds.disconnect(id: feed.id, jwt: jwt)
                await state.refreshCalendarFeeds()
            } catch {
                feedRowError = "Couldn't disconnect. Check your connection and try again."
            }
            feedRowWorking = nil
        }
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("INTEGRATIONS")
            row(icon: "calendar", tint: AtlasTheme.Colors.school, title: "Google Calendar / Drive",
                subtitle: "Manage accounts in Calendars; Drive & Docs in Notes & Docs")
            googleConnectionBadge
            row(icon: "applelogo", tint: AtlasTheme.Colors.textSecondary, title: "Sign in with Apple",
                subtitle: "Enable signing in Xcode to use on device")

            // ── Notes & Docs (dedicated Drive/Docs login, one at a time) ─
            notesDocsRow

            // ── Per-tab Google Doc sync (beta) ──────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per-tab Google Doc sync (beta)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Multi-tab Docs edit tab-by-tab; tabs with tables stay read-only.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Toggle("", isOn: $perTabSyncEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()
        }
        .task {
            await loadDocsConnection()
        }
    }

    // MARK: – Notes & Docs row

    /// The dedicated Drive/Docs Google login — powers Notes ↔ Google Docs background work
    /// (import / re-sync / write-back), independent of the calendar connections and ONE at a
    /// time. Not connected → sign in; connected → email + status + Disconnect. When no Docs
    /// login exists but calendar accounts do, a muted hint names the fallback account.
    @ViewBuilder
    private var notesDocsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundStyle(AtlasTheme.Colors.school)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes & Docs")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    if let docs = docsConnection {
                        Text(docs.googleEmail)
                            .atlasFont(size: 12, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                        Text(docs.status == "active"
                             ? "Connected — Drive & Docs use this account"
                             : (docs.lastError ?? "Reconnect needed — Drive/Docs sync is stopped"))
                            .atlasFont(size: 12, design: .rounded)
                            .foregroundStyle(docs.status == "active"
                                             ? AtlasTheme.Colors.green
                                             : AtlasTheme.Colors.warning)
                    } else {
                        Text("Sign in to choose the Google account for Drive & Docs")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }
                Spacer()
                if docsWorking {
                    ProgressView().controlSize(.small)
                } else if docsConnection != nil {
                    Button("Disconnect") { disconnectDocs() }
                        .buttonStyle(.plain)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.danger)
                } else {
                    Button("Sign in with Google") { connectDocs() }
                        .buttonStyle(.plain)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
            }

            // Fallback hint: no explicit Docs login, but calendar accounts exist —
            // the server uses the oldest one until the user picks explicitly.
            if docsConnection == nil, let fallback = state.googleConnections.first {
                Text("Using \(fallback.googleEmail) (calendar account) — sign in to choose explicitly")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.leading, 34)
            }

            if let err = docsError {
                Text(err).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .atlasHairlineBelow()
    }

    /// Reads the singleton `google_docs_connections` row. Best-effort: a nil db
    /// (offline/mock) or an undeployed table leaves the row as "not connected".
    private func loadDocsConnection() async {
        docsConnection = try? await state.db?.loadGoogleDocsConnection()
    }

    /// Runs the account-chooser OAuth, then POSTs google-connect `{docs: true}` to set
    /// (or replace) the dedicated Drive/Docs login.
    private func connectDocs() {
        docsError = nil
        docsWorking = true
        Task {
            let grant = await googleAuth.connect()
            guard let grant else {
                docsError = googleAuth.errorMessage ?? "Couldn't connect Google. Try again."
                docsWorking = false
                return
            }
            guard let jwt = await auth.validAccessToken() else {
                docsError = "Your session expired — sign in again, then try."
                docsWorking = false
                return
            }
            do {
                try await googleAuth.connectDocs(refreshToken: grant.refreshToken,
                                                 googleEmail: grant.email, jwt: jwt)
                await loadDocsConnection()
            } catch {
                docsError = "Couldn't connect Notes & Docs. Try again."
            }
            docsWorking = false
        }
    }

    /// DELETE google-connect `{docs: true}` — drops the dedicated Drive/Docs login.
    private func disconnectDocs() {
        docsError = nil
        docsWorking = true
        Task {
            guard let jwt = await auth.validAccessToken() else {
                docsError = "Your session expired — sign in again, then try."
                docsWorking = false
                return
            }
            do {
                try await googleAuth.disconnectDocs(jwt: jwt)
                docsConnection = nil
            } catch {
                docsError = "Couldn't disconnect Notes & Docs. Try again."
            }
            docsWorking = false
        }
    }

    /// Aggregate Google connection status, aligned under the Google row. Derived from
    /// all of the user's `google_connections` (multi-account): no connection ⇒ "Not
    /// connected"; any non-active (revoked/error) ⇒ reconnect warning; else "Connected".
    @ViewBuilder
    private var googleConnectionBadge: some View {
        Group {
            if state.googleConnections.isEmpty {
                Text("Not connected").foregroundStyle(AtlasTheme.Colors.textMuted)
            } else if state.googleConnections.contains(where: { $0.status != "active" }) {
                Text("⚠ Reconnect needed — sync is stopped")
                    .foregroundStyle(AtlasTheme.Colors.warning)
            } else {
                Text("Connected").foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
        .font(.system(size: 11, design: .rounded))
        .padding(.leading, 34)
    }

    // MARK: – Calendars section

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CALENDARS")
            Text("Everything reads in. An event syncs to the Google account its space is linked to; an unlinked space stays in Atlas.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            // ── Apple Calendar ───────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "applelogo")
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Calendar")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(appleCalendarSubtitle)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(appleCalendarSubtitleColor)
                }
                Spacer()
                Toggle("", isOn: $appleCalendarEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: appleCalendarEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await ekService.requestAccess()
                                await MainActor.run {
                                    appleAccessGranted = granted
                                    if !granted { appleCalendarEnabled = false }
                                }
                            }
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()

            // ── Google accounts (multi-account) — their own labeled cluster,
            //    with "Add Google account…" docked directly under the rows ──
            VStack(alignment: .leading, spacing: 0) {
                Text("GOOGLE")
                    .atlasMono(size: 10, weight: .semibold).tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                ForEach(state.googleConnections) { conn in
                    googleConnectionRow(conn)
                }
                Button { startAddGoogleAccount() } label: {
                    HStack(spacing: 8) {
                        if googleWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(AtlasTheme.Colors.school)
                        }
                        Text(googleWorking ? "Connecting…" : "Add Google account…")
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.accentText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(googleWorking)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .atlasHairlineBelow()
                .popoverTip(connectTip)

                if let err = googleError {
                    errorRow(err)
                        .padding(.horizontal, 12)
                }
            }

            // ── Canvas ──────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(AtlasTheme.Colors.school)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Canvas LMS")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Group {
                        if hasActiveCanvasFeed {
                            Text(canvasFeedRow?.status == "error"
                                 ? "Connected — sync paused, retrying"
                                 : "Connected — syncing in the cloud")
                                .foregroundStyle(canvasFeedRow?.status == "error"
                                                 ? AtlasTheme.Colors.warning
                                                 : AtlasTheme.Colors.green)
                        } else {
                            Text("Not connected — add your feed in Calendar Feeds")
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    .atlasFont(size: 12, design: .rounded)
                }
                Spacer()
                Image(systemName: "eye.fill")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .help("Read-only import")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()

            // ── Atlas Native ────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atlas (native)")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Always on")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AtlasTheme.Colors.green)
                    .atlasFont(size: 15, design: .rounded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()

            // ── Mirror Atlas events to Apple (device-local) ─────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mirror Atlas events to Apple")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(appleWritebackEnabled
                         ? "New Atlas events are copied into Apple Calendar on this Mac."
                         : "Off — Atlas events stay in Atlas. Applies to this Mac only.")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Toggle("", isOn: $appleWritebackEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
                    .disabled(!appleAccessGranted)
                    .onChange(of: appleWritebackEnabled) { _, on in
                        if on {
                            refreshAppleWritableCalendars()
                            state.backfillEventsToApple()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()

            // Destination calendar — only when the mirror is on and access is granted.
            if appleWritebackEnabled && !appleWritableCalendars.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mirror into calendar")
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Where mirrored Atlas events are created")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Spacer()
                    Picker("Mirror into calendar", selection: $appleWritebackCalendarId) {
                        ForEach(appleWritableCalendars, id: \.id) { cal in
                            Text(cal.title).tag(cal.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .atlasHairlineBelow()
            }

            // ── Default space mapping ──────────────────────────────────
            if !state.spaces.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default space for Apple events")
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Imported events land in this space")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Spacer()
                    Picker("Default space", selection: $appleDefaultSpace) {
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                    .onAppear {
                        // Seed default to first space if not yet set
                        if appleDefaultSpace.isEmpty, let first = state.spaces.first {
                            appleDefaultSpace = first.name
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .atlasHairlineBelow()
            }
        }
        .sheet(item: $detailConnection) { conn in
            googleDetailSheet(conn)
        }
        .sheet(isPresented: $showAddGoogleSheet) {
            addGoogleSheet
        }
    }

    // MARK: – Google connection row (multi-account)

    /// One connected Google account: name / muted email / status line, plus the inline
    /// destination-space dropdown (visual sibling of the Canvas connected row). The row
    /// itself opens the detail sheet (rename / reconnect / disconnect).
    @ViewBuilder
    private func googleConnectionRow(_ conn: GoogleConnection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(AtlasTheme.Colors.school)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conn.name)
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(conn.googleEmail)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Text(googleConnectionStatus(conn))
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(googleConnectionStatusColor(conn))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                detailRename = conn.name
                detailConnection = conn
            }

            // Destination space — inline, mirrors the Canvas connected row. Changing it
            // PATCHes google-connect (routes this account's events to the new space).
            if !state.spaces.isEmpty {
                HStack {
                    Text("Events land in")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Spacer()
                    Picker("Destination space", selection: Binding(
                        get: { spaceName(forSpaceId: conn.spaceId) },
                        set: { updateGoogleSpace(conn, toSpaceName: $0) }
                    )) {
                        Text("None (read-in only)").tag("")
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                    .tint(AtlasTheme.Colors.accent)
                    .disabled(googleWorking)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .atlasHairlineBelow()
    }

    /// Status line for a connection row: server-owned sync state, per connection.
    private func googleConnectionStatus(_ conn: GoogleConnection) -> String {
        switch conn.status {
        case "error", "revoked":
            return "⚠ Reconnect needed — sync is stopped"
        default:
            if conn.spaceId == nil { return "Connected — pick a space to sync events out" }
            if let synced = conn.lastSyncedDate {
                return "Connected — last synced \(Self.relativeSync(from: synced))"
            }
            return "Connected — first sync runs shortly"
        }
    }

    private func googleConnectionStatusColor(_ conn: GoogleConnection) -> Color {
        conn.status == "active" ? AtlasTheme.Colors.green : AtlasTheme.Colors.warning
    }

    /// The space NAME a connection is linked to (for the picker), or "" when unlinked.
    private func spaceName(forSpaceId id: UUID?) -> String {
        guard let id, let space = state.spaces.first(where: { $0.id == id }) else { return "" }
        return space.name
    }

    // MARK: – Google connection detail sheet

    @ViewBuilder
    private func googleDetailSheet(_ conn: GoogleConnection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(conn.name).atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button("Done") { detailConnection = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("NAME")
                input("School", text: $detailRename)
                Text(conn.googleEmail)
                    .atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }

            if conn.status != "active" {
                Text(conn.lastError ?? "This account's sync is stopped — reconnect to resume.")
                    .atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.warning)
            }

            calendarsPickerSection(conn)

            if let err = googleError {
                Text(err).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
            }

            HStack(spacing: 12) {
                Button(googleWorking ? "Working…" : "Reconnect") { reconnectGoogle(conn) }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .disabled(googleWorking)
                Spacer()
                Button("Disconnect") { disconnectGoogle(conn) }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .disabled(googleWorking)
            }

            Button("Save name") { renameGoogle(conn) }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .disabled(googleWorking || detailRename.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24)
        .frame(width: 380)
        .background(AtlasTheme.Colors.bgBase)
        .task(id: conn.id) { await loadDetailCalendars(conn.id) }
    }

    // MARK: – Calendar picker (per-calendar selection, 0036)

    /// True when the only calendar on record is the server's primary-only fallback: a
    /// single row whose id is the literal `"primary"`. A genuinely-enumerated primary
    /// carries the account's real calendar id (its email), never `"primary"`, so this
    /// uniquely identifies "enumeration didn't run" (pre-`calendar.readonly` grant).
    private var isPrimaryOnlyFallback: Bool {
        detailCalendars.count == 1 && detailCalendars.first?.calendarId == "primary"
    }

    /// The connection's calendars as a checkbox list — tap to opt a calendar in/out of
    /// sync. Primary is badged. Follows AtlasTheme (outline square glyphs, caps label,
    /// no accent fills). Hidden until at least one calendar is known.
    @ViewBuilder
    private func calendarsPickerSection(_ conn: GoogleConnection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CALENDARS")
                .popoverTip(perCalTip, arrowEdge: .top)
            if detailCalendarsLoading && detailCalendars.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading calendars…")
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            } else if isPrimaryOnlyFallback {
                // Enumeration never ran (older grant lacks calendar.readonly, or a fetch
                // error): the server recorded only the fallback `primary` row. Tell the
                // user their other calendars are listable after a reconnect, rather than
                // silently implying this account has just one calendar.
                Text("Reconnect to list your other calendars.")
                    .atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else if detailCalendars.isEmpty {
                Text("Only this account's primary calendar is available.")
                    .atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                Text("Choose which calendars sync into Atlas.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(detailCalendars) { cal in
                            Button { toggleCalendar(cal, conn: conn) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: cal.selected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(cal.selected
                                                         ? AtlasTheme.Colors.textPrimary
                                                         : AtlasTheme.Colors.textMuted)
                                    Text(cal.summary)
                                        .atlasFont(size: 13, design: .rounded)
                                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                        .lineLimit(1)
                                    if cal.isPrimary {
                                        Text("PRIMARY")
                                            .atlasMono(size: 9, weight: .semibold).tracking(1)
                                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .disabled(googleWorking)
                        }
                    }
                }
                .frame(maxHeight: 168)
            }
        }
    }

    // MARK: – Add-account sheet (name it + pick a space)

    @ViewBuilder
    private var addGoogleSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Name this Google account")
                .atlasFont(size: 18, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            if let email = pendingGrant?.email {
                Text(email).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("NAME")
                input("School", text: $newAccountName)
            }

            if !state.spaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("EVENTS LAND IN")
                    Picker("Destination space", selection: $newAccountSpace) {
                        Text("None (read-in only)").tag("")
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(AtlasTheme.Colors.accent)
                }
            }

            if let err = googleError {
                Text(err).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
            }

            HStack {
                Button("Cancel") { showAddGoogleSheet = false; pendingGrant = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button(googleWorking ? "Saving…" : "Save") { saveNewGoogleAccount() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .disabled(googleWorking || newAccountName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: – Google multi-account actions

    /// Runs the account-chooser OAuth, then opens the name+space sheet on success.
    private func startAddGoogleAccount() {
        googleError = nil
        googleWorking = true
        Task {
            let grant = await googleAuth.connect()
            googleWorking = false
            guard let grant else {
                googleError = googleAuth.errorMessage ?? "Couldn't connect Google. Try again."
                return
            }
            pendingGrant = grant
            newAccountName = ""
            newAccountSpace = state.spaces.contains(where: { $0.name == "School" }) ? "School" : ""
            showAddGoogleSheet = true
        }
    }

    /// POSTs google-connect with the granted token + chosen name/space → new connection.
    private func saveNewGoogleAccount() {
        guard let grant = pendingGrant else { return }
        let name = newAccountName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        googleError = nil
        googleWorking = true
        Task {
            guard let jwt = await auth.validAccessToken() else {
                googleError = "Your session expired — sign in again, then try."
                googleWorking = false
                return
            }
            do {
                try await googleAuth.createConnection(
                    refreshToken: grant.refreshToken,
                    name: name,
                    spaceId: state.spaceID(named: newAccountSpace),
                    googleEmail: grant.email,
                    jwt: jwt)
                await state.refreshGoogleConnections()
                await AtlasTipEvents.connectedSource.donate()
                AtlasTips.ConnectSource.hasConnection = true
                let email = grant.email
                showAddGoogleSheet = false
                pendingGrant = nil
                // Surface the calendar picker for the account just added — its detail
                // sheet loads the enumerated calendars. Deferred a beat so the add sheet
                // finishes dismissing before the detail sheet presents (same host view).
                if let created = state.googleConnections.first(where: { $0.googleEmail == email }) {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    detailRename = created.name
                    detailConnection = created
                }
            } catch {
                googleError = googleConnectMessage(error, fallback: "Couldn't add the account. Try again.")
            }
            googleWorking = false
        }
    }

    /// Reconnect in one action: re-run OAuth for this account, then re-POST google-connect
    /// (server treats a re-POST for the same account as a reconnect — vault + status reset).
    private func reconnectGoogle(_ conn: GoogleConnection) {
        googleError = nil
        googleWorking = true
        Task {
            let grant = await googleAuth.connect()
            guard let grant else {
                googleError = googleAuth.errorMessage ?? "Couldn't reconnect Google. Try again."
                googleWorking = false
                return
            }
            guard let jwt = await auth.validAccessToken() else {
                googleError = "Your session expired — sign in again, then try."
                googleWorking = false
                return
            }
            do {
                try await googleAuth.createConnection(
                    refreshToken: grant.refreshToken,
                    name: conn.name,
                    spaceId: conn.spaceId,
                    googleEmail: conn.googleEmail,
                    jwt: jwt)
                await state.refreshGoogleConnections()
                detailConnection = nil
            } catch {
                googleError = googleConnectMessage(error, fallback: "Couldn't reconnect. Try again.")
            }
            googleWorking = false
        }
    }

    /// Loads the open connection's calendars for the picker. Best-effort — an empty /
    /// failed load just leaves the "primary only" hint (the primary always syncs).
    private func loadDetailCalendars(_ connectionId: UUID) async {
        detailCalendarsLoading = true
        defer { detailCalendarsLoading = false }
        detailCalendars = (try? await state.db?.loadGoogleConnectionCalendars(connectionId: connectionId)) ?? []
    }

    /// Opt a calendar in/out of sync: PATCH google-connect with the FULL selected set,
    /// then reload. Optimistically flips the local row so the checkbox responds at once.
    private func toggleCalendar(_ cal: GoogleConnectionCalendar, conn: GoogleConnection) {
        perCalTip.invalidate(reason: .actionPerformed)
        googleError = nil
        googleWorking = true
        // Optimistic flip so the tap feels instant; reload reconciles with the server.
        if let i = detailCalendars.firstIndex(where: { $0.id == cal.id }) {
            detailCalendars[i].selected.toggle()
        }
        let selectedIds = detailCalendars.filter { $0.selected }.map { $0.calendarId }
        Task {
            guard let jwt = await auth.validAccessToken() else {
                googleError = "Your session expired — sign in again, then try."
                googleWorking = false
                await loadDetailCalendars(conn.id)
                return
            }
            do {
                try await googleAuth.updateCalendars(connectionId: conn.id, selectedCalendarIds: selectedIds, jwt: jwt)
            } catch {
                googleError = googleConnectMessage(error, fallback: "Couldn't update calendars. Try again.")
            }
            await loadDetailCalendars(conn.id)
            googleWorking = false
        }
    }

    /// PATCH the connection's name.
    private func renameGoogle(_ conn: GoogleConnection) {
        let name = detailRename.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != conn.name else { detailConnection = nil; return }
        patchGoogle(conn, name: name, spaceId: nil, thenDismissDetail: true)
    }

    /// Change (or clear) the connection's destination space. `""` unlinks (read-in only).
    private func updateGoogleSpace(_ conn: GoogleConnection, toSpaceName newName: String) {
        let newSpaceId = newName.isEmpty ? nil : state.spaceID(named: newName)
        guard newSpaceId != conn.spaceId else { return }
        patchGoogle(conn, name: nil, spaceId: .some(newSpaceId), thenDismissDetail: false)
    }

    /// Shared PATCH runner. `spaceId` is a double-optional: nil ⇒ don't touch the mapping;
    /// `.some(nil)` ⇒ unlink; `.some(id)` ⇒ re-map. Refreshes on success.
    private func patchGoogle(_ conn: GoogleConnection, name: String?, spaceId: UUID??, thenDismissDetail: Bool) {
        googleError = nil
        googleWorking = true
        Task {
            guard let jwt = await auth.validAccessToken() else {
                googleError = "Your session expired — sign in again, then try."
                googleWorking = false
                return
            }
            do {
                try await googleAuth.updateConnection(connectionId: conn.id, name: name, spaceId: spaceId, jwt: jwt)
                await state.refreshGoogleConnections()
                if thenDismissDetail { detailConnection = nil }
            } catch {
                googleError = googleConnectMessage(error, fallback: "Couldn't update the account. Try again.")
            }
            googleWorking = false
        }
    }

    /// DELETE the connection + its vault secret.
    private func disconnectGoogle(_ conn: GoogleConnection) {
        googleError = nil
        googleWorking = true
        Task {
            guard let jwt = await auth.validAccessToken() else {
                googleError = "Your session expired — sign in again, then try."
                googleWorking = false
                return
            }
            do {
                try await googleAuth.deleteConnection(connectionId: conn.id, jwt: jwt)
                await state.refreshGoogleConnections()
                detailConnection = nil
            } catch {
                googleError = googleConnectMessage(error, fallback: "Couldn't disconnect. Try again.")
            }
            googleWorking = false
        }
    }

    /// Surfaces the one server message users must see verbatim — an occupied destination
    /// space (409). Everything else collapses to a calm fallback.
    private func googleConnectMessage(_ error: Error, fallback: String) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        if detail.contains("409") || detail.lowercased().contains("already linked") || detail.lowercased().contains("space") && detail.contains("unique") {
            return "That space is already linked to another Google account."
        }
        return fallback
    }

    /// Short relative label for "Last synced Xm ago".
    private static func relativeSync(from date: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }

    // MARK: – Calendar helpers

    private func refreshAppleAccessStatus() {
        let status = ekService.authorizationStatus()
        appleAccessGranted = (status == .fullAccess)
        if !appleAccessGranted && appleCalendarEnabled {
            appleCalendarEnabled = false
        }
        // Populate the mirror's destination picker if it's already on when Settings opens.
        if appleAccessGranted && appleWritebackEnabled {
            refreshAppleWritableCalendars()
        }
    }

    /// Loads the pickable Apple destination calendars, seeding the selection to the first
    /// writable calendar so the Picker isn't blank (empty falls back to Apple's default).
    private func refreshAppleWritableCalendars() {
        appleWritableCalendars = ekService.writableCalendars()
        if appleWritebackCalendarId.isEmpty, let first = appleWritableCalendars.first {
            appleWritebackCalendarId = first.id
        }
    }

    private var appleCalendarSubtitle: String {
        if appleCalendarEnabled && appleAccessGranted {
            return "Reading from Apple Calendar"
        }
        let status = ekService.authorizationStatus()
        switch status {
        case .denied, .restricted:
            return "Access denied — enable in System Settings → Privacy"
        case .notDetermined:
            return "Toggle to request access"
        default:
            return "Toggle to enable"
        }
    }

    private var appleCalendarSubtitleColor: Color {
        if appleCalendarEnabled && appleAccessGranted {
            return AtlasTheme.Colors.green
        }
        let status = ekService.authorizationStatus()
        if status == .denied || status == .restricted {
            return AtlasTheme.Colors.danger
        }
        return AtlasTheme.Colors.textMuted
    }

    // MARK: – Tasks section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("TASKS")
            if state.spaces.isEmpty {
                Text("Create a space first to set a default.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default space for new tasks")
                            .atlasFont(size: 14, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Quick-captured tasks without an inferred space land here")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Spacer()
                    Picker("Default task space", selection: $defaultTaskSpace) {
                        ForEach(state.spaces) { space in
                            Text(space.name).tag(space.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                    .tint(AtlasTheme.Colors.accent)
                    .onAppear {
                        // Heal a stale/empty default (e.g. the space was renamed or deleted).
                        if !state.spaces.contains(where: { $0.name == defaultTaskSpace }) {
                            defaultTaskSpace = state.spaces.contains(where: { $0.name == "Personal" })
                                ? "Personal"
                                : (state.spaces.first?.name ?? "Personal")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .atlasHairlineBelow()
            }
        }
    }

    // MARK: – Appearance section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("APPEARANCE")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text size")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Applies everywhere, immediately")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Picker("Text size", selection: $textScale) {
                    Text("Small").tag(0.9)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                    Text("X-Large").tag(1.3)
                    Text("XX-Large").tag(1.5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()
        }
    }

    // MARK: – Sidebar section

    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SIDEBAR")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidebar visibility")
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Slide out keeps it hidden until the cursor touches the left edge")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Picker("Sidebar visibility", selection: $sidebarMode) {
                    Text("Always visible").tag("always")
                    Text("Slide out on hover").tag("hover")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 170)
                .tint(AtlasTheme.Colors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .atlasHairlineBelow()
        }
    }

    // MARK: – Help & Tips section

    /// "Report a bug" sheet presentation (in-app issue filing, 0037).
    @State private var showReportBug = false

    /// Static, scannable practical tips — title + one-liner per row, hairline-
    /// separated like every other settings group. No links, no fluff.
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("HELP & TIPS")
            ForEach(Self.helpTips, id: \.title) { tip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title)
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(tip.detail)
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .atlasHairlineBelow()
            }

            Button { showReportBug = true } label: {
                row(icon: "ant", tint: AtlasTheme.Colors.accent,
                    title: "Report a bug",
                    subtitle: "Hit a snag? Send it straight to us — no email needed.")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showReportBug) {
            ReportBugSheet(db: state.db)
        }
    }

    private static let helpTips: [(title: String, detail: String)] = [
        ("Quick capture",
         "Jot a task from the capture bar; with no space inferred it lands in your default space (set it under Tasks)."),
        ("Spaces vs. projects & classes",
         "Spaces are your life buckets (School, Personal, Side). Projects live inside a space — in a School space they're Classes."),
        ("Drag to schedule",
         "Drag a task onto the calendar grid to block time for it. Drop sets the start; drag its edge to resize."),
        ("Canvas sync",
         "Connect your Canvas feed in Integrations to import assignments and events. Link a course to a class so its items file there."),
        ("Google Calendar",
         "Add accounts under Calendars, then link each to a space so its events sync out. An unlinked space stays in Atlas only."),
        ("Menu-bar agenda",
         "Atlas lives in the menu bar too — click its icon for today's agenda without opening the full window."),
    ]

    // MARK: – Shortcuts section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SHORTCUTS")
            Text("Rebind the in-app and system-wide capture keys. The Global Capture Key works from any app.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            ForEach(ShortcutAction.allCases) { action in
                shortcutRow(for: action)
            }

            if let warning = conflictWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.warning)
                    Text(warning)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.warning)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: conflictWarning)
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        let isRecording = recordingAction == action
        let binding = shortcuts.binding(for: action)

        HStack(spacing: 12) {
            // Action title
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if isRecording {
                    Text("Press a key combo…")
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
            }

            Spacer()

            // Current combo badge
            Text(isRecording ? "…" : binding.displayString)
                .atlasMono(size: 12, weight: .semibold)
                .foregroundStyle(isRecording ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording
                              ? AtlasTheme.Colors.accent.opacity(0.12)
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isRecording ? AtlasTheme.Colors.accent.opacity(0.4) : AtlasTheme.Colors.border,
                                lineWidth: 1)
                )

            // Record / Cancel button
            Button(isRecording ? "Cancel" : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording(for: action)
                }
            }
            .buttonStyle(.plain)
            .atlasFont(size: 13, weight: .medium, design: .rounded)
            .foregroundStyle(isRecording ? AtlasTheme.Colors.danger : AtlasTheme.Colors.accentText)

            // Reset button
            Button {
                shortcuts.reset(action)
                if recordingAction == action { stopRecording() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Reset to default (\(ShortcutBinding(key: action.defaultKey, modifiers: action.defaultModifiers).displayString))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Recording keeps the accent-highlighted instrument box; idle rows drop the
        // dead fill and separate with a hairline (paper idiom).
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRecording ? AtlasTheme.Colors.accent.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecording ? AtlasTheme.Colors.accent.opacity(0.25) : Color.clear,
                        lineWidth: 1)
        )
        .atlasHairlineBelow()
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }

    // MARK: – Recorder

    private func startRecording(for action: ShortcutAction) {
        stopRecording()
        conflictWarning = nil
        recordingAction = action

        // Install a local NSEvent monitor that captures the next key-down chord.
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Ignore modifier-only events (no characters).
            guard let chars = event.charactersIgnoringModifiers, let first = chars.lowercased().first,
                  first != "\u{0}" else { return event }

            // Escape → cancel without saving.
            if event.keyCode == 53 { // kVK_Escape
                DispatchQueue.main.async { stopRecording() }
                return nil
            }

            // Map NSEvent.ModifierFlags → SwiftUI EventModifiers.
            let nsFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            var swiftMods = EventModifiers()
            if nsFlags.contains(.command) { swiftMods.insert(.command) }
            if nsFlags.contains(.option)  { swiftMods.insert(.option) }
            if nsFlags.contains(.control) { swiftMods.insert(.control) }
            if nsFlags.contains(.shift)   { swiftMods.insert(.shift) }

            let candidate = ShortcutBinding(key: first, modifiers: swiftMods)

            DispatchQueue.main.async {
                // Reject bare keys — require at least ⌘, ⌃, or ⌥. Warning persists
                // until the next recording attempt (startRecording clears it).
                guard swiftMods.contains(.command) || swiftMods.contains(.control) || swiftMods.contains(.option) else {
                    conflictWarning = "Add ⌘, ⌥, or ⌃"
                    stopRecording()
                    return
                }

                // In-app duplicate is a hard block — the two actions can't share a combo.
                if let conflicting = shortcuts.conflict(candidate, excluding: action) {
                    conflictWarning = "Conflicts with \"\(conflicting.title)\" — not saved."
                } else if action == .capture {
                    // Warn-but-allow: a commonly-claimed combo still applies; only a real
                    // Carbon registration failure blocks. Warnings do NOT auto-dismiss —
                    // they clear when the next combo registers successfully.
                    let status = CaptureShortcutSync.apply(candidate, to: shortcuts)
                    if status != noErr {
                        conflictWarning = "Couldn't register \(candidate.displayString) — another app owns it. Pick a different shortcut."
                    } else {
                        conflictWarning = CaptureShortcutSync.claimWarning(candidate)
                    }
                } else {
                    conflictWarning = nil
                    shortcuts.set(candidate, for: action)
                }
                stopRecording()
            }
            return nil // consume the event
        }
    }

    private func stopRecording() {
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        recordingAction = nil
    }

    // MARK: helpers

    private var identityTitle: String {
        switch auth.state {
        case .signedIn(let u): return u.displayName
        case .offline: return "Offline mode"
        default: return "Not signed in"
        }
    }
    private var identitySubtitle: String {
        switch auth.state {
        case .signedIn(let u): return u.email ?? "Signed in"
        case .offline: return "Using local mock data"
        default: return ""
        }
    }

    /// Persists the edited nickname to profiles.display_name — only when it actually
    /// changed, so closing Settings unchanged never fires a redundant write.
    private func commitNickname() {
        guard nicknameSeeded else { return }
        let trimmed = nicknameField.trimmingCharacters(in: .whitespaces)
        guard trimmed != state.nickname else { return }
        state.saveNickname(trimmed)
    }

    private func label(_ t: String) -> some View {
        Text(t).atlasMono(size: 11, weight: .semibold).tracking(1.2)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    /// A red connection-error line with a "Report this" affordance that opens the
    /// app-wide bug sheet pre-filled with the error text (log auto-attached).
    private func errorRow(_ err: String) -> some View {
        HStack(spacing: 8) {
            Text(err).atlasFont(size: 12, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.danger)
            Button("Report this") { state.reportBug(prefillTitle: err) }
                .buttonStyle(.plain)
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
        }
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).atlasFont(size: 14, design: .rounded).foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(subtitle).atlasFont(size: 12, weight: .medium, design: .rounded).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
    }

    private func input(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain).atlasFont(size: 14, design: .rounded)
        .foregroundStyle(AtlasTheme.Colors.textPrimary).tint(AtlasTheme.Colors.accent)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
    }
}
