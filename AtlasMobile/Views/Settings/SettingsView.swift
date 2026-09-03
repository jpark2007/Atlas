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
        // iPad presents this in a page-sheet card; without an explicit detent it lands as a
        // short slab. `.large` is the phone's implicit height anyway, so nothing moves there.
        .edSheetDetents([.large], preferringLarge: true)
    }
}

/// In-app settings under the SAME five headings as the Mac — Account, Calendars,
/// Capture & Tasks, Notes & Files, App & Help (Phase 5 IA) — so what a student learns
/// on one device transfers to the other. Mac-only rows (shortcut recorder, text size,
/// sidebar visibility) are simply absent; nothing iOS-only is invented, and the phone's
/// two OS-permission surfaces (notifications, microphone) live under App & Help.
struct SettingsView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.openURL) private var openURL

    /// Shared with CaptureView (Task 3) — the capture routing fallback.
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""
    @AppStorage("notificationPrefs") private var prefs = NotificationPrefs.default

    /// nil = not yet loaded; false = OS-denied (show honest off state); otherwise the app's own prefs UI.
    @State private var osAuthorized: Bool?

    // The server-owned connection rows, loaded in `.task`. Empty/nil ⇒ no row (or not
    // yet loaded / offline → the honest "not connected" copy). Google accounts are shown
    // here and managed on the Mac; by-link calendars are fully manageable.
    @State private var googleConns: [GoogleConnection] = []
    @State private var docsConn: AtlasDB.GoogleDocsConnection?

    /// Shared feed client (AtlasCore, platform-neutral) — re-space / disconnect an
    /// existing by-link calendar. Adding one is Mac-only (see `calendarsSection`).
    @StateObject private var feeds = FeedService()
    /// Subscribed calendar feeds (`calendar_feeds`) — generic ICS. Canvas feeds are set
    /// up on the Mac and never surfaced here; their synced items still show everywhere.
    @State private var calendarFeeds: [CalendarFeedRow] = []
    @State private var feedRowWorking: UUID?
    @State private var feedRowError: String?
    /// The feed the disconnect confirmation dialog is armed for.
    @State private var feedToDisconnect: CalendarFeedRow?
    /// Which Apple calendars show in Atlas — same device-local semantics as the Mac's
    /// picker (`AppleCalendarSelection`).
    @AppStorage(AppleCalendarSelection.hiddenKey) private var appleHiddenCalendarIds = ""

    // Delete-account state (mirrors the Mac SettingsView pattern).
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false
    @State private var deleteError: String?

    private let leadOptions = [0, 5, 15, 30, 60]

    // Onboarding tip (rule-gated in AtlasTips): report a bug (beta).
    @State private var bugTip = AtlasTips.ReportBug()

    /// The hub: each row pushes a detail subpage. `.task`/`.onChange` live here on the
    /// root — which stays alive under any pushed page — so connections load and synced
    /// prefs push regardless of which subpage is on screen.
    var body: some View {
        List {
            Section {
                identityRow
            }
            Section {
                // No "Account" row here — the identity header above IS the way in.
                navRow("Calendars") { calendarsPage }
                navRow("Capture & Tasks") { capturePage }
                navRow("Notes & Files") { notesFilesPage }
                navRow("App & Help") { appHelpPage }
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

    /// Who you're signed in as, at the top of the hub — an identity header (avatar +
    /// address), not another settings row. Mirrors the Mac's Account column, where the
    /// account reads as a person rather than a preference. Tapping it opens the same
    /// Account page the row below does, so sign-out and delete stay one tap away.
    private var identityRow: some View {
        NavigationLink { accountPage } label: {
            HStack(spacing: 12) {
                Circle().fill(MobileTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MobileTheme.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.session?.user.email ?? "Your account")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .lineLimit(1)
                    Text("Account, sign out, delete")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
            }
            .padding(.vertical, 4)
        }
        .rowStyle()
    }

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

    /// ONE unified list — a block per calendar source (each Google account ·
    /// each by-link calendar · Atlas itself), mirroring the Mac's Calendars heading.
    private var calendarsPage: some View {
        List {
            calendarsSection
        }
        .settingsListChrome()
        .navigationTitle("Calendars")
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

    private var capturePage: some View {
        List { captureSection }
            .settingsListChrome()
            .navigationTitle("Capture & Tasks")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var notesFilesPage: some View {
        List { notesFilesSection }
            .settingsListChrome()
            .navigationTitle("Notes & Files")
            .navigationBarTitleDisplayMode(.inline)
    }

    /// The Mac's App & Help, phone edition: School's show/hide, the two OS-permission
    /// surfaces the phone owns (notifications, microphone), then tips and bug reporting.
    private var appHelpPage: some View {
        List {
            schoolSection
            notificationsSection
            voiceSection
            helpSection
            Section {
                // Straight to the download band on the site, not the homepage — the
                // Mac app is a direct download.
                Button {
                    if let url = URL(string: "https://www.atlaslm.net/#download") { openURL(url) }
                } label: {
                    HStack {
                        Text("Atlas for Mac").rowLabel()
                        Spacer()
                        Text("atlaslm.net").rowValue()
                    }
                }
                .buttonStyle(.plain)
                .rowStyle()
                navRow("Report a bug") { ReportBugPage(db: store.db) }
                    .onboardingTip(bugTip, when: AtlasBuild.isBeta)
                labeledRow("Version", value: Self.appVersion)
            }
        }
        .settingsListChrome()
        .navigationTitle("App & Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - School (show / hide)

    /// The Mac keeps this beside its sidebar control rather than earning a sixth heading;
    /// on the phone the same switch lives here, with the same words.
    private var schoolSection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.schoolEnabled },
                                 set: { store.schoolEnabled = $0 })) {
                Text("School").rowLabel()
            }
            .rowStyle()
        } header: { header("School") } footer: {
            footer("Semesters, classes and their work. Turn it off and the tab disappears — nothing is deleted.")
        }
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
                    Text("Default space for new tasks").rowLabel()
                    Spacer()
                    Text(defaultSpaceName.isEmpty ? "First space" : defaultSpaceName).rowValue()
                    chevron
                }
            }
            .rowStyle()
        } header: { header("Capture & Tasks") } footer: {
            footer("Quick-captured tasks without an inferred space land here.")
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

    // MARK: - Notes & Files (the dedicated Drive/Docs Google login)

    private var notesFilesSection: some View {
        Section {
            notesDocsRow
        } header: { header("Notes & Files") }
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
        guard let docs = docsConn else { return "Not connected — Notes & Docs is set up in Atlas for Mac and syncs here" }
        return docs.status == "active"
            ? "Connected · \(docs.googleEmail)"
            : (docs.lastError ?? "Reconnect needed — reconnect once in Atlas for Mac and it syncs here")
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
        ("Spaces vs. projects & classes",
         "Spaces are the big areas of your life; projects and classes live inside them. Atlas on your phone is built for capture and review — the deeper reorganizing lives in Atlas for Mac and on the web, and everything stays in sync."),
        ("Schedule views",
         "Switch between the list and the hour grid. On the grid, long-press a block and drag to move it to a new time."),
        ("School",
         "Set up your semester once and your classes, their work and their meeting times all hang off it. Scan a syllabus from a class page to fill in the rest."),
        ("Google Calendar",
         "Connected Google calendars are shown, not editable on your phone. Accounts are managed in Atlas for Mac — everything syncs here automatically."),
        ("Notifications",
         "Choose what nudges you — events, tasks due, a daily digest, overdue reminders — under Notifications on this page."),
    ]

    // MARK: - Calendars (ONE unified list, one block per source)

    /// A block per calendar source — each Google account, each by-link calendar,
    /// and Atlas itself. Every block says what it shows in Atlas and, where the source can
    /// take them, where Atlas sends your own events. Mirrors the Mac's Calendars heading.
    private var calendarsSection: some View {
        Section {
            AppleCalendarConnectRow()
            if !store.appleCalendarEnabled {
                Text("Already connected Apple Calendar on Mac? Connect it here too — Apple requires calendar access to be granted separately on each device.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rowStyle()
            }
            applePicker

            googleAccountsBlock
            linkedCalendarsBlock
            if let feedRowError {
                Text(feedRowError)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
                    .rowStyle()
            }
            atlasNativeRow
            Text("Canvas courses are set up in Atlas for Mac — the classes and coursework they add sync here automatically.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowStyle()
        } header: { header("Calendars") } footer: {
            footer("Turn on the calendars you want to see in Atlas. Feeds added by link are managed in Atlas for Mac.")
        }
    }

    /// Which Apple calendars show in Atlas — device-local, mirroring the Mac's in-app
    /// picker (`Atlas/Views/Auth/SettingsView.swift`). Only shown once there's more than
    /// one calendar to choose between.
    @ViewBuilder
    private var applePicker: some View {
        let cals = store.eventKit.readableCalendars()
        if store.appleCalendarEnabled && cals.count > 1 {
            let hidden = AppleCalendarSelection.decode(appleHiddenCalendarIds)
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose which Apple calendars show in Atlas. This phone only.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                ForEach(cals, id: \.id) { cal in
                    let shown = !hidden.contains(cal.id)
                    Button { toggleAppleCalendar(cal.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: shown ? "checkmark.square.fill" : "square")
                                .foregroundStyle(shown ? MobileTheme.ink : MobileTheme.faint)
                            Text(cal.title).rowLabel().lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if hidden.count == cals.count {
                    Text("Every calendar is unchecked, so no Apple events show.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.warning)
                }
            }
            .rowStyle()
        }
    }

    private func toggleAppleCalendar(_ id: String) {
        var hidden = AppleCalendarSelection.decode(appleHiddenCalendarIds)
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        appleHiddenCalendarIds = AppleCalendarSelection.encode(hidden)
        store.refreshAppleEvents(around: Date())
    }

    // ── Google accounts (shown here, managed on the Mac) ────────────────
    @ViewBuilder
    private var googleAccountsBlock: some View {
        if googleConns.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("Google Calendar").rowLabel()
                Spacer()
                Text("Not connected — calendar accounts are managed in Atlas for Mac and sync here")
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
    }

    // ── Calendars added by link — one block each ─────────────────────────
    // Adding a new one is Mac-only (same `feeds-connect` function); a feed added there
    // already appears here.
    @ViewBuilder
    private var linkedCalendarsBlock: some View {
        ForEach(linkedFeeds) { feed in
            feedRows(feed)
        }
    }

    // ── Atlas itself ───────────────────────────────────────────────────
    private var atlasNativeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Atlas (native)").rowLabel()
                Text("Always on — events you make in Atlas live here")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MobileTheme.green)
        }
        .rowStyle()
    }

    /// One connected Google account: name, muted email, and a per-account status line
    /// (incl. the reconnect-needed warning). Shown here, managed on the Mac.
    private func googleAccountRow(_ conn: GoogleConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conn.name).rowLabel()
            Text(conn.googleEmail)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
            Text(googleAccountStatus(conn))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(googleAccountStatusColor(conn))
            Text("Show these events in Atlas — always on. Choose which of its calendars come in, and where Atlas sends your events, in Atlas on your Mac.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowStyle()
    }

    /// Per-account status, mirroring the Mac's `googleConnectionStatus`. The phone can't
    /// change where Atlas sends events (that PATCH is Mac-side), so the no-destination
    /// case says where to go rather than repeating the Mac's instruction verbatim.
    private func googleAccountStatus(_ conn: GoogleConnection) -> String {
        switch conn.status {
        case "error", "revoked":
            return "Reconnect needed — reconnect once in Atlas for Mac and it syncs here"
        default:
            if conn.spaceId == nil { return "Connected — not sending your Atlas events here" }
            if let synced = conn.lastSyncedDate {
                return "Connected · synced \(Self.relativeSync(from: synced))"
            }
            return "Connected — first sync runs shortly"
        }
    }

    private func googleAccountStatusColor(_ conn: GoogleConnection) -> Color {
        conn.status == "active" ? MobileTheme.green : MobileTheme.warning
    }

    // MARK: - Subscribed calendars (by-link — full manage from the phone)

    /// The user's by-link calendars — one unified-list block each. A Canvas feed
    /// (Mac-only setup) is deliberately excluded: its items still sync in and show.
    private var linkedFeeds: [CalendarFeedRow] {
        calendarFeeds.filter { $0.isServerOwned && $0.feedType != "canvas" }
    }

    /// One connected by-link calendar as a unified-list block: name + type
    /// badge + status, an inline destination-space picker (PATCH), and Disconnect
    /// (DELETE, via the confirmation dialog). These are read-in sources, so they get no
    /// "send my Atlas events here" control — just the plain-language note.
    @ViewBuilder
    private func feedRows(_ feed: CalendarFeedRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feed.displayName).rowLabel()
                    Text("CALENDAR LINK")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Text(feedStatusText(feed))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(feedStatusColor(feed))
                Text("Shown, not editable — Atlas never sends your events here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text("Put these events in").rowLabel()
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

    // MARK: Feed actions (shared AtlasCore FeedService; refresh status on success)

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
