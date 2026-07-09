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

    /// True once the server-side cron owns Google sync (`google_connections.status == "active"`).
    /// Loaded async in `.task`; stays false until known and on any error, so the row degrades
    /// gracefully to the snapshot-derived local-sync copy.
    @State private var cloudSynced = false

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
        .task {
            // Server owns Google↔DB sync once a connection is active. On any error
            // (offline, not signed in, no row) leave cloudSynced false → derived copy.
            if let conn = try? await store.db.loadGoogleConnection() {
                cloudSynced = conn.status == "active"
            }
        }
        .alert("Delete your Atlas account?", isPresented: $showDeleteConfirm) {
            Button("Delete account", role: .destructive) { performDeleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases your account and all your Atlas data — spaces, projects, tasks, events and notes. This can't be undone.")
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
            // "Synced automatically" once the server-side cron owns the sync; else
            // derived from the snapshot — Google events appear only once the Mac has
            // synced them into Supabase. The phone never connects to Google itself.
            labeledRow("Google Calendar", value: googleStatusText)
        } header: { header("Connections") }
    }

    /// Cloud sync active → "Synced automatically"; otherwise the honest Mac-derived
    /// syncing / not-syncing copy.
    private var googleStatusText: String {
        if cloudSynced { return "Synced automatically" }
        return googleConnected ? "Syncs via your Mac" : "Not syncing"
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

    private var googleConnected: Bool {
        store.snapshot.events.contains { $0.source == .google }
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
