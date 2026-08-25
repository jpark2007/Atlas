import Foundation
import Sparkle

/// Sparkle 2 auto-updates for the direct-download DMG channel.
///
/// Owns the one `SPUStandardUpdaterController` for the process. Created with
/// `startingUpdater: true`, so background checks begin at launch and Sparkle
/// presents its own native update sheet — no custom UI, no driver of our own.
/// Feed URL, public key and the automatic-check default all come from Info.plist
/// (SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks — see project.yml).
///
/// The app is NOT sandboxed (Atlas.entitlements deliberately leaves App Sandbox
/// off for the Carbon global hotkey), so this is Sparkle's standard integration:
/// no XPC installer service, no extra entitlements.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors the updater's "download and install in the background" preference so
    /// a SwiftUI `Toggle` can bind to it. Sparkle persists the value itself.
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates

        #if DEBUG
        // Fail loudly in development if the signing key was never generated: with the
        // placeholder in place Sparkle can verify nothing, so every update would be
        // rejected at install time — silently, from the user's point of view.
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == "PLACEHOLDER_ED_PUBLIC_KEY" {
            print("""
            ⚠️ [Sparkle] SUPublicEDKey is still PLACEHOLDER_ED_PUBLIC_KEY.
               Run Sparkle's `generate_keys` once, then paste the printed public key
               into project.yml (targets → Atlas → info → properties → SUPublicEDKey)
               and re-run `xcodegen generate`. Updates cannot be verified until then.
            """)
        }
        #endif
    }

    /// "Check for updates now" — shows Sparkle's native sheet (including the
    /// "you're up to date" case).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
