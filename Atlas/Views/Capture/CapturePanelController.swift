import AppKit
import SwiftUI

/// Hosts the quick-capture command bar in a floating, **non-activating** `NSPanel`,
/// so the global ⌘⇧K hotkey can summon it OVER whatever app the user is in — without
/// pulling them into Atlas (the old behavior was `NSApp.activate` + an in-window overlay).
///
/// It reuses the existing `CaptureCommandBar` (same AI routing / fallback / dictation),
/// just rendered in `inPanel` mode (no full-bleed scrim). Click-outside and Esc are
/// handled here via event monitors.
@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var state: AppState?
    private var auth: AuthService?

    /// Inject the live app objects once (from `GlobalHotkeyInstaller.onAppear`).
    func configure(state: AppState, auth: AuthService) {
        self.state = state
        self.auth = auth
    }

    func toggle() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    func show() {
        guard let state, let auth else { return }
        let panel = panel ?? makePanel(state: state, auth: auth)
        self.panel = panel
        reposition(panel)
        // Become key so the text field receives keystrokes — a non-activating panel
        // can be key WITHOUT making Atlas the frontmost app.
        panel.makeKeyAndOrderFront(nil)
        installMonitors(panel: panel)
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
        // Drop the cached panel so the next summon rebuilds the hosted CaptureCommandBar:
        // its `.onAppear` re-fires (re-focusing the field) and `@State text` resets. Without
        // this, a reused panel never re-focuses the field after the first capture.
        panel = nil
    }

    private func makePanel(state: AppState, auth: AuthService) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let root = CaptureCommandBar(
            isPresented: Binding(get: { true }, set: { [weak self] show in if !show { self?.hide() } }),
            atlasAI: AtlasAI(session: { auth.session }),
            inPanel: true
        )
        .environmentObject(state)
        .environmentObject(auth)

        let hosting = NSHostingController(rootView: AnyView(root))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentViewController = hosting
        return panel
    }

    /// Center horizontally near the top of whichever screen the cursor is on.
    private func reposition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installMonitors(panel: NSPanel) {
        removeMonitors()
        // Click in another app → dismiss.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        // Esc → dismiss (the bar's own Esc handling is disabled in panel mode).
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // kVK_Escape
                Task { @MainActor in self?.hide() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }
}
