import SwiftUI
import AtlasCore
import AppKit
import EventKit

/// Full-page Settings route (General / Integrations / Metrics). Opened by the sidebar gear.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var canvas: CanvasService
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var googleAuth: GoogleAuthService

    @AppStorage("calendar.google.enabled") private var googleCalendarEnabled: Bool = false

    /// Space new / quick-captured tasks fall into when none is inferred.
    @AppStorage("tasks.defaultSpaceName") private var defaultTaskSpace: String = "Personal"

    // MARK: – Canvas server-sync state
    @State private var canvasFeedURL = ""
    @State private var canvasSpaceName = "School"
    @State private var canvasWorking = false
    @State private var canvasError: String? = nil

    // MARK: – Shortcut recorder state
    @State private var recordingAction: ShortcutAction? = nil
    @State private var conflictWarning: String? = nil
    @State private var recordMonitor: Any? = nil

    // MARK: – Calendar sync state
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    @State private var appleAccessGranted: Bool = false
    @State private var appleAccessChecked: Bool = false

    // MARK: – Cloud-sync (server-owned) state
    @State private var cloudSyncWorking = false
    @State private var cloudSyncError: String? = nil

    private let ekService = EventKitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 24, weight: .semibold, design: .rounded))
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

            Picker("", selection: $state.settingsSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 14)

            Divider().overlay(AtlasTheme.Colors.border)

            sectionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { refreshAppleAccessStatus() }
        .onDisappear { stopRecording() }
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
                    tasksSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    shortcutsSection
                    Spacer(minLength: 8)
                }
                .padding(28)
            }
        case .integrations:
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    canvasSection
                    Divider().overlay(AtlasTheme.Colors.border)
                    integrations
                    Divider().overlay(AtlasTheme.Colors.border)
                    calendarsSection
                    Spacer(minLength: 8)
                }
                .padding(28)
            }
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
                    Text(identityTitle).font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(identitySubtitle).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                if case .offline = auth.state {
                    Button("Sign in") { auth.signOut() } // returns to gate
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.accentText)
                } else {
                    Button("Sign out") { auth.signOut() }
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.danger)
                }
            }
        }
    }

    // MARK: – Canvas (server-side ICS feed sync)

    /// Canvas now syncs server-side from the user's Calendar Feed URL (migration 0012 +
    /// `canvas-connect`/`canvas-sync`): assignments + events flow in on a cron with every
    /// Atlas client closed. When connected, the persisted status comes from
    /// `state.canvasConnection`; when not, the user pastes their feed link.
    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CANVAS")
            Text("Import Canvas assignments and events on a server schedule — no need to keep Atlas open.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            if let conn = state.canvasConnection, conn.isServerOwned {
                canvasConnectedRow(conn)
            } else {
                canvasConnectForm(repaste: state.canvasConnection?.status == "revoked")
            }
        }
    }

    @ViewBuilder
    private func canvasConnectedRow(_ conn: CanvasConnectionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(AtlasTheme.Colors.school)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Canvas feed connected")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(canvasStatusSubtitle(conn))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(canvasStatusColor(conn))
                }
                Spacer()
                if canvasWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Disconnect") { disconnectCanvas() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.danger)
                }
            }
            if let err = canvasError {
                Text(err).font(.system(size: 11, design: .rounded)).foregroundStyle(AtlasTheme.Colors.danger)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
        )
    }

    @ViewBuilder
    private func canvasConnectForm(repaste: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if repaste {
                Text("Your Canvas feed link expired — paste a fresh one to resume.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.warning)
            }

            input("https://school.instructure.com/feeds/calendars/…ics", text: $canvasFeedURL)

            if !state.spaces.isEmpty {
                HStack {
                    Text("Items land in")
                        .font(.system(size: 12, design: .rounded))
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
                Text(err).font(.system(size: 11, design: .rounded)).foregroundStyle(AtlasTheme.Colors.danger)
            }

            Button { connectCanvas() } label: {
                Text(canvasWorking ? "Connecting…" : "Connect Canvas")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    private func canvasStatusSubtitle(_ conn: CanvasConnectionRow) -> String {
        if conn.status == "error" {
            return "Sync paused — Atlas will retry automatically."
        }
        let dest = conn.spaceName.map { " → \($0)" } ?? ""
        if let synced = conn.lastSyncedDate {
            return "Last synced \(Self.relativeSync(from: synced))\(dest)."
        }
        return "Connected — first sync runs shortly\(dest)."
    }

    private func canvasStatusColor(_ conn: CanvasConnectionRow) -> Color {
        conn.status == "error" ? AtlasTheme.Colors.warning : AtlasTheme.Colors.green
    }

    private func connectCanvas() {
        let feed = canvasFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validCanvasFeedURL(feed) else {
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
                try await canvas.connect(feedUrl: feed, spaceName: canvasSpaceName, jwt: jwt)
                await state.refreshCanvasConnection()
                canvasFeedURL = ""   // don't retain the capability URL in the field
            } catch {
                canvasError = "Couldn't connect Canvas. Check the link and your connection, then try again."
            }
            canvasWorking = false
        }
    }

    private func disconnectCanvas() {
        guard let jwt = auth.session?.accessToken else {
            canvasError = "Sign in to Atlas to change Canvas sync."
            return
        }
        canvasError = nil
        canvasWorking = true
        Task {
            do {
                try await canvas.disconnect(jwt: jwt)
                state.canvasConnection = nil   // clean disconnect: back to the paste form
            } catch {
                canvasError = "Couldn't disconnect Canvas. Check your connection and try again."
            }
            canvasWorking = false
        }
    }

    /// Client-side shape check: https + a Canvas ICS feed path. A calm gate before we
    /// bother the server (which re-validates and Vaults the URL).
    private func validCanvasFeedURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              !(url.host ?? "").isEmpty else { return false }
        let path = url.path.lowercased()
        return path.hasSuffix(".ics") || path.contains("/feeds/calendars")
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("INTEGRATIONS")
            row(icon: "calendar", tint: AtlasTheme.Colors.school, title: "Google Calendar / Drive / Gmail",
                subtitle: "Sign in with Google to enable")
            row(icon: "applelogo", tint: AtlasTheme.Colors.textSecondary, title: "Sign in with Apple",
                subtitle: "Enable signing in Xcode to use on device")
        }
    }

    // MARK: – Calendars section

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CALENDARS")
            Text("Aggregate read-only. Pick one source to write new events.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            // ── Apple Calendar ───────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "applelogo")
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Calendar")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(appleCalendarSubtitle)
                        .font(.system(size: 11, design: .rounded))
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Google Calendar ──────────────────────────────────────────
            googleCalendarRow

            // ── Canvas ──────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(AtlasTheme.Colors.school)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Canvas LMS")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Group {
                        if let conn = state.canvasConnection, conn.isServerOwned {
                            Text(conn.status == "error"
                                 ? "Connected — sync paused, retrying"
                                 : "Connected — syncing in the cloud")
                                .foregroundStyle(conn.status == "error"
                                                 ? AtlasTheme.Colors.warning
                                                 : AtlasTheme.Colors.green)
                        } else {
                            Text("Not connected — add your feed in Integrations")
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    .font(.system(size: 11, design: .rounded))
                }
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .help("Read-only import")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Atlas Native ────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atlas (native)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Always on")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AtlasTheme.Colors.green)
                    .font(.system(size: 14, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Two-way sync toggle ─────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync calendar with Google")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(syncSubtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Toggle("", isOn: $googleCalendarEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AtlasTheme.Colors.textPrimary)
                    .disabled(!googleAuth.isConnected)
                    .onChange(of: googleCalendarEnabled) { _, on in
                        if on { state.backfillEventsToGoogle() }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Sync in the cloud (server-owned) ────────────────────────
            // Only when Google is connected locally: hands the refresh token to
            // the server so sync runs with every Atlas client closed.
            if googleAuth.isConnected {
                cloudSyncRow
            }

            // ── Default space mapping ──────────────────────────────────
            if !state.spaces.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default space for Apple events")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Imported events land in this space")
                            .font(.system(size: 11, design: .rounded))
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
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
                )
            }
        }
    }

    // MARK: – Google Calendar row

    private var googleCalendarRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundStyle(AtlasTheme.Colors.school)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Calendar")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(googleSubtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(googleSubtitleColor)
            }
            Spacer()
            if googleAuth.isConnected {
                Button("Disconnect") {
                    googleAuth.disconnect()
                    googleCalendarEnabled = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.danger)
            } else {
                Button {
                    Task {
                        await googleAuth.connect()
                        if googleAuth.isConnected { googleCalendarEnabled = true }
                    }
                } label: {
                    Text(googleAuth.isWorking ? "Connecting…" : "Connect")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                        )
                }
                .buttonStyle(.plain)
                .disabled(googleAuth.isWorking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
        )
    }

    private var syncSubtitle: String {
        if !googleAuth.isConnected { return "Connect Google above to enable two-way sync." }
        return googleCalendarEnabled
            ? "Events sync both ways with your primary Google Calendar."
            : "Off — your calendar stays in Atlas only."
    }

    private var googleSubtitle: String {
        if googleAuth.isConnected {
            if let syncError = state.lastCalendarSyncError { return "Sync issue — \(syncError)" }
            return "Connected — syncing your primary calendar"
        }
        if let error = googleAuth.errorMessage { return error }
        return "Not connected — sign in to sync events two-way"
    }

    private var googleSubtitleColor: Color {
        if googleAuth.isConnected {
            return state.lastCalendarSyncError == nil
                ? AtlasTheme.Colors.green : AtlasTheme.Colors.danger
        }
        if googleAuth.errorMessage != nil { return AtlasTheme.Colors.danger }
        return AtlasTheme.Colors.textMuted
    }

    // MARK: – Cloud sync (server-owned) row

    private var cloudSyncRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync in the cloud")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(cloudSyncSubtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(cloudSyncSubtitleColor)
                }
                Spacer()
                if cloudSyncWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: cloudSyncBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AtlasTheme.Colors.textPrimary)
                }
            }
            // A degraded server connection (error/revoked) keeps the row so the user
            // can restore it. A clean user-disconnect clears it (no nag).
            if let conn = state.googleConnection, conn.status != "active" {
                Button(cloudSyncWorking ? "Reconnecting…" : "Reconnect") { reconnectCloudSync() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .disabled(cloudSyncWorking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
        )
    }

    private var cloudSyncSubtitle: String {
        if let err = cloudSyncError { return err }
        switch state.googleConnection?.status {
        case "active":
            if let synced = state.googleConnection?.lastSyncedDate {
                return "Last synced \(Self.relativeSync(from: synced))."
            }
            return "On — syncing in the cloud, even with Atlas closed."
        case "error":
            return "Sync paused — reconnect to resume cloud sync."
        case "revoked":
            return "Disconnected on the server — reconnect to resume."
        default:
            return "On to keep your calendar in sync with Atlas closed."
        }
    }

    private var cloudSyncSubtitleColor: Color {
        if cloudSyncError != nil { return AtlasTheme.Colors.danger }
        switch state.googleConnection?.status {
        case "active":            return AtlasTheme.Colors.green
        case "error", "revoked":  return AtlasTheme.Colors.danger
        default:                  return AtlasTheme.Colors.textMuted
        }
    }

    /// Drives the toggle: flipping it runs the async connect/disconnect. The visible
    /// state only changes after the network call succeeds, so a failure leaves the
    /// mode untouched (calm error, no flip).
    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { state.serverSyncEnabled },
            set: { on in if on { enableCloudSync() } else { disableCloudSync() } }
        )
    }

    private func enableCloudSync() {
        guard let jwt = auth.session?.accessToken else {
            cloudSyncError = "Sign in to Atlas to enable cloud sync."
            return
        }
        guard googleAuth.currentRefreshToken != nil else {
            cloudSyncError = "Reconnect Google above, then try again."
            return
        }
        cloudSyncError = nil
        cloudSyncWorking = true
        Task {
            do {
                try await googleAuth.enableServerSync(jwt: jwt)
                await state.refreshGoogleConnection()   // re-derive server-owned mode
            } catch {
                cloudSyncError = "Couldn't turn on cloud sync. Check your connection and try again."
            }
            cloudSyncWorking = false
        }
    }

    private func disableCloudSync() {
        guard let jwt = auth.session?.accessToken else {
            cloudSyncError = "Sign in to Atlas to change cloud sync."
            return
        }
        cloudSyncError = nil
        cloudSyncWorking = true
        Task {
            do {
                try await googleAuth.disableServerSync(jwt: jwt)
                state.serverSyncEnabled = false
                state.googleConnection = nil            // clean disconnect: no Reconnect nag
            } catch {
                cloudSyncError = "Couldn't turn off cloud sync. Check your connection and try again."
            }
            cloudSyncWorking = false
        }
    }

    private func reconnectCloudSync() { enableCloudSync() }

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
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default space for new tasks")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Quick-captured tasks without an inferred space land here")
                            .font(.system(size: 11, design: .rounded))
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
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
                )
            }
        }
    }

    // MARK: – Shortcuts section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SHORTCUTS")
            Text("In-app only. Global system-wide hotkey is deferred (v2).")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            ForEach(ShortcutAction.allCases) { action in
                shortcutRow(for: action)
            }

            if let warning = conflictWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.warning)
                    Text(warning)
                        .font(.system(size: 11, design: .rounded))
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
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if isRecording {
                    Text("Press a key combo…")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
            }

            Spacer()

            // Current combo badge
            Text(isRecording ? "…" : binding.displayString)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording
                              ? AtlasTheme.Colors.accent.opacity(0.12)
                              : AtlasTheme.Colors.bgElevated)
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
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(isRecording ? AtlasTheme.Colors.danger : AtlasTheme.Colors.accentText)

            // Reset button
            Button {
                shortcuts.reset(action)
                if recordingAction == action { stopRecording() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Reset to default (\(ShortcutBinding(key: action.defaultKey, modifiers: action.defaultModifiers).displayString))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRecording
                      ? AtlasTheme.Colors.accent.opacity(0.05)
                      : AtlasTheme.Colors.bgElevated.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecording ? AtlasTheme.Colors.accent.opacity(0.25) : Color.clear,
                        lineWidth: 1)
        )
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
                // Reject bare keys — require at least ⌘, ⌃, or ⌥.
                guard swiftMods.contains(.command) || swiftMods.contains(.control) || swiftMods.contains(.option) else {
                    conflictWarning = "Add ⌘, ⌥, or ⌃"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { conflictWarning = nil }
                    stopRecording()
                    return
                }

                if let conflicting = shortcuts.conflict(candidate, excluding: action) {
                    conflictWarning = "Conflicts with \"\(conflicting.title)\" — not saved."
                    // Auto-clear warning after 2 s.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        conflictWarning = nil
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

    private func label(_ t: String) -> some View {
        Text(t).font(AtlasTheme.Font.sectionLabel()).tracking(1.2)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, design: .rounded)).foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(subtitle).font(.system(size: 11, design: .rounded)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
    }

    private func input(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain).font(.system(size: 13, design: .rounded))
        .foregroundStyle(AtlasTheme.Colors.textPrimary).tint(AtlasTheme.Colors.accent)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
    }
}
