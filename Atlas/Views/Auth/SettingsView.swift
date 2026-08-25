import SwiftUI
import AtlasCore
import AppKit
import EventKit
import TipKit

/// Full-page Settings route (Account / Calendars / Capture & Tasks / Notes & Files /
/// App & Help, plus Metrics). Opened by the sidebar gear.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    /// Multi-feed connect client (`calendar_feeds`) — Canvas + generic ICS feeds.
    @EnvironmentObject private var feeds: FeedService
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var googleAuth: GoogleAuthService
    /// Sparkle auto-updates — the App section's two update rows drive this.
    @EnvironmentObject private var updater: UpdaterService

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

    /// Key of the source row whose details are disclosed (only one at a time), and the
    /// "Add another calendar by link" sheet that holds the connect forms.
    @State private var expandedSource: String? = nil
    @State private var showAddCalendarSheet = false

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
    /// Which Apple calendars are hidden from Atlas — device-local, same reason.
    @AppStorage(AppleCalendarSelection.hiddenKey) private var appleHiddenCalendarIds: String = ""
    // Outbound push rules per object type. Work sessions default ON — reserved time IS busy
    // time — under a human-readable label the external calendar can actually show.
    @AppStorage("calendar.workSessions.push") private var workSessionPushEnabled: Bool = true
    @AppStorage("calendar.workSessions.titlePrefix") private var workSessionPrefix: String = CalendarSync.defaultWorkSessionPrefix
    @State private var appleWritableCalendars: [(id: String, title: String)] = []
    /// Every calendar Atlas could read — the per-calendar checkbox list in the Apple detail.
    @State private var appleReadableCalendars: [(id: String, title: String)] = []
    /// The LIVE EventKit grant, not a boolean guess. macOS 14 has five outcomes and
    /// write-only / denied must never render as a working connection.
    @State private var appleAccessStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private var appleAccessGranted: Bool { appleAccessStatus == .fullAccess }
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
        case .account:
            settingsStack { account }
        case .calendars:
            settingsStack(spacing: 26) {
                HStack(alignment: .top, spacing: 36) {
                    calendarSourcesColumn
                    calendarOutboundColumn
                }
            }
        case .capture:
            settingsStack(spacing: 26) {
                captureAndTasksSection
                Divider().overlay(AtlasTheme.Colors.border)
                CaptureHistorySection()
            }
        case .notes:
            settingsStack { notesFilesSection }
        case .app:
            settingsStack(spacing: 26) {
                appSection
                helpSection
            }
        case .metrics:
            MetricsView()
        }
    }

    /// The shared scrolling settings stack every heading (except Metrics) renders into.
    @ViewBuilder
    private func settingsStack<C: View>(spacing: CGFloat = 22, @ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
                Spacer(minLength: 8)
            }
            .padding(28)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            columnHeader("Account", note: "Who you're signed in as on this Mac.")

            // An account reads as an identity header — avatar + who you are — not as
            // another settings row.
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
                        .buttonStyle(.plain)
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                } else {
                    Button("Sign out") {
                        // Clear the settings-sync cache + synced keys AND every Google
                        // credential (singleton + per-connection keychain slots) so a next
                        // sign-in on a shared device starts clean — no cross-account leak.
                        state.settingsSync.reset()
                        googleAuth.disconnect()
                        auth.signOut()
                    }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
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
                    Text("Used to greet you on the dashboard. Leave it blank for a plain greeting.")
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .onAppear {
                    if !nicknameSeeded { nicknameField = state.nickname; nicknameSeeded = true }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button { showDeleteAccountConfirm = true } label: {
                        Text(deletingAccount ? "Deleting account…" : "Delete account…")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .disabled(deletingAccount)
                    Text("Erases your account and everything in it. This can't be undone.")
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    if let err = deleteAccountError { errorRow(err) }
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

    // MARK: – Calendars pane · LEFT column (one compact row per source)
    //
    // Subscribed calendar feeds live in `calendar_feeds` and sync server-side (migration
    // 0012+ · `feeds-connect` + the feed cron): each feed's capability URL is Vaulted once,
    // then assignments/events flow in with every Atlas client closed.

    /// Every calendar Atlas reads from — Apple, each Google account, each subscribed feed
    /// (`calendar_feeds`: Canvas + generic links, synced server-side), and Atlas itself —
    /// as one row each: icon · name · a single status line · one trailing control. The
    /// details (where events land, which calendars, disconnect, the connect forms) live
    /// behind the row: a disclosure for feeds/Apple, the account sheet for Google, and the
    /// "Add another calendar by link" sheet for connecting something new.
    private var calendarSourcesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("Your calendars", note: "One row per source. Atlas shows events from all of them.")

            appleSourceRow

            ForEach(state.googleConnections) { conn in
                googleSourceRow(conn)
            }
            if let err = googleError { errorRow(err).padding(.vertical, 8) }

            ForEach(connectedFeeds) { feed in
                feedSourceRow(feed)
            }
            if let err = feedRowError { errorRow(err).padding(.vertical, 8) }

            atlasNativeSourceRow

            // Adding is an action, not a source — both live under the list as the same
            // outlined button, so every row above is a calendar you actually have.
            VStack(alignment: .leading, spacing: 10) {
                outlinedAction(googleWorking ? "Connecting…" : "Add a Google account…",
                               working: googleWorking) { startAddGoogleAccount() }
                    .popoverTip(connectTip)
                outlinedAction("Add another calendar by link") { showAddCalendarSheet = true }
            }
            .padding(.top, 16)

            Text("Most apps (Schoology, Outlook, your gym) have a \"subscribe\" or \"calendar link\". Copy it and paste it here.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await state.refreshCalendarFeeds() }
        .sheet(item: $detailConnection) { conn in
            googleDetailSheet(conn)
        }
        .sheet(isPresented: $showAddGoogleSheet) {
            addGoogleSheet
        }
        .sheet(isPresented: $showAddCalendarSheet) {
            addCalendarSheet
        }
    }

    // MARK: – Shared pane anatomy (every Settings tab is built from these)

    /// A section heading — caps-mono title under a hairline, with an optional one-line note.
    private func columnHeader(_ title: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .atlasCapsLabel()
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .atlasHairlineBelow()
            if let note {
                Text(note)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.top, 8)
            }
        }
    }

    /// THE settings row, used by every tab: an optional 16 pt icon · 13 pt semibold name ·
    /// ONE status line · one trailing control · hairline. `status` is the tiny mono
    /// uppercase state line; `detail` is a short plain sentence. A row uses one or the
    /// other — never both, and never a stack of sentences. Anything longer lives behind
    /// the row (a disclosure or a sheet).
    @ViewBuilder
    private func settingsRow<Trailing: View>(
        icon: String? = nil,
        tint: Color = AtlasTheme.Colors.textSecondary,
        name: String,
        status: String? = nil,
        statusColor: Color = AtlasTheme.Colors.textMuted,
        // A calendar source row passes its health instead of a color: the dot and the
        // status sentence then both come from that one value and can't disagree.
        health: StatusDot.Health? = nil,
        detail: String? = nil,
        detailColor: Color = AtlasTheme.Colors.textMuted,
        onTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let content = HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(tint)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                if let status {
                    HStack(spacing: 6) {
                        if let health { StatusDot(health: health) }
                        Text(status)
                            .atlasMono(size: 10)
                            .textCase(.uppercase)
                            .foregroundStyle(health.map(StatusDot.textColor) ?? statusColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if let detail {
                    // Two lines is the ceiling: a row explains itself in a sentence, or
                    // the explanation belongs behind the row.
                    Text(detail)
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(detailColor)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .atlasHairlineBelow()

        if let onTap {
            content.onTapGesture(perform: onTap)
        } else {
            content
        }
    }

    /// The outlined action button that closes a section — "Add a Google account…",
    /// "Add another calendar by link". An action, never a row.
    private func outlinedAction(_ title: String, working: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                Text(title)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
            )
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    /// The disclosed detail block under a source row — indented to the row's text column.
    @ViewBuilder
    private func sourceDetail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(.leading, 28)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .atlasHairlineBelow()
    }

    /// A "where things land" space picker used by every detail block. `includeNone` adds
    /// the unlinked option (events stay in Atlas).
    private func spacePicker(_ title: String, selection: Binding<String>,
                             includeNone: Bool = false, disabled: Bool = false) -> some View {
        HStack {
            Text(title)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
            Picker(title, selection: selection) {
                if includeNone { Text("Nowhere — stays in Atlas").tag("") }
                ForEach(state.spaces) { space in
                    Text(space.name).tag(space.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
            .tint(AtlasTheme.Colors.accent)
            .disabled(disabled)
        }
    }

    private func disclosureChevron(_ expanded: Bool) -> some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .atlasFont(size: 11, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    private func toggleExpanded(_ key: String) {
        expandedSource = (expandedSource == key) ? nil : key
    }

    // ── Apple ────────────────────────────────────────────────────────────

    @ViewBuilder
    private var appleSourceRow: some View {
        settingsRow(icon: "applelogo", tint: AtlasTheme.Colors.textPrimary,
                    name: "Apple Calendar",
                    status: appleStatusLine,
                    health: appleHealth,
                    onTap: { toggleExpanded("apple") }) {
            // The switch owns the trailing slot on this row, so the chevron every other
            // source row uses to advertise its disclosure sits beside it — otherwise
            // nothing says the row itself opens (calendars, where events land, disconnect).
            HStack(spacing: 10) {
                Toggle("", isOn: $appleCalendarEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(AtlasTheme.Colors.textPrimary)
                    .onChange(of: appleCalendarEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            // Safe to call in any state: once the grant is decided macOS
                            // returns the standing answer instead of re-prompting.
                            _ = await ekService.requestAccess()
                            await MainActor.run {
                                refreshAppleAccessStatus()   // flips the switch back off if not granted
                                // Never fail silently: open the detail so the reason and the
                                // System Settings link are on screen.
                                if !appleAccessGranted { expandedSource = "apple" }
                            }
                        }
                    }
                disclosureChevron(expandedSource == "apple")
            }
        }
        if expandedSource == "apple" {
            sourceDetail {
                if appleAccessGranted {
                    if !state.spaces.isEmpty {
                        spacePicker("Apple events land in", selection: $appleDefaultSpace)
                            .onAppear {
                                if appleDefaultSpace.isEmpty, let first = state.spaces.first {
                                    appleDefaultSpace = first.name
                                }
                            }
                    }
                    appleCalendarsPicker
                } else {
                    Text(appleAccessExplanation)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if appleAccessStatus != .restricted { openCalendarPrivacySettingsButton }
                }

                appleDisconnect
            }
        }
    }

    /// The row's one mono state line — it must never read as "working" when the grant
    /// isn't full. macOS 14 has five outcomes and each gets its own honest sentence.
    private var appleStatusLine: String {
        switch appleAccessStatus {
        case .denied:     return "Access denied · allow in System Settings"
        case .restricted: return "Access blocked · calendars are restricted on this Mac"
        case .writeOnly:  return "Write-only · Atlas can add but not see events"
        case .fullAccess:
            return appleCalendarEnabled
                ? "Showing · this Mac"
                : "Not showing · turn on to add your Apple events"
        default:          return "Not showing · turn on to add your Apple events"
        }
    }

    /// The same five outcomes `appleStatusLine` reads, as one health value — the dot and
    /// the sentence's color both come from here. Write-only counts as an error: Atlas
    /// can't see a single event, which is exactly the state the grant needs fixing for.
    private var appleHealth: StatusDot.Health {
        switch appleAccessStatus {
        case .denied, .restricted, .writeOnly: return .error
        case .fullAccess:                      return appleCalendarEnabled ? .live : .off
        default:                               return .off
        }
    }

    /// The plain-sentence version of the status line, shown in the disclosed detail.
    private var appleAccessExplanation: String {
        switch appleAccessStatus {
        case .denied:
            return "Atlas was told no to calendar access, and macOS won't ask again. Turn Atlas on under Privacy & Security → Calendars, then flip this switch back on."
        case .restricted:
            return "Calendar access is blocked on this Mac by a profile or parental controls. Atlas can't ask for it."
        case .writeOnly:
            return "Atlas only got \"Add Only\" access: it can put events into Apple Calendar but can't see what's already there — so nothing shows in Atlas. Switch it to Full Access under Privacy & Security → Calendars."
        default:
            return "Turn the switch on and macOS will ask whether Atlas can see your calendars."
        }
    }

    /// Deep-links to the Calendars pane of Privacy & Security — the only place a macOS
    /// calendar grant can actually be changed.
    private var openCalendarPrivacySettingsButton: some View {
        Button("Open Privacy & Security → Calendars") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .atlasFont(size: 13, weight: .medium, design: .rounded)
        .foregroundStyle(AtlasTheme.Colors.accentText)
    }

    /// Which Apple calendars show in Atlas. macOS has no iOS-style "limited calendars"
    /// OS picker, so this in-app list is the equivalent — device-local, matching the
    /// per-calendar checkboxes a Google account gets. Unchecking never deletes anything;
    /// it only stops Atlas reading that calendar.
    @ViewBuilder
    private var appleCalendarsPicker: some View {
        if appleReadableCalendars.count > 1 {
            let hidden = AppleCalendarSelection.decode(appleHiddenCalendarIds)
            VStack(alignment: .leading, spacing: 8) {
                label("CALENDARS")
                Text("Choose which Apple calendars show in Atlas. This Mac only.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(appleReadableCalendars, id: \.id) { cal in
                            let shown = !hidden.contains(cal.id)
                            Button { toggleAppleCalendar(cal.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: shown ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(shown
                                                         ? AtlasTheme.Colors.textPrimary
                                                         : AtlasTheme.Colors.textMuted)
                                    Text(cal.title)
                                        .atlasFont(size: 13, design: .rounded)
                                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 168)
                if hidden.count == appleReadableCalendars.count {
                    Text("Every calendar is unchecked, so no Apple events show.")
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.warning)
                }
            }
        }
    }

    /// Turns Apple Calendar off in both directions and forgets the device-local Apple
    /// settings. The macOS grant itself is NOT ours to revoke — an app can't take back
    /// its own TCC permission — so the copy says where that lives instead of pretending.
    private var appleDisconnect: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Disconnect Apple Calendar") { disconnectApple() }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.danger)
            Text("Stops Atlas reading and writing Apple Calendar on this Mac and forgets these settings. Nothing is deleted from Apple Calendar. macOS keeps the permission itself — remove Atlas under Privacy & Security → Calendars to take that back.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if appleAccessGranted { openCalendarPrivacySettingsButton }
        }
        .padding(.top, 4)
    }

    private func toggleAppleCalendar(_ id: String) {
        var hidden = AppleCalendarSelection.decode(appleHiddenCalendarIds)
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        appleHiddenCalendarIds = AppleCalendarSelection.encode(hidden)
    }

    private func disconnectApple() {
        appleCalendarEnabled = false
        appleWritebackEnabled = false
        appleWritebackCalendarId = ""
        appleHiddenCalendarIds = ""
        appleWritableCalendars = []
        appleReadableCalendars = []
        state.externalEvents = []
    }

    // ── Google accounts ──────────────────────────────────────────────────

    /// One connected Google account — the same skeleton as the Apple row (16 pt icon ·
    /// name · one mono status line · one trailing control). The control is a chevron, not
    /// a switch: Google has no per-account on/off. The only thing an account-level switch
    /// could drive is the per-calendar selection, and deselecting a calendar server-side
    /// DELETES its mirrored Atlas events (google-connect PATCH) — a destructive action
    /// wearing a visibility switch, with no stored previous selection to restore. So the
    /// row keeps the chevron and everything editable (name, which calendars, where its
    /// events land, reconnect, disconnect) stays in the detail sheet the row opens.
    private func googleSourceRow(_ conn: GoogleConnection) -> some View {
        settingsRow(icon: "globe", tint: AtlasTheme.Colors.school,
                    name: "Google · \(conn.name)",
                    status: googleStatusLine(conn),
                    health: googleHealth(conn),
                    onTap: {
                        detailRename = conn.name
                        detailConnection = conn
                    }) {
            disclosureChevron(false)
        }
    }

    /// The account's one status line: is it showing, and where do Atlas events go.
    private func googleStatusLine(_ conn: GoogleConnection) -> String {
        guard conn.status == "active" else { return "Reconnect needed · not syncing" }
        let destination = spaceName(forSpaceId: conn.spaceId)
        let sending = destination.isEmpty
            ? "not sending Atlas events out"
            : "sending Atlas events → \(destination)"
        if let synced = conn.lastSyncedDate {
            return "Showing · synced \(Self.relativeSync(from: synced)) · \(sending)"
        }
        if let created = conn.createdDate, Date().timeIntervalSince(created) > Self.firstSyncGrace {
            return "Connected · no events received yet"
        }
        return "Showing · first sync runs shortly · \(sending)"
    }

    // ── Subscribed feeds (Canvas + calendar links) ───────────────────────

    @ViewBuilder
    private func feedSourceRow(_ feed: CalendarFeedRow) -> some View {
        let isCanvas = feed.feedType == "canvas"
        let key = feed.id.uuidString
        settingsRow(icon: isCanvas ? "graduationcap.fill" : "link",
                    tint: isCanvas ? AtlasTheme.Colors.school : AtlasTheme.Colors.textSecondary,
                    name: feed.displayName,
                    status: feedStatusLine(feed),
                    health: feedHealth(feed),
                    onTap: { toggleExpanded(key) }) {
            if feedRowWorking == feed.id {
                ProgressView().controlSize(.small)
            } else {
                disclosureChevron(expandedSource == key)
            }
        }
        if expandedSource == key {
            sourceDetail {
                // The server's own reason for a paused feed — actionable detail the
                // one-line row status can't carry.
                if feed.status == "error", let reason = feed.lastError, !reason.isEmpty {
                    Text(reason)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.warning)
                }
                if !state.spaces.isEmpty {
                    spacePicker("Items land in", selection: Binding(
                        get: { feed.spaceName ?? "" },
                        set: { updateFeedSpace(feed, to: $0) }
                    ), disabled: feedRowWorking == feed.id)
                }
                Button("Remove this calendar") { disconnectFeed(feed) }
                    .buttonStyle(.plain)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.danger)
                    .disabled(feedRowWorking == feed.id)
            }
        }
    }

    private func feedStatusLine(_ feed: CalendarFeedRow) -> String {
        if feed.status == "error" {
            return "Paused · Atlas will retry · shown, not editable"
        }
        let lead = feed.feedType == "canvas" ? "Showing" : "Calendar link · showing"
        if let synced = feed.lastSyncedDate {
            return "\(lead) · last synced \(Self.relativeSync(from: synced)) · shown, not editable"
        }
        return "\(lead) · first sync runs shortly · shown, not editable"
    }

    /// A feed syncs server-side on the 15-minute cron (0012+), so a `last_synced_at`
    /// older than two ticks means a run was missed — stalled, not broken. A paused feed
    /// (`status == "error"`) needs the user; its reason shows in the disclosed detail.
    private func feedHealth(_ feed: CalendarFeedRow) -> StatusDot.Health {
        if feed.status == "error" { return .error }
        guard let synced = feed.lastSyncedDate else { return .live }  // first sync pending
        return Date().timeIntervalSince(synced) > Self.feedSyncOverdue ? .stalled : .live
    }

    /// Two ticks of the 15-minute feed cron.
    private static let feedSyncOverdue: TimeInterval = 30 * 60

    // ── Atlas itself ─────────────────────────────────────────────────────

    private var atlasNativeSourceRow: some View {
        settingsRow(icon: "sparkles", tint: AtlasTheme.Colors.accent,
                    name: "Atlas",
                    status: "Always on · events you make here",
                    health: .live) {
            EmptyView()
        }
    }

    // MARK: – Calendars pane · RIGHT column (what leaves Atlas)

    /// The outbound side: the one thing Atlas actually pushes out (events), where they go,
    /// and plain-language reassurance about what never leaves.
    private var calendarOutboundColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("What Atlas sends to your calendar",
                         note: "Only what you choose leaves Atlas. Tasks never do.")

            settingsRow(name: "Events",
                        detail: "Things you schedule in Atlas show up in Apple Calendar on this Mac") {
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

            if appleWritebackEnabled && !appleWritableCalendars.isEmpty {
                sourceDetail {
                    HStack {
                        Text("They go into")
                            .atlasFont(size: 12, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        Spacer()
                        Picker("They go into", selection: $appleWritebackCalendarId) {
                            ForEach(appleWritableCalendars, id: \.id) { cal in
                                Text(cal.title).tag(cal.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                        .tint(AtlasTheme.Colors.accent)
                    }
                }
            }

            // Sub-rule of the mirror above: work sessions ride along by default (reserved
            // time IS busy time), under a label the other calendar can actually show.
            if appleWritebackEnabled {
                settingsRow(name: "Work sessions",
                            detail: "Reserved time shows as busy on your other calendars") {
                    Toggle("", isOn: $workSessionPushEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AtlasTheme.Colors.textPrimary)
                        .onChange(of: workSessionPushEnabled) { _, on in
                            if on { state.backfillWorkSessionsToApple() }
                        }
                }

                if workSessionPushEnabled {
                    sourceDetail {
                        HStack {
                            Text("Labelled")
                                .atlasFont(size: 12, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            Spacer()
                            TextField(CalendarSync.defaultWorkSessionPrefix, text: $workSessionPrefix)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                        Text(CalendarSync.mirroredWorkSessionTitle("English essay", prefix: workSessionPrefix))
                            .atlasFont(size: 11, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }
            }

            settingsRow(name: "Google accounts",
                        detail: "Each account gets the events from the space it's linked to") {
                stateBadge(googleOutboundState)
            }

            settingsRow(name: "Due dates",
                        detail: "Stay in Atlas — your other calendars stay clean") {
                stateBadge("Never sent")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A read-only trailing state — the mono caps label a row shows when it has no control.
    private func stateBadge(_ text: String) -> some View {
        Text(text)
            .atlasMono(size: 10)
            .textCase(.uppercase)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    /// How many Google accounts currently receive Atlas events.
    private var googleOutboundState: String {
        let linked = state.googleConnections.filter { $0.spaceId != nil }.count
        if state.googleConnections.isEmpty { return "None added" }
        return linked == 0 ? "None linked" : "\(linked) linked"
    }

    // MARK: – "Add another calendar by link" sheet

    /// The connect forms, moved off the page: Canvas (when it isn't connected yet) and any
    /// other calendar by its link.
    @ViewBuilder
    private var addCalendarSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Add a calendar")
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button("Done") { showAddCalendarSheet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }

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
                Divider().overlay(AtlasTheme.Colors.border)
            }

            icsConnectForm
        }
        .padding(24)
        .frame(width: 380)
        .background(AtlasTheme.Colors.bgBase)
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

    /// "Any other calendar" — display name + calendar link + destination space, reusing the
    /// Canvas connect card's visual template. Connects a generic `ics`-type feed.
    @ViewBuilder
    private var icsConnectForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                Text("Any other calendar")
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }

            input("Calendar name (e.g. Schoology)", text: $icsName)
            input("https://…/calendar.ics", text: $icsURL)

            if !state.spaces.isEmpty {
                HStack {
                    Text("Put these events in")
                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    Spacer()
                    Picker("Calendar-link space", selection: $icsSpaceName) {
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

            HStack(spacing: 6) {
                Text("Paste the calendar link from the other app.")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Image(systemName: "questionmark.circle")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .help("Not sure if your app has one? Search for '[app name] calendar link' to see if it does and how to copy it. In Schoology: Calendar, then Calendar Feed. Calendars added this way are shown in Atlas but not editable here.")
            }
        }
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
                    Text("Put these events in")
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
                showAddCalendarSheet = false
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
                showAddCalendarSheet = false
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

    private var notesFilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("Notes & files",
                         note: "The Google account Atlas uses for Drive and Docs — separate from your calendar accounts.")

            // ── Notes & Docs (dedicated Drive/Docs login, one at a time) ─
            notesDocsRow

            // ── Per-tab Google Doc sync (beta) ──────────────────────────
            settingsRow(icon: "doc.on.doc",
                        name: "Per-tab Google Doc sync (beta)",
                        detail: "Multi-tab Docs edit tab-by-tab; tabs with tables stay read-only.") {
                Toggle("", isOn: $perTabSyncEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
            }
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
        settingsRow(icon: "doc.text",
                    tint: AtlasTheme.Colors.school,
                    name: "Google Drive & Docs",
                    detail: docsDetailLine,
                    detailColor: docsDetailColor) {
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
        if let err = docsError {
            errorRow(err).padding(.vertical, 8)
        }
    }

    /// The Docs row's one line: which account is in use, or what to do about it. Covers
    /// the fallback case too — no explicit Docs login, but calendar accounts exist, so
    /// the server uses the oldest one until the user picks explicitly.
    private var docsDetailLine: String {
        if let docs = docsConnection {
            return docs.status == "active"
                ? "Signed in as \(docs.googleEmail)"
                : (docs.lastError ?? "Reconnect needed — Drive and Docs have stopped syncing")
        }
        if let fallback = state.googleConnections.first {
            return "Using \(fallback.googleEmail) from your calendar accounts — sign in to choose"
        }
        return "Sign in to choose the Google account Drive and Docs use"
    }

    private var docsDetailColor: Color {
        (docsConnection?.status ?? "active") == "active"
            ? AtlasTheme.Colors.textMuted
            : AtlasTheme.Colors.warning
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

    /// Grace period after a connection is created before a still-empty `last_synced_at`
    /// is treated as a stall rather than a pending first sync. The cron runs every 5
    /// minutes (0008), so ~15 min covers a slow first tick without masking a dead one.
    private static let firstSyncGrace: TimeInterval = 15 * 60

    /// The connection-health derivation `googleStatusLine` narrates, as one health value:
    /// a stopped connection needs the user (error); an active one past the grace window
    /// that has never received events is stalled; everything else — including a first sync
    /// still inside the grace window — is live. The connection's own error reason is
    /// surfaced verbatim in its detail sheet.
    private func googleHealth(_ conn: GoogleConnection) -> StatusDot.Health {
        guard conn.status == "active" else { return .error }
        if conn.lastSyncedDate == nil,
           let created = conn.createdDate, Date().timeIntervalSince(created) > Self.firstSyncGrace {
            return .stalled
        }
        return .live
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

            // Where this account's Atlas events go — moved off the source row.
            if !state.spaces.isEmpty {
                spacePicker("Atlas events go to", selection: Binding(
                    get: { spaceName(forSpaceId: conn.spaceId) },
                    set: { updateGoogleSpace(conn, toSpaceName: $0) }
                ), includeNone: true, disabled: googleWorking)
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
                    label("SEND MY ATLAS EVENTS HERE")
                    Picker("Destination space", selection: $newAccountSpace) {
                        Text("Nowhere — stays in Atlas").tag("")
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

    /// Change (or clear) the connection's destination space. `""` unlinks — Atlas then
    /// only shows this account's events and never sends its own there.
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
        appleAccessStatus = ekService.authorizationStatus()
        // Anything short of full access can't read events, so the switch must not sit "on".
        if !appleAccessGranted && appleCalendarEnabled {
            appleCalendarEnabled = false
        }
        appleReadableCalendars = appleAccessGranted ? ekService.readableCalendars() : []
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

    // MARK: – Capture & tasks section

    /// Where captured tasks land, and the keys that open capture — one row each. The
    /// shortcut recorder keeps its existing interaction (Record → press a combo), just
    /// wearing the row skeleton instead of its own boxed card.
    private var captureAndTasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("Capture & tasks",
                         note: "The global capture key works from any app, even when Atlas is in the background.")

            if state.spaces.isEmpty {
                settingsRow(icon: "tray.and.arrow.down",
                            name: "Default space for new tasks",
                            detail: "Make a space first, then you can pick one here") {
                    EmptyView()
                }
            } else {
                settingsRow(icon: "tray.and.arrow.down",
                            name: "Default space for new tasks",
                            detail: "Captured tasks with no obvious space land here") {
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
            }

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
                .padding(.vertical, 8)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: conflictWarning)
            }
        }
    }

    // MARK: – App section (appearance + sidebar)

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("App")

            settingsRow(icon: "textformat.size",
                        name: "Text size",
                        detail: "Applies everywhere, right away") {
                Picker("Text size", selection: $textScale) {
                    Text("Small").tag(0.9)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                    Text("X-Large").tag(1.3)
                    Text("XX-Large").tag(1.5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }

            settingsRow(icon: "sidebar.left",
                        name: "Sidebar",
                        detail: "Slide out keeps it hidden until the cursor touches the left edge") {
                Picker("Sidebar visibility", selection: $sidebarMode) {
                    Text("Always visible").tag("always")
                    Text("Slide out on hover").tag("hover")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 170)
                .tint(AtlasTheme.Colors.accent)
            }

            // School is a sidebar section, so its show/hide lives with the sidebar's
            // other visibility control rather than earning a seventh settings heading.
            settingsRow(icon: "graduationcap",
                        name: "School",
                        detail: "Semesters, classes and their work. Turn it off and the section disappears — nothing is deleted.") {
                Toggle("", isOn: Binding(get: { state.schoolEnabled },
                                         set: { state.schoolEnabled = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
            }

            // Sparkle checks in the background on its own; these two rows are the
            // manual nudge and the "don't ask, just do it" preference.
            settingsRow(icon: "arrow.triangle.2.circlepath",
                        name: "Install updates automatically",
                        detail: "New versions download and install in the background. Off means Atlas asks first.") {
                Toggle("", isOn: $updater.automaticallyDownloadsUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
            }

            settingsRow(icon: "arrow.down.circle",
                        name: "Check for updates now",
                        detail: "Atlas already checks on its own — this asks right away.") {
                Button("Check") { updater.checkForUpdates() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
        }
    }

    // MARK: – Help & Tips section

    /// "Report a bug" sheet presentation (in-app issue filing, 0037).
    @State private var showReportBug = false

    /// Static, scannable practical tips — title + one-liner per row, hairline-
    /// separated like every other settings group. No links, no fluff.
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("Help & tips")

            ForEach(Self.helpTips, id: \.title) { tip in
                settingsRow(name: tip.title, detail: tip.detail) { EmptyView() }
            }

            settingsRow(icon: "ant",
                        tint: AtlasTheme.Colors.accent,
                        name: "Report a bug",
                        detail: "Hit a snag? Send it straight to us — no email needed.",
                        onTap: { showReportBug = true }) {
                disclosureChevron(false)
            }
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
         "Paste your Canvas calendar link under Calendars to bring in assignments and events. Link a course to a class so its items file there."),
        ("Google Calendar",
         "Add accounts under Calendars, then pick which space's events get sent to each one. Leave it unpicked and your Atlas events stay in Atlas."),
        ("Menu-bar agenda",
         "Atlas lives in the menu bar too — click its icon for today's agenda without opening the full window."),
    ]

    // MARK: – Shortcut row

    /// One rebindable key, in the row skeleton: name · a mono state line · the combo
    /// badge, Record/Cancel and Reset as the trailing control cluster. Same interaction
    /// as before (Record, then press a combo; Esc cancels) — no boxed card.
    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        let isRecording = recordingAction == action
        let binding = shortcuts.binding(for: action)

        settingsRow(icon: "command",
                    tint: isRecording ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary,
                    name: action.title,
                    status: isRecording ? "Press a key combo…" : nil,
                    statusColor: AtlasTheme.Colors.accentText,
                    detail: isRecording ? nil : "Press Record, then the keys you want") {
            HStack(spacing: 12) {
                // Current combo badge
                Text(isRecording ? "…" : binding.displayString)
                    .atlasMono(size: 12, weight: .semibold)
                    .foregroundStyle(isRecording ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording ? AtlasTheme.Colors.accent.opacity(0.4) : AtlasTheme.Colors.border,
                                    lineWidth: 1)
                    )

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
            .animation(.easeInOut(duration: 0.15), value: isRecording)
        }
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
