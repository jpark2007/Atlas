import SwiftUI
import AtlasCore

/// New-account first-run decision + local seen-flag for the name/nickname prompt.
/// Mirrors `CaptureKeyOnboarding` exactly: new account = session user created within
/// 7 days AND the prompt never shown on this device. Skipping still marks it seen, so
/// it never re-prompts.
enum NamePromptOnboarding {
    private static let seenKey = "onboarding.namePromptSeen"

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

/// A small editorial sheet shown once, right after sign-up, asking for a first name
/// or nickname to personalize the dashboard greeting. Skippable. Matches
/// `CaptureKeyPopup`'s look; persists into the profile's `display_name` via AppState.
struct NamePromptPopup: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "hand.wave.fill").foregroundStyle(AtlasTheme.Colors.accent)
                Text("What should Atlas call you?")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Text("A first name or nickname — we'll use it to say good morning. You can change it anytime in Settings.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Your name", text: $name)
                .textFieldStyle(.plain)
                .atlasFont(size: 14, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))

            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AtlasTheme.Colors.bgBase)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { state.saveNickname(trimmed) }
        finish()
    }

    /// Skip = never re-prompt (no name saved). Both paths mark the flag.
    private func finish() {
        NamePromptOnboarding.markSeen()
        dismiss()
    }
}
