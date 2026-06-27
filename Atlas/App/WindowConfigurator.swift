import SwiftUI
import AppKit

/// Strips the default macOS title-bar / toolbar chrome so Atlas's dark content
/// runs edge-to-edge to the very top — no gray strip, no stray toolbar button.
/// The traffic-light buttons still appear (on hover) over the transparent bar.
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
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(srgbRed: 0x16/255, green: 0x13/255, blue: 0x0f/255, alpha: 1) // bgBase
        // Kill the toolbar NavigationSplitView attaches (the gray bar's source).
        window.toolbar = nil
        // Hide the 1px separator line under the (now transparent) titlebar.
        window.titlebarSeparatorStyle = .none
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}
