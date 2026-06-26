import Foundation
import Combine

/// Drives the Pomodoro focus timer.
///
/// Ported from the old prototype's `FocusViewModel` (carryover) but rebuilt as a
/// plain `ObservableObject` countdown around a `Foundation.Timer`. It does NOT
/// touch `AppState`, SwiftData, or any AppKit/menu-bar code — purely the timing
/// logic for a 25-minute work / 5-minute break cycle.
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
