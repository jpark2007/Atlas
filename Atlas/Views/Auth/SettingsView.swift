import SwiftUI
import AppKit
import EventKit

/// Account + integrations sheet. Reached from the sidebar profile row.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var canvas: CanvasService
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var googleAuth: GoogleAuthService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("calendar.google.enabled") private var googleCalendarEnabled: Bool = false

    @State private var canvasToken = ""

    // MARK: – Shortcut recorder state
    @State private var recordingAction: ShortcutAction? = nil
    @State private var conflictWarning: String? = nil
    @State private var recordMonitor: Any? = nil

    // MARK: – Calendar sync state
    @AppStorage("calendar.apple.enabled") private var appleCalendarEnabled: Bool = false
    @AppStorage("calendar.main") private var mainCalendar: String = "Atlas"
    @AppStorage("calendar.apple.defaultSpace") private var appleDefaultSpace: String = ""
    @State private var appleAccessGranted: Bool = false
    @State private var appleAccessChecked: Bool = false

    private let ekService = EventKitService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Settings").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                        state.presentGraph = true
                    } label: {
                        BrandLogo(size: 18).opacity(0.85)
                    }
                    .buttonStyle(.plain)
                    .help("Open relationship graph")
                    .padding(.trailing, 2)
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.textMuted)
                }

                account
                Divider().overlay(AtlasTheme.Colors.border)
                canvasSection
                Divider().overlay(AtlasTheme.Colors.border)
                integrations
                Divider().overlay(AtlasTheme.Colors.border)
                calendarsSection
                Divider().overlay(AtlasTheme.Colors.border)
                shortcutsSection

                Spacer(minLength: 8)
            }
            .padding(28)
        }
        .frame(width: 460, height: 800)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { refreshAppleAccessStatus() }
        .onDisappear { stopRecording() }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("ACCOUNT")
            HStack(spacing: 12) {
                Circle().fill(AtlasTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(AtlasTheme.Colors.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(identityTitle).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(identitySubtitle).font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                if case .offline = auth.state {
                    Button("Sign in") { auth.signOut() } // returns to gate
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.accent)
                } else {
                    Button("Sign out") { auth.signOut(); dismiss() }
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.danger)
                }
            }
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CANVAS")
            switch canvas.status {
            case .connected(let name):
                row(icon: "checkmark.seal.fill", tint: AtlasTheme.Colors.green,
                    title: "Connected as \(name)", subtitle: canvas.host)
                Button("Disconnect") { canvas.disconnect() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(AtlasTheme.Colors.danger)
            default:
                input("school.instructure.com", text: Binding(get: { canvas.host }, set: { canvas.host = $0 }))
                input("Canvas access token", text: $canvasToken, secure: true)
                if case .failed(let msg) = canvas.status {
                    Text(msg).font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.danger)
                }
                Button {
                    Task { await canvas.connect(host: canvas.host, token: canvasToken) }
                } label: {
                    Text(canvas.status == .connecting ? "Connecting…" : "Connect Canvas")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(AtlasTheme.Colors.bgDeep)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(AtlasTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Account → Settings → Approved Integrations → New Access Token")
                    .font(.system(size: 10)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
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
                .font(.system(size: 10))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            // ── Apple Calendar ───────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "applelogo")
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(appleCalendarSubtitle)
                        .font(.system(size: 11))
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
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Group {
                        if case .connected(let name) = canvas.status {
                            Text("Connected as \(name)")
                                .foregroundStyle(AtlasTheme.Colors.green)
                        } else {
                            Text("Not connected — event import deferred (v2)")
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                    .font(.system(size: 11))
                }
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .help("Read-only display")
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
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Always on")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AtlasTheme.Colors.green)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Main calendar picker ────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Main calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text("Atlas-native events only — write-back to Apple/Google deferred (v2)")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Picker("Main calendar", selection: $mainCalendar) {
                    Text("Atlas").tag("Atlas")
                    if appleCalendarEnabled && appleAccessGranted {
                        Text("Apple Calendar").tag("Apple")
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140)
                .tint(AtlasTheme.Colors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.5))
            )

            // ── Default space mapping ──────────────────────────────────
            if !state.spaces.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default space for Apple events")
                            .font(.system(size: 13))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Imported events land in this space")
                            .font(.system(size: 11))
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
                    .font(.system(size: 13))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(googleSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(googleSubtitleColor)
            }
            Spacer()
            if googleAuth.isConnected {
                Button("Disconnect") {
                    googleAuth.disconnect()
                    googleCalendarEnabled = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.danger)
            } else {
                Button {
                    Task {
                        await googleAuth.connect()
                        if googleAuth.isConnected { googleCalendarEnabled = true }
                    }
                } label: {
                    Text(googleAuth.isWorking ? "Connecting…" : "Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.bgDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AtlasTheme.Colors.accent)
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

    private var googleSubtitle: String {
        if googleAuth.isConnected { return "Connected — syncing your primary calendar" }
        if let error = googleAuth.errorMessage { return error }
        return "Not connected — sign in to sync events two-way"
    }

    private var googleSubtitleColor: Color {
        if googleAuth.isConnected { return AtlasTheme.Colors.green }
        if googleAuth.errorMessage != nil { return AtlasTheme.Colors.danger }
        return AtlasTheme.Colors.textMuted
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

    // MARK: – Shortcuts section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SHORTCUTS")
            Text("In-app only. Global system-wide hotkey is deferred (v2).")
                .font(.system(size: 10))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            ForEach(ShortcutAction.allCases) { action in
                shortcutRow(for: action)
            }

            if let warning = conflictWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.warning)
                    Text(warning)
                        .font(.system(size: 11))
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
                    .font(.system(size: 13))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                if isRecording {
                    Text("Press a key combo…")
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                }
            }

            Spacer()

            // Current combo badge
            Text(isRecording ? "…" : binding.displayString)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary)
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isRecording ? AtlasTheme.Colors.danger : AtlasTheme.Colors.accent)

            // Reset button
            Button {
                shortcuts.reset(action)
                if recordingAction == action { stopRecording() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
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
                Text(title).font(.system(size: 13)).foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
    }

    private func input(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain).font(.system(size: 13))
        .foregroundStyle(AtlasTheme.Colors.textPrimary).tint(AtlasTheme.Colors.accent)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
    }
}
