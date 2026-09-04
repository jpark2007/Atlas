import SwiftUI
import AppKit

/// Strips the default macOS title-bar / toolbar chrome so Atlas's cream content
/// runs edge-to-edge to the very top — no gray strip, no stray toolbar button —
/// while explicitly keeping the standard traffic-light controls (close / minimize
/// / zoom) visible over the transparent bar.
///
/// NavigationSplitView re-adds its toolbar after our first pass, so we re-assert
/// the configuration a few times to win the race.
///
/// It also re-adds it later — after a body re-render, and across entering/leaving
/// true macOS fullscreen. SwiftUI calls `updateNSView` only once, at launch (this
/// view stores nothing, so SwiftUI never sees it change), so the Coordinator watches
/// the window itself — `didUpdate` plus the fullscreen notifications — and strips the
/// toolbar again whenever AppKit puts one back.
struct WindowConfigurator: NSViewRepresentable {
    /// bgBase (paper #f2efe6) — the window's background and the color we repaint
    /// AppKit's own white title-bar backing with.
    private static let paper = NSColor(srgbRed: 0xf2/255, green: 0xef/255, blue: 0xe6/255, alpha: 1)

    func makeCoordinator() -> Coordinator { Coordinator(configure: configure, hasDrifted: hasDrifted) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.observe(view)
        context.coordinator.reassert(delays: [0.0, 0.15, 0.4, 1.0])
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
        window.backgroundColor = Self.paper
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

        paperTitlebarBackings(window)
    }

    /// Repaints AppKit's own title-bar backing views paper.
    ///
    /// `NSSplitView` (what `NavigationSplitView` is built on) parks an
    /// `NSTitlebarBackgroundView` over the top 32pt of the window — one as a sibling
    /// drawn ABOVE the detail pane's wrapper, one inside the sidebar's. Both are
    /// layer-backed with a hard `#ffffff`, normally `isHidden = true`. AppKit un-hides
    /// them whenever it decides the title bar needs a solid backing (a toolbar cycling
    /// on and off, a pane re-laying out), and because they are AppKit siblings painted
    /// over the SwiftUI hosting view, the detail column's
    /// `bgBase.ignoresSafeArea(edges: .top)` in `RootView` cannot cover them — that
    /// paint is *underneath*. That is the white band.
    ///
    /// Rather than fight the un-hide, we make the view harmless: give it the paper
    /// color, so if AppKit shows it, it shows paper. No timers, no polling — this runs
    /// on the same passes as the rest of `configure`.
    private func paperTitlebarBackings(_ window: NSWindow) {
        guard let root = window.contentView?.superview else { return }
        func walk(_ view: NSView) {
            if view is NSVisualEffectView { return }   // don't repaint materials
            if String(describing: type(of: view)).hasSuffix("TitlebarBackgroundView") {
                view.wantsLayer = true
                view.layer?.backgroundColor = Self.paper.cgColor
                return
            }
            view.subviews.forEach(walk)
        }
        walk(root)
    }

    /// True when any property `configure` asserts has drifted back to an AppKit
    /// default. Cheap enough to run on every `didUpdate` tick (a handful of compares).
    ///
    /// This used to be `window.toolbar != nil` alone, which meant a title bar that
    /// turned opaque WITHOUT a toolbar being re-attached was never re-asserted —
    /// exactly the case behind the white band after saving a task description.
    private func hasDrifted(_ window: NSWindow) -> Bool {
        window.toolbar != nil
            || !window.titlebarAppearsTransparent
            || window.titleVisibility != .hidden
            || !window.styleMask.contains(.fullSizeContentView)
            || window.titlebarSeparatorStyle != .none
    }

    // NOTE: there is deliberately no work here. `WindowConfigurator` stores nothing,
    // so SwiftUI treats every instance as identical and calls `updateNSView` exactly
    // once, at launch — never again, not even when AppState mutations re-resolve
    // RootView's body. Anything hung off this hook can't defend the title bar; the
    // `didUpdate` observer in the Coordinator does that instead.
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Re-asserts the window chrome across fullscreen transitions. macOS re-shows the
    /// titlebar and NavigationSplitView re-attaches its toolbar when entering/leaving
    /// fullscreen; without this the top of the window flashes an opaque white bar.
    final class Coordinator {
        private let configure: (NSWindow) -> Void
        private let hasDrifted: (NSWindow) -> Bool
        private weak var view: NSView?
        private var tokens: [NSObjectProtocol] = []

        private var pending = false

        init(configure: @escaping (NSWindow) -> Void, hasDrifted: @escaping (NSWindow) -> Bool) {
            self.configure = configure
            self.hasDrifted = hasDrifted
        }

        /// Re-applies the chrome across the launch-time passes, when SwiftUI is still
        /// building the split view and re-attaching its toolbar. Coalesced so repeated
        /// calls can't pile up timers.
        func reassert(delays: [TimeInterval]) {
            guard !pending else { return }
            pending = true
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    if delay == delays.last { self.pending = false }
                    guard let window = self.view?.window else { return }
                    self.configure(window)
                }
            }
        }

        func observe(_ view: NSView) {
            self.view = view
            let center = NotificationCenter.default
            // willEnter fires before the transition paints; did* fires after the
            // toolbar has been re-attached. Re-configure on both to keep the strip
            // paper-colored and toolbar-free throughout the animation.
            for name in [NSWindow.willEnterFullScreenNotification,
                         NSWindow.didEnterFullScreenNotification,
                         NSWindow.willExitFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self, let window = self.view?.window,
                          note.object as? NSWindow == window else { return }
                    self.configure(window)
                }
                tokens.append(token)
            }

            // The one hook that actually catches the toolbar coming back. AppKit sends
            // every window an `update()` once per event-loop pass, so this fires right
            // after NavigationSplitView re-installs its NSToolbar. It does that after a
            // body re-render (observed: a stray sidebar-toggle button appears in the
            // titlebar and the detail content drops ~20pt). SwiftUI does NOT call
            // `updateNSView` for those re-renders — WindowConfigurator stores nothing, so
            // SwiftUI sees an unchanged view and skips it — which is why hanging the
            // re-assert off `updateNSView` did nothing. `hasDrifted` keeps the common
            // case to a handful of property compares — and, unlike the `toolbar != nil`
            // test it replaces, it also catches a title bar that goes opaque with no
            // toolbar involved (the white band after saving a task description).
            let updateToken = center.addObserver(forName: NSWindow.didUpdateNotification,
                                                 object: nil, queue: .main) { [weak self] note in
                guard let self, let window = self.view?.window,
                      note.object as? NSWindow == window, self.hasDrifted(window) else { return }
                self.configure(window)
            }
            tokens.append(updateToken)
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
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
