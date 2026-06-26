// CARRYOVER — from old Atlas prototype. Cross-platform timer logic. Restyle/adapt before use.
// Depends on old `AtlasProject` + `FocusSession` model.
import SwiftUI
import SwiftData

@MainActor @Observable
final class FocusViewModel {
    var selectedProject: AtlasProject?
    var isRunning = false
    var isOnBreak = false
    var elapsedSeconds: Int = 0
    var breakElapsedSeconds: Int = 0
    var currentSession: FocusSession?
    var pendingReflection: FocusSession? = nil

    private var timer: Timer?
    private var breakTimer: Timer?
    private var accumulatedBreakSeconds: Int = 0

    // MARK: - Formatting

    var elapsedFormatted: String { Self.hms(elapsedSeconds) }
    var breakElapsedFormatted: String { Self.hms(breakElapsedSeconds) }

    private static func hms(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Session lifecycle

    func startSession(project: AtlasProject, intention: String? = nil, context: ModelContext) {
        selectedProject = project
        let session = FocusSession(project: project)
        let trimmed = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.intention = (trimmed?.isEmpty ?? true) ? nil : trimmed
        context.insert(session)
        try? context.save()
        currentSession = session
        elapsedSeconds = 0
        breakElapsedSeconds = 0
        accumulatedBreakSeconds = 0
        isRunning = true
        isOnBreak = false
        startFocusTimer()
    }

    /// Pauses the focus timer, starts the break timer. No-op if already on break.
    func startBreak() {
        guard isRunning, !isOnBreak else { return }
        timer?.invalidate()
        timer = nil
        isOnBreak = true
        breakElapsedSeconds = 0
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.breakElapsedSeconds += 1
            }
        }
    }

    /// Stops the break timer, folds break seconds into the accumulator, restarts the focus timer.
    func endBreak() {
        guard isOnBreak else { return }
        breakTimer?.invalidate()
        breakTimer = nil
        accumulatedBreakSeconds += breakElapsedSeconds
        breakElapsedSeconds = 0
        isOnBreak = false
        startFocusTimer()
    }

    /// Pauses the timer and sets pendingReflection — does NOT yet commit/save.
    func requestEndSession() {
        if isOnBreak {
            breakTimer?.invalidate()
            breakTimer = nil
            accumulatedBreakSeconds += breakElapsedSeconds
            breakElapsedSeconds = 0
            isOnBreak = false
        }
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentSession?.endedAt = Date()
        currentSession?.totalBreakSeconds = accumulatedBreakSeconds
        pendingReflection = currentSession
    }

    /// Saves the session with optional notes, then clears state.
    func commitSession(notes: String?, context: ModelContext) {
        if let session = pendingReflection {
            session.notes = notes
            try? context.save()
        }
        pendingReflection = nil
        currentSession = nil
        accumulatedBreakSeconds = 0
    }

    /// Saves the session with nil notes (user skipped reflection).
    func discardReflection(context: ModelContext) {
        commitSession(notes: nil, context: context)
    }

    /// Backward-compatible — now delegates through the new flow.
    func stopSession(context: ModelContext) {
        requestEndSession()
        commitSession(notes: nil, context: context)
    }

    // MARK: - Internal

    private func startFocusTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }
}
