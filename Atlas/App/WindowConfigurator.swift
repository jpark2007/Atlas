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
        window.backgroundColor = NSColor(srgbRed: 0xfb/255, green: 0xfa/255, blue: 0xf7/255, alpha: 1) // bgBase (cream)
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
