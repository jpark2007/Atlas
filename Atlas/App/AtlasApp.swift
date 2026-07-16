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
    /// Focus-session + Pomodoro state. Owned here (not inside FocusView) so the
    /// MenuBarExtra — a separate Scene — can bind to the same live countdown.
    @StateObject private var focus = FocusViewModel()
    /// User-adjustable global text scale (Settings → General → Appearance).
    /// 1.0 = default; see `AtlasTextScaleKey` in AtlasCore/Theme.swift.
    @AppStorage("appearance.textScale") private var textScale: Double = 1.0

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(state)
                .environmentObject(auth)
                .environmentObject(canvas)
                .environmentObject(canvasFeed)
                .environmentObject(shortcuts)
                .environmentObject(googleAuth)
                .environmentObject(focus)
                // Two-way Google-Doc write-back for linked Doc-notes: the concrete
                // edge-function client, minting a valid Supabase JWT on each save.
                .environment(\.docNoteWriteBack,
                             GoogleDocWriteBackClient(accessToken: { await auth.validAccessToken() }))
                // On-demand "Sync now" pull for a single linked Doc-note reference.
                .environment(\.referencePull,
                             ReferencePullClient(accessToken: { await auth.validAccessToken() }))
                .environment(\.atlasTextScale, CGFloat(textScale))
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

        // Menu-bar item: the Atlas mark normally; the live MM:SS countdown while a
        // focus session runs — visible even when Atlas isn't frontmost. Clicking it
        // opens the calendar popup (mini-month + agenda) with session controls on
        // top while a session runs (see AtlasMenuBarContent). `.window` style so
        // the item can host a real view instead of menu rows.
        MenuBarExtra {
            AtlasMenuBarContent(focus: focus)
                .environmentObject(state)
                .preferredColorScheme(.light)   // paper theme — don't follow a dark menu bar
        } label: {
            FocusMenuLabel(focus: focus)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu-bar label: the live `MM:SS` countdown while a focus session is active,
/// otherwise the Atlas mark. `@ObservedObject` so it re-renders each tick.
struct FocusMenuLabel: View {
    @ObservedObject var focus: FocusViewModel

    var body: some View {
        if focus.sessionActive {
            Text(focus.timeFormatted)
        } else {
            Image("AtlasMenuBar")
        }
    }
}

/// The menu-bar calendar popup (`.window` MenuBarExtra): the dashboard's
/// mini-month + agenda instrument, glanceable over ANY app, with the focus
/// session controls stacked on top while a session runs.
struct AtlasMenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var focus: FocusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if focus.sessionActive {
                sessionBlock
                Divider().overlay(AtlasTheme.Colors.hairline)
            }

            MiniMonthAgenda(
                onOpenCalendar: {
                    Self.closePopup()
                    Self.activateMainWindow()
                    state.route = .calendar
                },
                agendaLimit: 8   // a stacked day must not grow the popup unbounded
            )

            Divider().overlay(AtlasTheme.Colors.hairline)

            footerRow
        }
        .padding(16)
        .frame(width: 340)
        .background(AtlasTheme.Colors.bgBase)
    }

    /// Focus session controls — the same actions the old menu rows offered.
    private var sessionBlock: some View {
        HStack(spacing: 10) {
            Text("FOCUS · \(focus.phaseLabel.uppercased()) · \(focus.timeFormatted)")
                .atlasMono(size: 11, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button(focus.isRunning ? "Pause" : "Resume") { focus.toggle() }
                .buttonStyle(.plain)
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            Button("End") {
                focus.endSession()
                // Belt-and-suspenders: drop fullscreen directly too, since this can
                // fire while Atlas isn't frontmost. Idempotent with FocusView's own
                // sessionActive→setFullScreen sync.
                FocusWindow.setFullScreen(false)
            }
            .buttonStyle(.plain)
            .atlasFont(size: 12, weight: .semibold, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
    }

    /// Open / capture / quit — the old menu rows as quiet mono buttons.
    // No ⌘⇧K equivalent here on purpose: a MenuBarExtra key-equivalent shadows BOTH
    // the Carbon global hotkey and the in-app capture shortcut whenever Atlas is the
    // active app, breaking ⌘⇧K. The global hotkey + in-app shortcut own that combo.
    private var footerRow: some View {
        HStack(spacing: 14) {
            footerButton("Open Atlas") {
                Self.closePopup()
                Self.activateMainWindow()
            }
            footerButton("Quick Capture") {
                Self.closePopup()
                Self.activateMainWindow()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    state.presentCapture = true
                }
            }
            Spacer()
            footerButton("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")   // parity with the old menu row's ⌘Q
        }
    }

    /// A `.window` MenuBarExtra panel doesn't auto-dismiss on button clicks the
    /// way menu rows did — close it before switching to the main window, or it
    /// stays floating over the app. The panel is key while its button is clicked.
    private static func closePopup() {
        NSApp.keyWindow?.close()
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
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
                // Gate the real UI on a VERIFIED user-id match: render RootView only
                // once `bootstrap` has loaded THIS user's data (loadedUserID == the
                // authenticated id). Until then show the neutral loading spinner —
                // never the seed MockData or a previous account's still-in-memory
                // rows, which would otherwise flash for the frames before `loadAll()`
                // returns. The bootstrap `.task` runs regardless (attached to the
                // container, not the gated RootView) so the load always kicks off.
                Group {
                    if state.loadedUserID == auth.session?.user.id {
                        RootView()
                            // Re-pull cross-device preferences whenever Atlas comes to the
                            // foreground (server wins). `state.db` is set by bootstrap; nil
                            // before it lands, in which case this no-ops.
                            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                                guard let db = state.db else { return }
                                Task { await state.settingsSync.pullAndApply(db: db) }
                            }
                    } else {
                        ProgressView().controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AtlasTheme.Colors.bgBase)
                    }
                }
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
        // On sign-out wipe every per-user in-memory model + the bootstrap/gate
        // bookkeeping, so a subsequent sign-in (same OR different account) can never
        // render the previous user's still-in-memory rows — the render gate stays
        // closed until the next account's own `loadAll()` lands.
        .onChange(of: auth.state) { _, newValue in
            if newValue == .signedOut { state.resetForSignOut() }
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
