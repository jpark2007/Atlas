import SwiftUI
import AppKit
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

    @State private var recording = false
    @State private var recordMonitor: Any?
    @State private var warning: String?

    private var binding: ShortcutBinding { shortcuts.binding(for: .capture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").foregroundStyle(AtlasTheme.Colors.accent)
                Text("Your Global Capture Key")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Text("Press \(binding.displayString) from any app to capture — type a task or speak it. Change it here or anytime in Settings.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(recording ? "…" : binding.displayString)
                    .atlasMono(size: 14, weight: .semibold)
                    .foregroundStyle(recording ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                Button(recording ? "Cancel" : "Record a new key") {
                    recording ? stopRecording() : startRecording()
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }

            if let warning {
                Text(warning).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.warning)
            }

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
        .onDisappear { stopRecording() }
    }

    private func finish() {
        CaptureKeyOnboarding.markSeen()
        dismiss()
    }

    private func startRecording() {
        stopRecording()
        warning = nil
        recording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.lowercased().first, first != "\u{0}" else { return event }
            if event.keyCode == 53 { DispatchQueue.main.async { stopRecording() }; return nil }
            var mods = EventModifiers()
            let flags = event.modifierFlags
            if flags.contains(.command) { mods.insert(.command) }
            if flags.contains(.option)  { mods.insert(.option) }
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.shift)   { mods.insert(.shift) }
            DispatchQueue.main.async {
                guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
                    warning = "Add ⌘, ⌥, or ⌃"; stopRecording(); return
                }
                let candidate = ShortcutBinding(key: first, modifiers: mods)
                if let other = shortcuts.conflict(candidate, excluding: .capture) {
                    warning = "Conflicts with \(other.title) — not saved."; stopRecording(); return
                }
                if let owner = CaptureShortcutSync.systemConflict(candidate) {
                    warning = "macOS uses that for \(owner) — pick another."; stopRecording(); return
                }
                let status = CaptureShortcutSync.apply(candidate, to: shortcuts)
                if status != noErr {
                    warning = "Something else owns that combo — pick another."
                }
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        recording = false
    }
}
