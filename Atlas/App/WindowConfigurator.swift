import SwiftUI
import AppKit

/// Strips the default macOS title-bar / toolbar chrome so Atlas's cream content
/// runs edge-to-edge to the very top — no gray strip, no stray toolbar button —
/// while explicitly keeping the standard traffic-light controls (close / minimize
/// / zoom) visible over the transparent bar.
///
/// NavigationSplitView re-adds its toolbar after our first pass, so we re-assert
/// the configuration a few times to win the race.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        for delay in [0.0, 0.15, 0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let window = view?.window else { return }
                configure(window)
            }
        }
        return view
    }

    private func configure(_ window: NSWindow) {
        // Keep the window titled + closable/miniaturizable/resizable so the standard
        // traffic-light controls exist AND are enabled — a hidden-title-bar style can
        // strip these flags, which leaves the red/yellow/green buttons missing.
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Do NOT make the whole body drag the window — it hijacks content drags such
        // as calendar drag-to-schedule (you'd move the window instead of the event).
        // The transparent title-bar strip at the top still drags the window normally.
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(srgbRed: 0xf2/255, green: 0xef/255, blue: 0xe6/255, alpha: 1) // bgBase (paper #f2efe6)
        // Kill the toolbar NavigationSplitView attaches (the gray bar's source).
        window.toolbar = nil
        // Hide the 1px separator line under the (now transparent) titlebar.
        window.titlebarSeparatorStyle = .none

        // Explicitly restore the standard macOS window controls (red/yellow/green).
        // Removing the toolbar / hiding the title bar can leave these hidden, so we
        // un-hide them every pass to guarantee close / minimize / zoom are present.
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}

/// Drives the app's main window in and out of true macOS fullscreen for Focus mode.
///
/// Idempotent: it only calls `toggleFullScreen` when the window's current state
/// differs from the requested one, so it is safe to call from onAppear / onChange /
/// the menu bar (and after the window itself has already left fullscreen) without
/// double-toggling.
enum FocusWindow {
    /// Toggles the main window to `on`, returning `true` only when it actually toggled
    /// (i.e. the window wasn't already in the requested state). Callers use the return
    /// to record whether Focus *itself* drove the window into fullscreen, so ending a
    /// session never yanks a user out of a fullscreen they chose themselves.
    @MainActor
    @discardableResult
    static func setFullScreen(_ on: Bool) -> Bool {
        guard let window = mainWindow() else { return false }
        let isFull = window.styleMask.contains(.fullScreen)
        guard on != isFull else { return false }
        window.toggleFullScreen(nil)
        return true
    }

    /// True when `object` is the app's main content window — lets `didExitFullScreen`
    /// observers ignore unrelated windows (capture panel, menu-bar item).
    @MainActor
    static func isMain(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return window == mainWindow()
    }

    /// The main content window (not the capture panel / menu-bar item). Mirrors the
    /// `canBecomeMain` pick used by `AtlasMenuBarContent.activateMainWindow`.
    @MainActor
    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain }
    }
}
