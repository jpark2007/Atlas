import SwiftUI
import AppKit
import AtlasCore

/// Focus mode. Two states, both driven by the app-wide `FocusViewModel`:
///
///  • **Landing** (no session) — the big Pomodoro dial with a single "Start focus"
///    CTA. Reached from the sidebar Focus item.
///  • **In-session** — the window is in true macOS fullscreen; the timer shrinks to
///    a corner and the centre becomes the notes work surface. ⌘K opens the command
///    palette scoped to notes; the "New" note and any picked note open in the
///    chromeless `NoteCardOverlay` corner card (doc-linked notes keep two-way
///    write-back for free through `NoteEditorView`).
struct FocusView: View {
    @EnvironmentObject private var focus: FocusViewModel

    /// The note currently open in the corner card (picked via ⌘K or the notes list).
    @State private var editingNote: Note?

    /// True only when Focus *itself* drove the window into fullscreen (it was windowed
    /// when the session started). Gates the auto-exit on End so we never yank a user out
    /// of a fullscreen they chose themselves (window already fullscreen at session start).
    @State private var didEnterFullScreen = false

    var body: some View {
        ZStack {
            AtlasTheme.Colors.bgBase.ignoresSafeArea()

            if focus.sessionActive {
                sessionSurface.transition(.opacity)
            } else {
                landing.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: focus.sessionActive)
        // Only ever ENTER fullscreen for a session — never force-exit from the landing,
        // so opening the Focus tab while the user is in their own fullscreen doesn't yank
        // them out. Idempotent (`setFullScreen` no-ops when already in the target state).
        .onAppear {
            if focus.sessionActive, FocusWindow.setFullScreen(true) { didEnterFullScreen = true }
        }
        .onChange(of: focus.sessionActive) { _, active in
            if active {
                if FocusWindow.setFullScreen(true) { didEnterFullScreen = true }
            } else {
                // Only drop fullscreen if Focus put us there; if the window was already
                // fullscreen at session start, leave the user's fullscreen untouched.
                if didEnterFullScreen { FocusWindow.setFullScreen(false) }
                didEnterFullScreen = false
            }
        }
        // A ⌘K note pick (notes scope) hands the note off here → open the corner card.
        // Keyed off the id because `Note` isn't Equatable.
        .onChange(of: focus.noteToOpen?.id) { _, _ in
            if let note = focus.noteToOpen {
                editingNote = note
                focus.noteToOpen = nil
            }
        }
        // If the window leaves fullscreen by ANY route (green button, ⌃⌘F, or our own
        // toggle), end the session so we never sit in the corner-timer layout while
        // windowed. Fires on *did*Exit — `.fullScreen` is already cleared — so the
        // onChange → setFullScreen(false) that follows is a guaranteed no-op (no loop).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard FocusWindow.isMain(note.object) else { return }
            if focus.sessionActive { focus.endSession() }
        }
    }

    // MARK: - Landing (pre-session)

    private var landing: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)
            phaseLabel
            timerType
            landingControls
            cycleMeta
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: focus.isRunning)
    }

    private var landingControls: some View {
        HStack(spacing: 16) {
            // Primary CTA — enter the fullscreen session.
            Button(action: focus.startSession) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Start focus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .overlay(Capsule().strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Enter fullscreen focus")

            // Reset — secondary, outlined circular control.
            Button(action: focus.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: AtlasTheme.rule))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reset the cycle")
        }
    }

    // MARK: - In-session surface

    private var sessionSurface: some View {
        // The full-page notes surface is the work surface; the timer floats in a
        // corner and picked/new notes open in the bottom-trailing corner card.
        NotesListView(onOpen: { editingNote = $0 })
            .overlay(alignment: .bottomLeading) { cornerTimer.padding(20) }
            .overlay(alignment: .bottomTrailing) {
                if let note = editingNote {
                    NoteCardOverlay(note: note) { editingNote = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: editingNote?.id)
            // Esc: close the corner card first, otherwise end the session. The command
            // palette (a separate overlay) captures its own Esc while open, so it never
            // reaches here — matching "palette closes first, second Esc exits Focus".
            .onExitCommand {
                if editingNote != nil {
                    editingNote = nil
                } else {
                    focus.endSession()
                }
            }
    }

    /// Compact instrument-outline timer for the in-session corner (Phase-1 language:
    /// mono numerals, ink outline, flat paper fill — no card chrome).
    private var cornerTimer: some View {
        HStack(spacing: 12) {
            Text(focus.phaseLabel.uppercased())
                .atlasMono(size: 10, weight: .bold)
                .tracking(1.5)
                .foregroundStyle(isBreak ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)

            Text(focus.timeFormatted)
                .atlasMono(size: 22, weight: .regular)
                .monospacedDigit()
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .contentTransition(.numericText())

            Divider().frame(height: 18).overlay(AtlasTheme.Colors.border)

            cornerButton(focus.isRunning ? "pause.fill" : "play.fill") { focus.toggle() }
                .help(focus.isRunning ? "Pause" : "Resume")
            cornerButton("forward.end.fill") { focus.skipPhase() }
                .help(isBreak ? "Skip to focus" : "Skip to break")
            cornerButton("xmark") { focus.endSession() }
                .help("End session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(AtlasTheme.Colors.bgBase))
        .overlay(Capsule().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: AtlasTheme.rule))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func cornerButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared pieces

    private var phaseLabel: some View {
        // Caps treatment inlined: atlasCapsLabel() bakes its own foreground nearest the
        // Text, which would kill the break-phase accent (same trap as WeekColumnHeader).
        Text("— \(focus.phaseLabel.uppercased()) —")
            .atlasMono(size: 11, weight: .bold)
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(isBreak ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
    }

    /// Plain type on paper — the dashboard-clock language. Huge mono digits with
    /// a clay colon, a thin clay progress hairline beneath; no ring, no box.
    private var timerType: some View {
        VStack(spacing: 26) {
            digitsRow
            progressHairline
        }
    }

    private var digitsRow: some View {
        // Split MM:SS so the colon carries the clay accent, like the dashboard clock.
        let parts = focus.timeFormatted.split(separator: ":", maxSplits: 1).map(String.init)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            bigDigits(parts.first ?? "")
            Text(":")
                .atlasMono(size: 96, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.accent)
            bigDigits(parts.count > 1 ? parts[1] : "")
        }
    }

    private func bigDigits(_ s: String) -> some View {
        Text(s)
            .atlasMono(size: 96, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .contentTransition(.numericText())
    }

    private var progressHairline: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(AtlasTheme.Colors.border)
            Rectangle().fill(AtlasTheme.Colors.accent)
                .scaleEffect(x: focus.progress, anchor: .leading)
                .animation(.linear(duration: 0.3), value: focus.progress)
        }
        .frame(width: 320, height: 2)
    }

    private var cycleMeta: some View {
        Text(intervalsText)
            .atlasMono(size: 11, weight: .medium)
            .tracking(1.2)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    private var intervalsText: String {
        let n = focus.completedWorkIntervals
        return n == 1 ? "1 INTERVAL DONE" : "\(n) INTERVALS DONE"
    }

    private var isBreak: Bool { focus.phase == .shortBreak }
}

#if DEBUG
#Preview {
    FocusView()
        .environmentObject(AppState())
        .environmentObject(FocusViewModel())
        .frame(width: 900, height: 640)
}
#endif
