import AppKit
import SwiftUI

/// Hosts the quick-capture command bar in a floating NSPanel summoned by ⌘⇧K.
///
/// macOS only routes keyboard events to the active application's key window, so
/// Atlas must become the active app for the text field to accept typing. The panel
/// is ordered front first (so there is a visible Atlas window during activation),
/// then NSApp activates, then the main Atlas window is sent to the back so it
/// doesn't cover the user's work. On dismiss the previous app is restored.
///
/// Click-outside and Esc are handled here via event monitors.
// NSPanel with .borderless styleMask returns false from canBecomeKey by default,
// causing makeKeyAndOrderFront to silently fail. Override to fix that.
private final class CapturePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var state: AppState?
    private var auth: AuthService?
    private var previousApp: NSRunningApplication?

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
        previousApp = NSWorkspace.shared.frontmostApplication

        let p = self.panel ?? makePanel(state: state, auth: auth)
        self.panel = p
        reposition(p)

        // Show the panel before activating so macOS has a visible Atlas window
        // to anchor the activation to — activating with no visible windows causes
        // macOS to immediately hand focus back to the previous app.
        p.orderFront(nil)
        NSApp.activate()

        // After activation macOS restores the previously-key Atlas window (the
        // main WindowGroup), which would cover the user's work. One run-loop pass
        // later: push all regular windows behind everything, then claim key status
        // for the panel. The panel sits at .floating level so it stays on top.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for w in NSApp.windows where !(w is NSPanel) {
                w.orderBack(nil)
            }
            self.panel?.makeKeyAndOrderFront(nil)
        }
        installMonitors(panel: p)
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
        // Drop the cached panel so the next summon rebuilds the hosted CaptureCommandBar:
        // its `.onAppear` re-fires (re-focusing the field) and `@State text` resets. Without
        // this, a reused panel never re-focuses the field after the first capture.
        panel = nil
        previousApp?.activate()
        previousApp = nil
    }

    private func makePanel(state: AppState, auth: AuthService) -> NSPanel {
        let panel = CapturePanelWindow(
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
