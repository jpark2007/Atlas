import SwiftUI
import AppKit

/// Strips the default macOS title-bar / toolbar chrome so Atlas's dark content
/// runs edge-to-edge to the very top — no gray strip, no stray toolbar button.
/// The traffic-light buttons still appear (on hover) over the transparent bar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(srgbRed: 0x16/255, green: 0x13/255, blue: 0x0f/255, alpha: 1) // bgBase
            // Drop any toolbar NavigationSplitView attaches (the gray bar's source).
            window.toolbar = nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
