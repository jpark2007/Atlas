import SwiftUI
import AtlasCore

/// The "Report a bug" sheet — opened from Settings → Help & Tips, the ⌘K command
/// palette, the sidebar, or an error's "Report this" affordance. A short title, a
/// description, and an optional contact email; recent in-app logs (`AtlasLog`) are
/// attached automatically. Inserts into `bug_reports` via `AtlasDB` with the
/// signed-in user's JWT, stamping app version + platform "macos". Follows
/// AtlasTheme (outline controls, caps labels, flat paper).
struct ReportBugSheet: View {
    /// The signed-in DB client (from `AppState.db`). Nil ⇒ offline; Send is disabled.
    let db: AtlasDB?
    /// Optional seed for the Title field (e.g. an error message that opened this sheet).
    var prefillTitle: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var contactEmail = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String? = nil

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Report a bug")
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }

            if sent {
                Text("Thanks — your report was sent. We read every one.")
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            } else {
                Text("TITLE")
                    .atlasMono(size: 11, weight: .semibold).tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                TextField("A quick summary", text: $title)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))

                Text("WHAT WENT WRONG?")
                    .atlasMono(size: 11, weight: .semibold).tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                TextEditor(text: $message)
                    .textEditorStyle(.plain)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
                    .scrollContentBackground(.hidden)
                    .frame(height: 130)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))

                Text("YOUR EMAIL (OPTIONAL — IN CASE THIS IS SPECIFIC TO YOUR ACCOUNT)")
                    .atlasMono(size: 11, weight: .semibold).tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("you@example.com", text: $contactEmail)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))

                Text("Sent with Atlas \(appVersion) · macOS · Includes recent app logs")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                if let error {
                    Text(error)
                        .atlasFont(size: 12, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.danger)
                }

                HStack {
                    Spacer()
                    Button(sending ? "Sending…" : "Send") { send() }
                        .buttonStyle(.plain)
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                        .disabled(sending || trimmed.isEmpty || db == nil)
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { if title.isEmpty, let prefillTitle { title = prefillTitle } }
    }

    private func send() {
        guard let db, !trimmed.isEmpty else { return }
        sending = true
        error = nil
        let text = String(trimmed.prefix(4000))
        let version = appVersion
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailText = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let logText = String(AtlasLog.snapshot().suffix(16000))
        Task {
            do {
                try await db.insertBugReport(
                    message: text, appVersion: version, platform: "macos",
                    title: titleText.isEmpty ? nil : String(titleText.prefix(200)),
                    contactEmail: emailText.isEmpty ? nil : String(emailText.prefix(320)),
                    log: logText.isEmpty ? nil : logText)
                sent = true
            } catch {
                self.error = "Couldn't send — check your connection and try again."
            }
            sending = false
        }
    }
}
