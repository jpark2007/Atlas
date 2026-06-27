import SwiftUI
import AppKit

@main
struct AtlasApp: App {
    @StateObject private var state = AppState()
    @StateObject private var auth = AuthService()
    @StateObject private var canvas = CanvasService()
    @StateObject private var shortcuts = ShortcutStore()
    @StateObject private var googleAuth = GoogleAuthService()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(state)
                .environmentObject(auth)
                .environmentObject(canvas)
                .environmentObject(shortcuts)
                .environmentObject(googleAuth)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .background(GlobalHotkeyInstaller())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Registers the system-wide ⌘⇧K capture hotkey (Carbon, fires even when Atlas is
/// unfocused) and routes it to the same capture overlay the in-app shortcut opens.
/// The in-app ShortcutStore binding (`.atlasCaptureOverlay()`) stays in place for
/// when the app is already focused.
private struct GlobalHotkeyInstaller: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                HotkeyService.shared.register {
                    NSApp.activate(ignoringOtherApps: true)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        state.presentCapture = true
                    }
                }
            }
    }
}

/// Routes between the auth gate and the app based on session state.
struct AppGate: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var state: AppState

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
                        let db = AtlasDB(session: { auth.session })
                        await state.bootstrap(db: db)
                    }
            case .offline:
                RootView()
                    .onAppear { state.userName = auth.displayName }
            }
        }
    }
}
