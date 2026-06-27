import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var state = AppState()
    @StateObject private var auth = AuthService()
    @StateObject private var canvas = CanvasService()
    @StateObject private var shortcuts = ShortcutStore()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(state)
                .environmentObject(auth)
                .environmentObject(canvas)
                .environmentObject(shortcuts)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
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
