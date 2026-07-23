import SwiftUI
import AtlasCore

/// New-account first-run decision + local seen-flag for the Global Capture Key popup.
enum CaptureKeyOnboarding {
    private static let seenKey = "onboarding.captureKeyPopupSeen"

    /// New account = session user created within 7 days AND the popup never shown on
    /// this device. If GoTrue omits created_at (nil) we treat the user as NOT new
    /// (safe). Existing users' accounts are older than 7 days.
    static func shouldShow(session: SupabaseSession?) -> Bool {
        guard !UserDefaults.standard.bool(forKey: seenKey),
              let iso = session?.user.createdAt,
              let created = parseISO(iso) else { return false }
        return Date().timeIntervalSince(created) < 7 * 24 * 60 * 60
    }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct CaptureKeyPopup: View {
    @EnvironmentObject private var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss

    private var binding: ShortcutBinding { shortcuts.binding(for: .capture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").foregroundStyle(AtlasTheme.Colors.accent)
                Text("Your Global Capture Key")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Text("Press \(binding.displayString) from any app to capture — type a task or speak it. You can change it anytime in Settings.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(binding.displayString)
                .atlasMono(size: 14, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))

            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button("Try it now") {
                    finish()
                    CapturePanelController.shared.show()
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AtlasTheme.Colors.bgBase)
    }

    private func finish() {
        CaptureKeyOnboarding.markSeen()
        dismiss()
    }
}
