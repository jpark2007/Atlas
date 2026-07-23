import SwiftUI
import AtlasCore
import Speech
import AVFoundation
import UserNotifications
import TipKit

/// The gear-presented Settings sheet: SettingsView under an inline nav bar with a
/// Done button. Each tab's inline gear presents this.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                    }
                }
        }
    }
}

/// In-app settings (spec §4.4 + §7): account, the capture-fallback default space,
/// notification preferences, voice permission, and a derived Google-connected
/// status. No system-level settings.
struct SettingsView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.openURL) private var openURL

    /// Shared with CaptureView (Task 3) — the capture routing fallback.
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""
    @AppStorage("notificationPrefs") private var prefs = NotificationPrefs.default

    /// nil = not yet loaded; false = OS-denied (show honest off state); otherwise the app's own prefs UI.
    @State private var osAuthorized: Bool?

    // Connections — the server-owned connection rows, loaded in `.task`. Empty/nil ⇒
    // no row (or not yet loaded / offline → the honest "not connected" copy). Google is
    // read-only here (accounts are managed on the Mac); Canvas is fully manageable.
    @State private var googleConns: [GoogleConnection] = []
    @State private var docsConn: AtlasDB.GoogleDocsConnection?

    /// Shared multi-feed connect client (AtlasCore, platform-neutral) — full manage from
    /// the phone: connect Canvas / add an ICS calendar / re-space / disconnect.
    @StateObject private var feeds = FeedService()
    /// Subscribed calendar feeds (`calendar_feeds`) — Canvas + generic ICS.
    @State private var calendarFeeds: [CalendarFeedRow] = []
    @State private var canvasFeedURL = ""
    @State private var canvasSpaceName = ""        // Canvas connect-form destination space
    @State private var canvasWorking = false
    @State private var canvasError: String?

    // Generic ICS feed connect + per-row edit state.
    @State private var icsName = ""
    @State private var icsURL = ""
    @State private var icsSpaceName = ""
    @State private var icsWorking = false
    @State private var icsError: String?
    @State private var feedRowWorking: UUID?
    @State private var feedRowError: String?
    /// The feed the disconnect confirmation dialog is armed for.
    @State private var feedToDisconnect: CalendarFeedRow?

    // Delete-account state (mirrors the Mac SettingsView pattern).
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false
    @State private var deleteError: String?

    private let leadOptions = [0, 5, 15, 30, 60]

    // Onboarding tips (rule-gated in AtlasTips): connect a source, report a bug (beta).
    @State private var connectTip = AtlasTips.ConnectSource()
    @State private var bugTip = AtlasTips.ReportBug()

    /// The hub: each row pushes a detail subpage. `.task`/`.onChange` live here on the
    /// root — which stays alive under any pushed page — so connections load and synced
    /// prefs push regardless of which subpage is on screen.
    var body: some View {
        List {
            Section {
                navRow("Account") { accountPage }
                navRow("Integrations") { integrationsPage }
                navRow("Notifications") { notificationsPage }
                navRow("General") { generalPage }
                navRow("Help & Tips") { helpPage }
                navRow("Report a bug") { ReportBugPage(db: store.db) }
                    .onboardingTip(bugTip, when: AtlasBuild.isBeta)
            }
        }
        .settingsListChrome()
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            osAuthorized = settings.authorizationStatus != .denied
        }
        .task { await loadConnections() }
        // Synced preferences — push the change (debounced). The pull-triggered echo of
        // either key is recognized as redundant and skipped.
        .onChange(of: defaultSpaceName) { _, _ in store.pushSyncedSettings() }
        .onChange(of: prefs)            { _, _ in store.pushSyncedSettings() }
    }

    // MARK: - Hub rows & subpages

    /// A top-level hub row: a plain-List NavigationLink (its own trailing disclosure
    /// chevron) that pushes a detail subpage within the Settings NavigationStack.
    private func navRow<Destination: View>(
        _ title: String, @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink { destination() } label: { Text(title).rowLabel() }
            .rowStyle()
    }

    private var accountPage: some View {
        List { accountSection }
            .settingsListChrome()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete your Atlas account?", isPresented: $showDeleteConfirm) {
                Button("Delete account", role: .destructive) { performDeleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases your account and all your Atlas data — spaces, projects, tasks, events and notes. This can't be undone.")
            }
    }

    private var integrationsPage: some View {
        List {
            calendarsSection
            calendarFeedsSection
            integrationsSection
        }
        .settingsListChrome()
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect calendar?",
                            isPresented: Binding(get: { feedToDisconnect != nil },
                                                 set: { if !$0 { feedToDisconnect = nil } }),
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                if let feed = feedToDisconnect { disconnectFeed(feed) }
                feedToDisconnect = nil
            }
            Button("Cancel", role: .cancel) { feedToDisconnect = nil }
        } message: {
            Text("Atlas will stop importing this calendar's items. You can reconnect anytime with its link.")
        }
    }

    private var notificationsPage: some View {
        List { notificationsSection }
            .settingsListChrome()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var generalPage: some View {
        List {
            captureSection
            voiceSection
        }
        .settingsListChrome()
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helpPage: some View {
        List { helpSection }
            .settingsListChrome()
            .navigationTitle("Help & Tips")
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            labeledRow("Email", value: store.session?.user.email ?? "—")
            Button(action: store.signOut) {
                Text("Sign out")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .rowStyle()
            Button { showDeleteConfirm = true } label: {
                Text(deletingAccount ? "Deleting account…" : "Delete account")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
            }
            .buttonStyle(.plain)
            .disabled(deletingAccount)
            .rowStyle()
            if let deleteError {
                Text(deleteError)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
                    .rowStyle()
            }
        } header: { header("Account") }
    }

    /// Fires the `delete-account` edge function; success clears the session (the
    /// app drops back to SignInView), failure surfaces an inline error row.
    private func performDeleteAccount() {
        deleteError = nil
        deletingAccount = true
        Task {
            deleteError = await store.deleteAccount()
            deletingAccount = false
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        Section {
            Menu {
                Button("First space") { defaultSpaceName = "" }
                ForEach(store.snapshot.spaces) { space in
                    Button(space.name) { defaultSpaceName = space.name }
                }
            } label: {
                HStack {
                    Text("Default space").rowLabel()
                    Spacer()
                    Text(defaultSpaceName.isEmpty ? "First space" : defaultSpaceName).rowValue()
                    chevron
                }
            }
            .rowStyle()
        } header: { header("Capture") } footer: {
            footer("Where a captured item lands when the AI can’t match a space.")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            if osAuthorized == false {
                // Notifications are OFF at the OS level — the in-app toggles would lie.
                labeledRow("Notifications", value: "Off — enable in Settings")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings").rowValue().foregroundStyle(MobileTheme.ink)
                }
                .buttonStyle(.plain)
                .rowStyle()
            } else {
                notificationPrefsRows
            }
        } header: { header("Notifications") }
    }

    @ViewBuilder
    private var notificationPrefsRows: some View {
        Group {
            Toggle(isOn: bind(\.enabled)) { Text("Notifications").rowLabel() }.rowStyle()

            if prefs.enabled {
                Toggle(isOn: bind(\.events)) { Text("Events").rowLabel() }.rowStyle()
                Toggle(isOn: bind(\.tasksDue)) { Text("Tasks due").rowLabel() }.rowStyle()
                Toggle(isOn: bind(\.digest)) { Text("Daily digest").rowLabel() }.rowStyle()
                Toggle(isOn: bind(\.overdue)) { Text("Overdue nudges").rowLabel() }.rowStyle()

                Menu {
                    ForEach(leadOptions, id: \.self) { minutes in
                        Button(leadLabel(minutes)) { prefs.leadMinutes = minutes }
                    }
                } label: {
                    HStack {
                        Text("Remind me before").rowLabel()
                        Spacer()
                        Text(leadLabel(prefs.leadMinutes)).rowValue()
                        chevron
                    }
                }
                .rowStyle()

                if prefs.digest {
                    DatePicker(selection: digestTime, displayedComponents: .hourAndMinute) {
                        Text("Digest time").rowLabel()
                    }
                    .rowStyle()
                }

                spacesPicker
            }
        }
    }

    @ViewBuilder
    private var spacesPicker: some View {
        Toggle(isOn: allSpacesBinding) { Text("All spaces").rowLabel() }.rowStyle()
        if prefs.spaceIds != nil {
            ForEach(store.snapshot.spaces) { space in
                Button { toggleSpace(space.id) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(space.color).frame(width: 8, height: 8)
                        Text(space.name).rowLabel()
                        Spacer()
                        if prefs.spaceIds?.contains(space.id) == true {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MobileTheme.ink)
                        }
                    }
                }
                .buttonStyle(.plain)
                .rowStyle()
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            labeledRow("Microphone & speech", value: voiceStatusText)
            if !voiceReady {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings").rowValue().foregroundStyle(MobileTheme.ink)
                }
                .buttonStyle(.plain)
                .rowStyle()
            }
        } header: { header("Voice") }
    }

    // MARK: - Integrations (Notes & Docs status + Canvas manage)

    private var integrationsSection: some View {
        Section {
            notesDocsRow
        } header: { header("Integrations") }
    }

    /// Load the server-owned connection rows. On any error (offline / not signed in /
    /// no row) they stay empty/nil → the honest "not connected" copy. Re-run after every
    /// feed connect / disconnect / space change so the status refreshes.
    private func loadConnections() async {
        googleConns   = (try? await store.db.loadGoogleConnections()) ?? []
        docsConn      = try? await store.db.loadGoogleDocsConnection()
        calendarFeeds = (try? await store.db.loadCalendarFeeds()) ?? []
    }

    // MARK: Notes & Docs — read-only status (the dedicated Drive/Docs Google login)

    private var notesDocsRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Notes & Docs").rowLabel()
            Text(notesDocsStatusText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(notesDocsStatusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle()
    }

    /// active ⇒ "Connected · email"; any other status ⇒ reconnect warning; no row ⇒
    /// "Not connected". The phone never runs the Google OAuth (a Desktop-loopback flow,
    /// Mac-only today), so this is informational.
    private var notesDocsStatusText: String {
        guard let docs = docsConn else { return "Not connected — set up on your Mac" }
        return docs.status == "active"
            ? "Connected · \(docs.googleEmail)"
            : (docs.lastError ?? "Reconnect needed — open Atlas on your Mac")
    }

    private var notesDocsStatusColor: Color {
        guard let docs = docsConn else { return MobileTheme.muted }
        return docs.status == "active" ? MobileTheme.green : MobileTheme.warning
    }

    // MARK: - Help & Tips (static — short practical pointers, no links)

    private var helpSection: some View {
        Section {
            ForEach(helpTips, id: \.title) { tip in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.title).rowLabel()
                    Text(tip.body)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowStyle()
            }
        } header: { header("Help & Tips") }
    }

    private let helpTips: [(title: String, body: String)] = [
        ("Quick capture",
         "Tap + to jot a task or event by voice or text. Atlas files it into the right space — or your Default space when it can’t tell."),
        ("Spaces vs. projects",
         "Spaces are the big areas of your life; projects and classes live inside them. Capture picks a space — organize the rest on Mac or web."),
        ("Schedule views",
         "Switch between the list and the hour grid. On the grid, long-press a block and drag to move it to a new time."),
        ("Canvas sync",
         "Canvas assignments come in read-only. Connect or change where they land here; manage the feed on Mac or web."),
        ("Google Calendar",
         "Connected Google calendars are read-only on your phone. Add or manage accounts in Atlas on your Mac — they sync here."),
        ("Notifications",
         "Choose what nudges you — events, tasks due, a daily digest, overdue reminders — under Notifications above."),
    ]

    // MARK: - Calendars (Google Calendar accounts — read-only, managed on the Mac)

    private var calendarsSection: some View {
        Section {
            if googleConns.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Google Calendar").rowLabel()
                    Spacer()
                    Text("Not connected — set up on your Mac")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .multilineTextAlignment(.trailing)
                }
                .rowStyle()
            } else {
                ForEach(googleConns) { conn in
                    googleAccountRow(conn)
                }
            }
        } header: { header("Calendars") } footer: {
            footer("Add or manage Google accounts in Atlas on your Mac — they sync here automatically.")
        }
    }

    /// One connected Google account: name, muted email, and a per-account status line
    /// (incl. the reconnect-needed warning). Read-only — no tap target, no manage flow.
    private func googleAccountRow(_ conn: GoogleConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conn.name).rowLabel()
            Text(conn.googleEmail)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
            Text(googleAccountStatus(conn))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(googleAccountStatusColor(conn))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle()
    }

    /// Per-account status, mirroring the Mac's `googleConnectionStatus`.
    private func googleAccountStatus(_ conn: GoogleConnection) -> String {
        switch conn.status {
        case "error", "revoked":
            return "Reconnect needed — open Atlas on your Mac"
        default:
            if conn.spaceId == nil { return "Connected — read-in only" }
            if let synced = conn.lastSyncedDate {
                return "Connected · synced \(Self.relativeSync(from: synced))"
            }
            return "Connected — first sync runs shortly"
        }
    }

    private func googleAccountStatusColor(_ conn: GoogleConnection) -> Color {
        conn.status == "active" ? MobileTheme.green : MobileTheme.warning
    }

    // MARK: - Calendar feeds (Canvas + generic ICS — full manage)

    private var calendarFeedsSection: some View {
        Section {
            // Canvas — the suggested first-class feed (connect card when none active).
            if !hasActiveCanvasFeed {
                Text("Canvas").rowLabel().rowStyle()
                canvasConnectForm(repaste: canvasFeedRow?.status == "revoked")
            }
            // Add any calendar by ICS link.
            icsConnectForm
            // Connected feeds (Canvas + ICS).
            ForEach(connectedFeeds) { feed in
                feedRows(feed)
            }
            if let feedRowError {
                Text(feedRowError)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
                    .rowStyle()
            }
        } header: { header("Calendar feeds") } footer: {
            footer("Add any calendar by link — Canvas, Schoology, and more. These calendars are read-only in Atlas.")
        }
    }

    private var canvasFeedRow: CalendarFeedRow? {
        calendarFeeds.first { $0.feedType == "canvas" }
    }
    private var hasActiveCanvasFeed: Bool {
        calendarFeeds.contains { $0.feedType == "canvas" && $0.isServerOwned }
    }
    private var connectedFeeds: [CalendarFeedRow] {
        calendarFeeds.filter { $0.isServerOwned }
    }

    /// "Add calendar (ICS link)" — name + ICS URL + destination space, mirroring the
    /// Canvas connect form. Connects a generic `ics`-type feed (read-only events only).
    @ViewBuilder
    private var icsConnectForm: some View {
        Text("Add calendar (ICS link)").rowLabel().rowStyle()

        TextField("Calendar name (e.g. Schoology)", text: $icsName)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .rowStyle()

        TextField("https://…/calendar.ics", text: $icsURL)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .rowStyle()

        if !store.snapshot.spaces.isEmpty {
            Menu {
                ForEach(store.snapshot.spaces) { space in
                    Button(space.name) { icsSpaceName = space.name }
                }
            } label: {
                HStack {
                    Text("Items land in").rowLabel()
                    Spacer()
                    Text(icsSpaceName).rowValue()
                    chevron
                }
            }
            .rowStyle()
            .onAppear {
                if !store.snapshot.spaces.contains(where: { $0.name == icsSpaceName }) {
                    icsSpaceName = store.snapshot.spaces.first?.name ?? ""
                }
            }
        }

        if let icsError {
            Text(icsError)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.danger)
                .rowStyle()
        }

        Button { connectICS() } label: {
            Text(icsWorking ? "Adding…" : "Add calendar")
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
        .disabled(icsWorking)
        .rowStyle()

        Text("Most apps share a calendar as a private ‘ICS’ or ‘iCal’ link (it usually ends in .ics). In Schoology: Calendar → iCal/Calendar Feed. Atlas checks it for updates automatically.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .rowStyle()
    }

    /// One connected feed (Canvas or ICS): name + type badge + status, an inline space
    /// picker (PATCH), and Disconnect (DELETE, via the confirmation dialog).
    @ViewBuilder
    private func feedRows(_ feed: CalendarFeedRow) -> some View {
        let isCanvas = feed.feedType == "canvas"
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feed.displayName).rowLabel()
                    Text(isCanvas ? "CANVAS" : "ICS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Text(feedStatusText(feed))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(feedStatusColor(feed))
            }
            Spacer()
            if feedRowWorking == feed.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Disconnect") { feedToDisconnect = feed }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
                    .buttonStyle(.plain)
            }
        }
        .rowStyle()

        if !store.snapshot.spaces.isEmpty {
            Menu {
                ForEach(store.snapshot.spaces) { space in
                    Button(space.name) { updateFeedSpace(feed, to: space.name) }
                }
            } label: {
                HStack {
                    Text("Items land in").rowLabel()
                    Spacer()
                    Text(feed.spaceName ?? "").rowValue()
                    chevron
                }
            }
            .rowStyle()
            .disabled(feedRowWorking == feed.id)
        }
    }

    private func feedStatusText(_ feed: CalendarFeedRow) -> String {
        if feed.status == "error" { return feed.lastError ?? "Sync paused — Atlas will retry automatically." }
        if let synced = feed.lastSyncedDate { return "Last synced \(Self.relativeSync(from: synced))." }
        return "Connected — first sync runs shortly."
    }

    private func feedStatusColor(_ feed: CalendarFeedRow) -> Color {
        feed.status == "error" ? MobileTheme.warning : MobileTheme.green
    }

    @ViewBuilder
    private func canvasConnectForm(repaste: Bool) -> some View {
        if repaste {
            Text("Your Canvas feed link expired — paste a fresh one to resume.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.warning)
                .rowStyle()
        }

        TextField("Paste Canvas feed URL", text: $canvasFeedURL)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .rowStyle()

        if !store.snapshot.spaces.isEmpty {
            Menu {
                ForEach(store.snapshot.spaces) { space in
                    Button(space.name) { canvasSpaceName = space.name }
                }
            } label: {
                HStack {
                    Text("Items land in").rowLabel()
                    Spacer()
                    Text(canvasSpaceName).rowValue()
                    chevron
                }
            }
            .rowStyle()
            .onAppear {
                // Seed to "School" (spec default) if present, else the first space.
                if !store.snapshot.spaces.contains(where: { $0.name == canvasSpaceName }) {
                    canvasSpaceName = store.snapshot.spaces.contains(where: { $0.name == "School" })
                        ? "School"
                        : (store.snapshot.spaces.first?.name ?? "School")
                }
            }
        }

        if let canvasError {
            Text(canvasError)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.danger)
                .rowStyle()
        }

        Button { connectCanvas() } label: {
            Text(canvasWorking ? "Connecting…" : "Connect Canvas")
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
        .disabled(canvasWorking)
        .rowStyle()
        .popoverTip(connectTip)

        Text("Canvas → Calendar → Calendar Feed (copy the .ics link)")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .rowStyle()
    }

    // MARK: Feed actions (shared AtlasCore FeedService; refresh status on success)

    /// Connects Canvas as a `canvas`-type feed (`feeds-connect`), preserving the paste-feed
    /// UX. The server keeps Canvas's assignment→task + course routing for canvas-type feeds.
    private func connectCanvas() {
        let feed = canvasFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CanvasService.isValidFeedURL(feed) else {
            canvasError = "That doesn't look like a Canvas feed link. Copy it from Canvas → Calendar → Calendar Feed."
            return
        }
        canvasError = nil
        canvasWorking = true
        Task {
            guard let jwt = await store.validAccessToken() else {
                canvasError = "Sign in to Atlas to connect Canvas."
                canvasWorking = false
                return
            }
            do {
                try await feeds.connect(feedUrl: feed, feedType: "canvas",
                                        displayName: "Canvas", spaceName: canvasSpaceName, jwt: jwt)
                await AtlasTipEvents.connectedSource.donate()
                UserDefaults.standard.set(true, forKey: "checklist.connected")
                AtlasTips.ConnectSource.hasConnection = true
                await loadConnections()
                canvasFeedURL = ""   // don't retain the capability URL in the field
            } catch {
                canvasError = "Couldn't connect Canvas. Check the link and your connection, then try again."
            }
            canvasWorking = false
        }
    }

    /// Connects a generic ICS calendar as an `ics`-type feed (read-only events only).
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
        icsError = nil
        icsWorking = true
        Task {
            guard let jwt = await store.validAccessToken() else {
                icsError = "Sign in to Atlas to add a calendar."
                icsWorking = false
                return
            }
            do {
                try await feeds.connect(feedUrl: url, feedType: "ics",
                                        displayName: name, spaceName: icsSpaceName, jwt: jwt)
                await AtlasTipEvents.connectedSource.donate()
                AtlasTips.ConnectSource.hasConnection = true
                await loadConnections()
                icsName = ""; icsURL = ""   // don't retain the capability URL
            } catch {
                icsError = "Couldn't add that calendar. Check the link and your connection, then try again."
            }
            icsWorking = false
        }
    }

    /// Re-routes a feed's unmatched items to a new space (PATCH `feeds-connect`).
    private func updateFeedSpace(_ feed: CalendarFeedRow, to newName: String) {
        guard newName != (feed.spaceName ?? ""), !newName.isEmpty else { return }
        feedRowError = nil
        feedRowWorking = feed.id
        Task {
            guard let jwt = await store.validAccessToken() else {
                feedRowError = "Sign in to Atlas to change where this calendar lands."
                feedRowWorking = nil
                return
            }
            do {
                try await feeds.updateFeed(id: feed.id, spaceName: newName, jwt: jwt)
                await loadConnections()
            } catch {
                feedRowError = "Couldn't change the space. Check your connection and try again."
            }
            feedRowWorking = nil
        }
    }

    /// Disconnects a feed (DELETE `feeds-connect`) → revoked server-side, dropped locally.
    private func disconnectFeed(_ feed: CalendarFeedRow) {
        feedRowError = nil
        feedRowWorking = feed.id
        Task {
            guard let jwt = await store.validAccessToken() else {
                feedRowError = "Sign in to Atlas to disconnect this calendar."
                feedRowWorking = nil
                return
            }
            do {
                try await feeds.disconnect(id: feed.id, jwt: jwt)
                await loadConnections()
            } catch {
                feedRowError = "Couldn't disconnect. Check your connection and try again."
            }
            feedRowWorking = nil
        }
    }

    /// Short relative label for "synced Xm ago" (mirrors the Mac SettingsView helper).
    private static func relativeSync(from date: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }

    // MARK: - Bindings & helpers

    private func bind(_ keyPath: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs[keyPath: keyPath] }, set: { prefs[keyPath: keyPath] = $0 })
    }

    private var allSpacesBinding: Binding<Bool> {
        Binding(get: { prefs.spaceIds == nil },
                set: { prefs.spaceIds = $0 ? nil : [] })
    }

    private func toggleSpace(_ id: UUID) {
        var ids = prefs.spaceIds ?? []
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        prefs.spaceIds = ids
    }

    private var digestTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: prefs.digestHour, minute: prefs.digestMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                prefs.digestHour = c.hour ?? 8
                prefs.digestMinute = c.minute ?? 0
            })
    }

    private func leadLabel(_ minutes: Int) -> String {
        minutes == 0 ? "At time" : "\(minutes) min"
    }

    private var voiceReady: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    private var voiceStatusText: String {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .authorized && mic == .granted { return "Enabled" }
        if speech == .denied || mic == .denied { return "Off" }
        return "Not asked"
    }

    // MARK: - Row primitives

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).rowLabel()
            Spacer()
            Text(value).rowValue()
        }
        .rowStyle()
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MobileTheme.faint)
    }

    // Headers and footers are section accessory rows, not `.rowStyle()` content rows,
    // so they need their own clear list-row background — without it a plain List draws
    // them on the default system (white) fill, which broke the paper bg behind every
    // caption. Zeroed insets align the internal 28 pt padding with the content rows.
    private func header(_ title: String) -> some View {
        Text(title).edCapsLabel().textCase(nil)
            .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 2)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .lineSpacing(1.5)
            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 2)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

// MARK: - Editorial row styling

private extension View {
    /// Shared list chrome for the Settings hub and every subpage — plain list, paper
    /// background, ink tint. Keeps the six pages visually identical.
    func settingsListChrome() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MobileTheme.bg.ignoresSafeArea())
            .tint(MobileTheme.ink)
    }

    /// Shared row chrome for the Settings list — full-bleed hairline separators on
    /// the bg, no card fill.
    func rowStyle() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(MobileTheme.hairline)
    }

    func rowLabel() -> some View {
        font(.system(size: 15.5, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
    }

    func rowValue() -> some View {
        font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.muted)
    }
}
