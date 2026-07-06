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
        // Drive the window in/out of true fullscreen from session state. Idempotent
        // (`FocusWindow.setFullScreen` no-ops when already in the target state), so
        // onAppear (FocusCard entry — session already true) and onChange (the "Start
        // focus" button) can both call it without double-toggling.
        .onAppear { FocusWindow.setFullScreen(focus.sessionActive) }
        .onChange(of: focus.sessionActive) { FocusWindow.setFullScreen(focus.sessionActive) }
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if focus.sessionActive { focus.endSession() }
        }
    }

    // MARK: - Landing (pre-session)

    private var landing: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)
            phaseLabel
            timerDial
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

    private var timerDial: some View {
        ZStack {
            // Subtle progress ring behind the digits.
            Circle()
                .stroke(AtlasTheme.Colors.border, lineWidth: 4)
            Circle()
                .trim(from: 0, to: focus.progress)
                .stroke(
                    AngularGradient(
                        colors: [AtlasTheme.Colors.accentDeep, AtlasTheme.Colors.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: focus.progress)

            Text(focus.timeFormatted)
                .atlasMono(size: 96, weight: .ultraLight)
                .monospacedDigit()
                .foregroundStyle(focus.isRunning
                    ? AtlasTheme.Colors.textPrimary
                    : AtlasTheme.Colors.textSecondary)
                .contentTransition(.numericText())
        }
        .frame(width: 320, height: 320)
    }

    private var cycleMeta: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(intervalsText)
                .atlasMono(size: 11)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(Capsule().strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
        .contentShape(Capsule())
    }

    private var intervalsText: String {
        let n = focus.completedWorkIntervals
        return n == 1 ? "1 focus interval done" : "\(n) focus intervals done"
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
