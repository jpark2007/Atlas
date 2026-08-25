import AppKit
import AtlasCore
import SwiftUI

/// Hosts the quick-capture command bar in a floating NSPanel summoned by ⌥Space.
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

    /// The screen centre-x and top-edge y this panel is pinned to, set once per summon.
    /// Assigning it re-places the panel immediately.
    var anchor: (centerX: CGFloat, top: CGFloat)? {
        didSet { setFrame(frame, display: false) }
    }

    /// Re-derive the origin from `anchor` on EVERY frame change.
    ///
    /// `NSHostingController` with `.intrinsicContentSize` collapses the window to 0×0
    /// the moment it becomes the content view controller and only sizes it once SwiftUI
    /// has laid out — so the size the panel is *placed* with is never the size it ends
    /// up at, and whichever corner AppKit keeps during that resize is not ours to pick.
    /// Pinning here makes placement size-independent: the top edge stays put (result
    /// cards grow the bar DOWNWARD) and the bar stays centred once its width settles.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard let anchor else { return super.setFrame(frameRect, display: flag) }
        super.setFrame(NSRect(x: (anchor.centerX - frameRect.width / 2).rounded(),
                              y: anchor.top - frameRect.height,
                              width: frameRect.width,
                              height: frameRect.height),
                       display: flag)
    }
}

@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    private var panel: CapturePanelWindow?
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
        guard let state, let auth else {
            AtlasLog.append("Capture panel show() skipped — app objects not configured")
            return
        }
        AtlasLog.append("Capture panel show()")
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

    /// Dismiss because the user clicked a result row to open that item: Atlas
    /// itself becomes the front app, not whatever they came from.
    ///
    /// This goes through the NORMAL `hide()` so the panel, monitors and cached
    /// hosting controller tear down identically — it only clears `previousApp`
    /// first, because `hide()`'s reactivation would immediately push Atlas back
    /// behind the app the user summoned from, undoing the handoff. `show()` also
    /// deliberately ordered the main window to the back, so bring it forward again.
    func hideForItemHandoff() {
        previousApp = nil
        hide()
        AtlasMenuBarContent.activateMainWindow()
    }

    private func makePanel(state: AppState, auth: AuthService) -> CapturePanelWindow {
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
        // The SwiftUI bar draws its own soft shadow; a window shadow on the transparent
        // padded content renders as a hard boxy halo, so leave it off.
        panel.hasShadow = false
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
    ///
    /// This only records the anchor — `CapturePanelWindow.setFrame` applies it, now and
    /// again on every later resize. It must not compute an origin from `panel.frame.size`:
    /// at this point the hosting controller has collapsed the panel to 0×0, so the old
    /// arithmetic put the panel's LEFT edge on the screen's centre line (and its BOTTOM
    /// edge at the intended top), leaving the bar sitting half a width right of centre.
    private func reposition(_ panel: CapturePanelWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.anchor = (centerX: visible.midX, top: visible.maxY - 120)
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
