import SwiftUI
import AtlasCore

/// New-account first-run decision + local seen-flag for the iPhone/iPad hand-off.
/// Same rule as `CaptureKeyOnboarding` / `NamePromptOnboarding`: new account = session
/// user created within 7 days AND never shown on this device. Dismissing marks it seen,
/// so it never nags — Settings keeps the same card reachable afterwards.
enum MobileAppsOnboarding {
    private static let seenKey = "onboarding.mobileAppsSeen"

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

/// The QR + App Store badge card — the same pair the download page shows, so a Mac user
/// can put Atlas on their phone or tablet without leaving the app. Used by the last
/// onboarding step and by Settings → App.
struct MobileAppsCard: View {
    static let storeURL = URL(string: "https://apps.apple.com/us/app/atlas-student-planner/id6786719011")!

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // A QR wants a light quiet zone around it; the paper background is close
            // enough in tone that a plain white plate keeps it scannable and tidy.
            Image("AppStoreQR")
                .resizable()
                .frame(width: 96, height: 96)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.md, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Text("Point your iPhone or iPad camera at the code. The same spaces, classes and tasks, on every device.")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: Self.storeURL) {
                    Image("AppStoreBadge")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .help("Open Atlas on the App Store")
            }
        }
    }
}

/// The last step of first-run setup: get Atlas onto the phone and tablet too.
/// Matches `CaptureKeyPopup`'s look; shown once, then never again.
struct MobileAppsPopup: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3").foregroundStyle(AtlasTheme.Colors.accent)
                Text("Get Atlas on your iPhone and iPad")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }

            MobileAppsCard()

            HStack {
                Spacer()
                Button("Done") { finish() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AtlasTheme.Colors.bgBase)
        // Marked on appear, not on Done: closing with Esc still counts as seen.
        .onAppear { MobileAppsOnboarding.markSeen() }
    }

    private func finish() { dismiss() }
}
