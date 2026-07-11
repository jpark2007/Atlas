import SwiftUI
import AtlasCore
import Speech
import AVFoundation
import UserNotifications

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

    // Connections — the server-owned connection rows, loaded in `.task`. nil ⇒ no
    // row (or not yet loaded / offline → the honest "not connected" copy).
    @State private var googleConn: GoogleConnectionRow?
    @State private var canvasConn: CanvasConnectionRow?

    /// Shared Canvas connect client (AtlasCore, platform-neutral) — full manage from
    /// the phone: connect / change destination space / disconnect.
    @StateObject private var canvas = CanvasService()
    @State private var canvasFeedURL = ""
    @State private var canvasSpaceName = ""        // connect-form destination space
    @State private var canvasConnectedSpace = ""   // connected-row picker (PATCHes on change)
    @State private var canvasWorking = false
    @State private var canvasError: String?
    @State private var showCanvasDisconnectConfirm = false

    // Delete-account state (mirrors the Mac SettingsView pattern).
    @State private var showDeleteConfirm = false
    @State private var deletingAccount = false
    @State private var deleteError: String?

    private let leadOptions = [0, 5, 15, 30, 60]

    var body: some View {
        List {
            accountSection
            captureSection
            notificationsSection
            voiceSection
            connectionsSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.bg.ignoresSafeArea())
        .tint(MobileTheme.ink)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            osAuthorized = settings.authorizationStatus != .denied
        }
        .task { await loadConnections() }
        .alert("Delete your Atlas account?", isPresented: $showDeleteConfirm) {
            Button("Delete account", role: .destructive) { performDeleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases your account and all your Atlas data — spaces, projects, tasks, events and notes. This can't be undone.")
        }
        .confirmationDialog("Disconnect Canvas?", isPresented: $showCanvasDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { disconnectCanvas() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Atlas will stop importing your Canvas assignments and events. You can reconnect anytime with your feed link.")
        }
        // Synced preferences — push the change (debounced). The pull-triggered echo of
        // either key is recognized as redundant and skipped.
        .onChange(of: defaultSpaceName) { _, _ in store.pushSyncedSettings() }
        .onChange(of: prefs)            { _, _ in store.pushSyncedSettings() }
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

    // MARK: - Connections

    private var connectionsSection: some View {
        Section {
            googleRow
            canvasRows
        } header: { header("Connections") }
    }

    /// Load the server-owned connection rows. On any error (offline / not signed in /
    /// no row) both stay nil → the honest "not connected" copy. Re-run after every
    /// Canvas connect / disconnect / space change so the status refreshes.
    private func loadConnections() async {
        googleConn = try? await store.db.loadGoogleConnection()
        canvasConn = try? await store.db.loadCanvasConnection()
    }

    // MARK: Google — read-only status (connect is a Desktop-loopback OAuth, Mac-only)

    private var googleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Google Calendar").rowLabel()
            Spacer()
            Text(googleStatusText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(googleStatusColor)
                .multilineTextAlignment(.trailing)
        }
        .rowStyle()
    }

    /// active ⇒ "Connected · synced Xm ago"; error/revoked ⇒ reconnect warning;
    /// no row ⇒ "Not connected — set up on your Mac". The phone never runs the
    /// Google OAuth (a Desktop-loopback flow, Mac-only today).
    private var googleStatusText: String {
        switch googleConn?.status {
        case "active":
            if let synced = googleConn?.lastSyncedDate {
                return "Connected · synced \(Self.relativeSync(from: synced))"
            }
            return "Connected"
        case .some:
            return "Reconnect needed — open Atlas on your Mac"
        case .none:
            return "Not connected — set up on your Mac"
        }
    }

    private var googleStatusColor: Color {
        switch googleConn?.status {
        case "active": return MobileTheme.green
        case .some:    return MobileTheme.warning
        case .none:    return MobileTheme.muted
        }
    }

    // MARK: Canvas — full manage (connect / change destination space / disconnect)

    @ViewBuilder
    private var canvasRows: some View {
        if let conn = canvasConn, conn.isServerOwned {
            canvasConnectedRows(conn)
        } else {
            canvasConnectForm(repaste: canvasConn?.status == "revoked")
        }
    }

    @ViewBuilder
    private func canvasConnectedRows(_ conn: CanvasConnectionRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Canvas").rowLabel()
                Text(canvasStatusText(conn))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(canvasStatusColor(conn))
            }
            Spacer()
            if canvasWorking {
                ProgressView().controlSize(.small)
            } else {
                Button("Disconnect") { showCanvasDisconnectConfirm = true }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.danger)
                    .buttonStyle(.plain)
            }
        }
        .rowStyle()

        // Destination space — editable after connect; changing it PATCHes canvas-connect.
        if !store.snapshot.spaces.isEmpty {
            Menu {
                ForEach(store.snapshot.spaces) { space in
                    Button(space.name) { canvasConnectedSpace = space.name }
                }
            } label: {
                HStack {
                    Text("Items land in").rowLabel()
                    Spacer()
                    Text(canvasConnectedSpace).rowValue()
                    chevron
                }
            }
            .rowStyle()
            .disabled(canvasWorking)
            // Seed the picker to the live space when the connected row appears (also
            // re-seeds after a disconnect→reconnect). No PATCH fires: updateCanvasSpace
            // no-ops when the new value equals the committed one.
            .onAppear { canvasConnectedSpace = conn.spaceName ?? "" }
            .onChange(of: canvasConnectedSpace) { old, new in
                updateCanvasSpace(current: conn.spaceName, from: old, to: new)
            }
        }

        if let canvasError {
            Text(canvasError)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.danger)
                .rowStyle()
        }
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

        Text("Canvas → Calendar → Calendar Feed (copy the .ics link)")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .rowStyle()
    }

    private func canvasStatusText(_ conn: CanvasConnectionRow) -> String {
        if conn.status == "error" {
            return "Sync paused — Atlas will retry automatically."
        }
        if let synced = conn.lastSyncedDate {
            return "Last synced \(Self.relativeSync(from: synced))."
        }
        return "Connected — first sync runs shortly."
    }

    private func canvasStatusColor(_ conn: CanvasConnectionRow) -> Color {
        conn.status == "error" ? MobileTheme.warning : MobileTheme.green
    }

    // MARK: Canvas actions (shared AtlasCore CanvasService; refresh status on success)

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
                try await canvas.connect(feedUrl: feed, spaceName: canvasSpaceName, jwt: jwt)
                await loadConnections()
                canvasFeedURL = ""   // don't retain the capability URL in the field
            } catch {
                canvasError = "Couldn't connect Canvas. Check the link and your connection, then try again."
            }
            canvasWorking = false
        }
    }

    /// Changes where unmatched Canvas items land (PATCH canvas-connect). `current` is
    /// the committed space, so the initial seed and the failure-revert are no-ops
    /// (both re-select `current`). On failure the picker reverts to `oldValue`.
    private func updateCanvasSpace(current: String?, from oldValue: String, to newValue: String) {
        guard newValue != (current ?? ""), !newValue.isEmpty else { return }
        canvasError = nil
        canvasWorking = true
        Task {
            guard let jwt = await store.validAccessToken() else {
                canvasError = "Sign in to Atlas to change the Canvas space."
                canvasConnectedSpace = oldValue
                canvasWorking = false
                return
            }
            do {
                try await canvas.updateSpace(spaceName: newValue, jwt: jwt)
                await loadConnections()
            } catch {
                canvasError = "Couldn't change the Canvas space. Check your connection and try again."
                canvasConnectedSpace = oldValue   // revert the picker to the committed space
            }
            canvasWorking = false
        }
    }

    private func disconnectCanvas() {
        canvasError = nil
        canvasWorking = true
        Task {
            guard let jwt = await store.validAccessToken() else {
                canvasError = "Sign in to Atlas to change Canvas sync."
                canvasWorking = false
                return
            }
            do {
                try await canvas.disconnect(jwt: jwt)
                canvasConn = nil   // clean disconnect: back to the paste form
            } catch {
                canvasError = "Couldn't disconnect Canvas. Check your connection and try again."
            }
            canvasWorking = false
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

    private func header(_ title: String) -> some View {
        Text(title).edCapsLabel().textCase(nil)
            .padding(.horizontal, 28).padding(.top, 8)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .padding(.horizontal, 28).padding(.top, 4)
    }
}

// MARK: - Editorial row styling

private extension View {
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
