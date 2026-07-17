import SwiftUI
import AtlasCore

/// A tiny "Report a bug" sheet opened from Settings → Help & Tips. Multiline
/// field + Send; the report inserts into `bug_reports` via `AtlasDB` with the
/// signed-in user's JWT, stamping the app version + platform "macos". No email,
/// no attachments — beta testers file issues in one step. Follows AtlasTheme
/// (outline controls, caps labels, flat paper).
struct ReportBugSheet: View {
    /// The signed-in DB client (from `AppState.db`). Nil ⇒ offline; Send is disabled.
    let db: AtlasDB?

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
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
        VStack(alignment: .leading, spacing: 16) {
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
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))

                Text("Sent with Atlas \(appVersion) · macOS")
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
        .padding(24)
        .frame(width: 380)
        .background(AtlasTheme.Colors.bgBase)
    }

    private func send() {
        guard let db, !trimmed.isEmpty else { return }
        sending = true
        error = nil
        let text = String(trimmed.prefix(4000))
        let version = appVersion
        Task {
            do {
                try await db.insertBugReport(message: text, appVersion: version, platform: "macos")
                sent = true
            } catch {
                self.error = "Couldn't send — check your connection and try again."
            }
            sending = false
        }
    }
}
