import Foundation
import Combine
import AtlasCore

/// Drives the Pomodoro focus timer AND the focus-session lifecycle.
///
/// Rebuilt from the old prototype's `FocusViewModel` as a plain `ObservableObject`
/// countdown around a `Foundation.Timer`. It stays free of AppKit — the fullscreen
/// window toggle lives in the view (`FocusView`), which observes `sessionActive`.
/// Owned app-wide by `AtlasApp` so the `MenuBarExtra` label can bind to the live
/// countdown even when Atlas isn't frontmost.
@MainActor
final class FocusViewModel: ObservableObject {

    /// Which side of the Pomodoro cycle we are on.
    enum Phase {
        case work
        case shortBreak

        var title: String {
            switch self {
            case .work:       return "Focus"
            case .shortBreak: return "Break"
            }
        }

        var durationSeconds: Int {
            switch self {
            case .work:       return 25 * 60
            case .shortBreak: return 5 * 60
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .work
    @Published private(set) var isRunning = false
    /// Seconds remaining in the current phase.
    @Published private(set) var remainingSeconds: Int = Phase.work.durationSeconds
    /// Count of completed work intervals in this run.
    @Published private(set) var completedWorkIntervals: Int = 0

    /// Whether a focus session is active — the window is (or is going) into true
    /// fullscreen work mode. Drives the in-session layout, the menu-bar countdown,
    /// and the fullscreen toggle (`FocusView` observes this).
    @Published var sessionActive = false

    /// A note the ⌘K notes-scoped palette asked Focus to open in the corner card.
    /// `FocusView` consumes it (opens the card) and clears it back to `nil`.
    @Published var noteToOpen: Note?

    private var timer: Timer?

    // MARK: - Derived display

    /// `MM:SS` countdown for the big display.
    var timeFormatted: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 0…1 progress through the current phase (elapsed fraction).
    var progress: Double {
        let total = Double(phase.durationSeconds)
        guard total > 0 else { return 0 }
        let elapsed = total - Double(remainingSeconds)
        return min(1, max(0, elapsed / total))
    }

    var phaseLabel: String { phase.title }

    var primaryButtonTitle: String { isRunning ? "Pause" : "Start" }
    var primaryButtonIcon: String { isRunning ? "pause.fill" : "play.fill" }

    // MARK: - Session lifecycle

    /// Enters a focus session and starts the countdown. `FocusView` observes
    /// `sessionActive` and drives the window into true macOS fullscreen.
    func startSession() {
        sessionActive = true
        start()
    }

    /// Ends the session: pauses the countdown and drops out of session mode.
    /// `FocusView` observes `sessionActive` and drops the window out of fullscreen.
    /// Remaining time is preserved so re-entering resumes where it left off.
    func endSession() {
        pause()
        sessionActive = false
    }

    // MARK: - Controls

    /// Toggles between running and paused for the current phase.
    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startTimer()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        stopTimer()
    }

    /// Resets the entire cycle back to a fresh 25-minute work phase.
    func reset() {
        stopTimer()
        isRunning = false
        phase = .work
        remainingSeconds = Phase.work.durationSeconds
        completedWorkIntervals = 0
    }

    /// Skips the current phase and advances to the next one (paused).
    func skipPhase() {
        advancePhase()
    }

    // MARK: - Internal

    private func startTimer() {
        stopTimer()
        // Build the timer non-scheduled and register it once in `.common` so it
        // keeps ticking through menu tracking / scrolling without double-adding.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            advancePhase()
            return
        }
        remainingSeconds -= 1
        if remainingSeconds == 0 {
            advancePhase()
        }
    }

    /// Moves to the next phase in the work↔break cycle. The next phase starts paused
    /// so the user can choose when to begin it.
    private func advancePhase() {
        stopTimer()
        isRunning = false
        switch phase {
        case .work:
            completedWorkIntervals += 1
            phase = .shortBreak
        case .shortBreak:
            phase = .work
        }
        remainingSeconds = phase.durationSeconds
    }

    deinit {
        timer?.invalidate()
    }
}
