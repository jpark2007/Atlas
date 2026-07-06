import SwiftUI
import AtlasCore
import AppKit

@main
struct AtlasApp: App {
    @StateObject private var state = AppState()
    @StateObject private var auth = AuthService()
    @StateObject private var canvas = CanvasService()
    /// Server-side Canvas ICS connect client (AtlasCore) — distinct from the local
    /// token-based `CanvasService` above; Settings' feed-URL section uses this one.
    @StateObject private var canvasFeed = AtlasCore.CanvasService()
    @StateObject private var shortcuts = ShortcutStore()
    @StateObject private var googleAuth = GoogleAuthService()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(state)
                .environmentObject(auth)
                .environmentObject(canvas)
                .environmentObject(canvasFeed)
                .environmentObject(shortcuts)
                .environmentObject(googleAuth)
                // Two-way Google-Doc write-back for linked Doc-notes: the concrete
                // edge-function client, minting a valid Supabase JWT on each save.
                .environment(\.docNoteWriteBack,
                             GoogleDocWriteBackClient(accessToken: { await auth.validAccessToken() }))
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.light)
                .background(GlobalHotkeyInstaller(state: state, auth: auth))
        }
        // .hiddenTitleBar gives the transparent, full-size-content title bar (edge-to-edge
        // light content, no gray strip, no title) while KEEPING the standard traffic-light
        // controls — it does not suppress them. The buttons were actually being removed by
        // `.toolbar(.hidden, for: .windowToolbar)` in RootView, which strips the whole
        // window toolbar (controls included); that line has been removed.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // Atlas mark in the macOS menu bar — always-on quick access.
        MenuBarExtra("Atlas", image: "AtlasMenuBar") {
            AtlasMenuBarContent()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Dropdown shown from the menu-bar Atlas icon.
struct AtlasMenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button("Open Atlas") { Self.activateMainWindow() }

        // No ⌘⇧K here on purpose: a MenuBarExtra key-equivalent shadows BOTH the
        // Carbon global hotkey and the in-app capture shortcut whenever Atlas is the
        // active app, breaking ⌘⇧K. The global hotkey + in-app shortcut own that combo.
        Button("Quick Capture") {
            Self.activateMainWindow()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                state.presentCapture = true
            }
        }

        Divider()

        Button("Quit Atlas") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Bring the main Atlas window to the front (it may be hidden or behind).
    static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }
}

/// Registers the system-wide ⌘⇧K capture hotkey (Carbon, fires even when Atlas is
/// unfocused) and routes it to the same capture overlay the in-app shortcut opens.
/// The in-app ShortcutStore binding (`.atlasCaptureOverlay()`) stays in place for
/// when the app is already focused.
private struct GlobalHotkeyInstaller: View {
    /// Concrete reference types captured directly so the escaping Carbon hotkey callback
    /// never touches an `@EnvironmentObject` wrapper outside `body` (that previously
    /// tripped a fatal SwiftUI error on hotkey press).
    let state: AppState
    let auth: AuthService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                // ⌘⇧K summons a floating, non-activating capture panel OVER the current
                // app — it no longer activates Atlas or uses the in-window overlay.
                CapturePanelController.shared.configure(state: state, auth: auth)
                HotkeyService.shared.register {
                    CapturePanelController.shared.toggle()
                }
            }
    }
}

/// Routes between the auth gate and the app based on session state.
struct AppGate: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var googleAuth: GoogleAuthService
    @EnvironmentObject private var canvas: CanvasService

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AtlasTheme.Colors.bgBase)
            case .signedOut:
                SignInView()
            case .signedIn:
                RootView()
                    .onAppear { state.userName = auth.displayName }
                    .task {
                        let db = AtlasDB(session: { await auth.validSession() })
                        await state.bootstrap(db: db, userID: auth.session?.user.id)
                        // Sync Canvas once bootstrap has populated projects so matching works.
                        if canvas.isConnected {
                            await state.syncCanvas(using: canvas)
                        }
                    }
            case .offline:
                RootView()
                    .onAppear { state.userName = auth.displayName }
            }
        }
        .onAppear {
            state.attachGoogle(googleAuth)
            // Sync Canvas whenever the user connects via Settings.
            canvas.onConnected = { [weak state, weak canvas] in
                guard let state, let canvas else { return }
                Task { await state.syncCanvas(using: canvas) }
            }
        }
    }
}
