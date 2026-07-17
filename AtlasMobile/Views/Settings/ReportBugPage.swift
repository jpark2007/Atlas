import SwiftUI
import AtlasCore

/// "Report a bug" subpage pushed from Settings. A multiline field + Send that
/// files into `bug_reports` via `AtlasDB` (same helper the Mac app uses),
/// stamping the app version + platform "ios". Editorial mobile styling: paper
/// bg, caps label, a 1.5 pt ink-outline Send control — no card chrome.
struct ReportBugPage: View {
    let db: AtlasDB

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sent {
                    Text("Thanks — your report was sent. We read every one.")
                        .font(.system(size: 15.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                } else {
                    Text("WHAT WENT WRONG?")
                        .edCapsLabel().textCase(nil)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Describe the bug — what you did and what happened.")
                                .font(.system(size: 15.5, weight: .regular, design: .rounded))
                                .foregroundStyle(MobileTheme.faint)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $message)
                            .font(.system(size: 15.5, weight: .regular, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                    }
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl)
                        .strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))

                    Text("Sent with Atlas \(appVersion) · iOS")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)

                    if let error {
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.danger)
                    }

                    Button(action: send) {
                        Text(sending ? "Sending…" : "Send")
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .frame(maxWidth: .infinity)
                            .edOutlineControl()
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.45 : 1)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .navigationTitle("Report a bug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        sending = true
        error = nil
        let text = String(trimmed.prefix(4000))
        let version = appVersion
        Task {
            do {
                try await db.insertBugReport(message: text, appVersion: version, platform: "ios")
                sent = true
            } catch {
                self.error = "Couldn't send — check your connection and try again."
            }
            sending = false
        }
    }
}
