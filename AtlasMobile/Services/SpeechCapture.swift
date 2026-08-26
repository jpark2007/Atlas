import Foundation
import Speech
import AVFoundation

/// On-device dictation for the Capture screen (iOS). Mirrors the Mac
/// `SpeechCaptureService` lifecycle, adapted for iOS permissions
/// (`AVAudioApplication`/`AVAudioSession`) and publishing a live input `level`
/// for the waveform. NEVER auto-listens — `start()` is called only when the mic
/// is tapped (or an `atlas://capture?mic=1` deep link fires).
///
/// A recognition TASK ends on its own — Apple finalizes after a silence gap and
/// caps a task at roughly a minute — but a SESSION does not. When a task
/// finalizes while the user is still listening, its words are banked and a fresh
/// task is started on the same live audio engine, so a breath or a pause never
/// resets the transcript or produces a second capture. The session ends when the
/// user taps stop — or, as a safety cap, after a full minute with no new words.
@MainActor
final class SpeechCapture: ObservableObject {

    enum State: Equatable {
        case idle          // ready, not listening
        case preparing     // asking for permission / starting the engine
        case listening     // mic live, transcript streaming
        case denied        // mic and/or speech permission refused
        case unavailable   // recognizer unavailable (locale/device/offline unsupported)
    }

    @Published private(set) var state: State = .idle
    /// Banked segments plus the live one — the whole dictation so far.
    @Published private(set) var transcript: String = ""
    /// Smoothed input level, 0…1 — drives the waveform bars.
    @Published private(set) var level: CGFloat = 0

    /// Fired once when dictation ends on its own (the session could not be kept
    /// alive) while still listening — a manual `stop()` never fires it. Carries the
    /// accumulated transcript so the caller can route it through the same flow as
    /// the Stop button.
    var onFinish: ((String) -> Void)?

    var isListening: Bool { state == .listening }

    /// The most one capture can hold, matching `CaptureView.maxLength`, the Mac and
    /// the server. Dictation stops growing here rather than building a doomed dump.
    static let maxLength = 20_000

    /// Safety cap: a session with no NEW words for this long ends itself, exactly as
    /// if the user had tapped stop. Keyed off the transcript growing — not the clock,
    /// not audio buffers (a silent room still delivers them) and not a task roll
    /// (which happens *because* of silence) — so a long thinking pause is safe.
    private static let silenceLimit: TimeInterval = 60

    /// How long the words must sit still before the running task is rolled on
    /// purpose. On-device recognition on a buffer request that is never ended
    /// frequently NEVER reports `isFinal` — it just ends the utterance internally and
    /// starts the next partial from scratch, overwriting `segment`. So banking is
    /// driven from here instead of from a signal iOS may never send. 1.8s sits above
    /// an ordinary mid-sentence breath (well under a second) so a roll can't clip a
    /// trailing word, and below the pause the recognizer itself treats as the end of
    /// an utterance — the window in which words used to be lost.
    private static let rollIdle: TimeInterval = 1.8
    /// How often idleness is checked. Fine enough that the roll lands close to
    /// `rollIdle`, coarse enough to cost nothing.
    private static let rollTick: TimeInterval = 0.25

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    /// The request the audio tap feeds. Boxed because the tap runs on the realtime
    /// audio thread while a transparent restart swaps the request on the main actor.
    private let feed = RequestFeed()
    private var task: SFSpeechRecognitionTask?
    /// Words from tasks that already finalized this session.
    private var banked = ""
    /// Words from the task currently running.
    private var segment = ""
    /// Consecutive task rolls that produced no words. A task started mid-pause
    /// hears silence and finalizes almost instantly, so these are the NORMAL shape
    /// of a thinking pause — they never end the session, they only slow the
    /// restarts down once they pile up.
    private var silentRolls = 0
    /// Consecutive refusals to start a task. One is transient; a run of them means
    /// the recognizer genuinely cannot continue.
    private var failedStarts = 0
    /// How many rapid silent rolls to allow before backing off, and how many
    /// failed starts to allow before giving up.
    private static let retryBudget = 5
    /// Spacing for restarts past the budget, so a dead recognizer can't spin hot.
    private static let retryBackoff: TimeInterval = 0.5
    /// Identifies the running task, so a cancelled task's late callback can't roll
    /// (or overwrite) the one that replaced it.
    private var generation = 0
    /// Fires when no new words have arrived for `silenceLimit`.
    private var silenceTimer: Timer?
    /// When the transcript last actually grew — the clock the deliberate roll reads.
    private var lastGrowth = Date()
    /// Polls that clock while listening.
    private var rollTimer: Timer?

    init(locale: Locale = .autoupdatingCurrent) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit { silenceTimer?.invalidate(); rollTimer?.invalidate() }

    // MARK: - Control

    func start() {
        guard state != .listening, state != .preparing else { return }
        // Both ways a session ends — `stop()` and `finalize()` — hand the words to
        // the caller and clear them, so anything still here was never routed
        // anywhere. Carry it into the new session rather than destroying it.
        banked = transcript
        segment = ""
        level = 0
        silentRolls = 0
        failedStarts = 0
        // Permissions are async and, on a fresh install, two system dialogs deep. The
        // screen must not claim to be listening until the mic really is.
        state = .preparing
        requestPermissions { [weak self] speechOK, micOK in
            guard let self else { return }
            // Stopped (tab left, Back tapped) while the dialogs were up — don't open
            // the mic behind whatever the user is looking at now.
            guard self.state == .preparing else { return }
            guard speechOK && micOK else { self.state = .denied; return }
            guard self.recognizer?.isAvailable == true else { self.state = .unavailable; return }
            self.beginEngine()
        }
    }

    /// The user-facing end. The caller reads `transcript` first and routes it, so the
    /// words are cleared here — anything left over later is by definition unrouted.
    func stop() {
        endEngine()
        if state == .listening || state == .preparing { state = .idle }
        clearWords()
    }

    // MARK: - Permissions

    private func requestPermissions(_ completion: @escaping (_ speech: Bool, _ mic: Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechOK = speechStatus == .authorized
            AVAudioApplication.requestRecordPermission { micOK in
                Task { @MainActor in completion(speechOK, micOK) }
            }
        }
    }

    // MARK: - Audio engine (integration-only)

    private func beginEngine() {
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        endEngine()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.feed.append(buffer)
            let lvl = SpeechCapture.rmsLevel(buffer)
            Task { @MainActor in self?.updateLevel(lvl) }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            endEngine()
            state = .unavailable
            return
        }
        state = .listening
        armSilence()
        armRoll()
        guard startTask() else { endEngine(); state = .unavailable; return }
    }

    /// Starts a recognition task on the already-running engine. Returns false when the
    /// recognizer refuses one.
    @discardableResult
    private func startTask() -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Without punctuation the parser gets one unbroken wall of words and can't
        // split a braindump into separate items.
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        feed.set(request)
        segment = ""
        generation += 1
        let gen = generation

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let ended = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let text { self.segment = text; self.publish() }
                // `isFinal` means THIS TASK is done — after a silence gap or the
                // per-task ceiling — not that the user is done talking.
                if ended { self.rollTask() }
            }
        }
        return true
    }

    /// Bank the finished task's words and start the next one on the same live audio.
    /// The user sees nothing: the transcript only ever grows.
    private func rollTask() {
        guard state == .listening else { return }
        let hadWords = !segment.isEmpty
        banked = joined(banked, segment)
        segment = ""
        task?.cancel()
        task = nil
        publish()

        // The one roll that really does end a session: there is no room left.
        guard banked.count < Self.maxLength else { finalize(); return }

        // A silent roll is a pause, not a failure — always restart. Past the budget
        // the restarts are merely spaced out, so the session still ends only on the
        // user's stop, the 60s no-new-words cap, or a recognizer that keeps refusing.
        silentRolls = hadWords ? 0 : silentRolls + 1
        if hadWords { failedStarts = 0 }
        restartTask(after: silentRolls > Self.retryBudget ? Self.retryBackoff : 0)
    }

    /// Start the next task, retrying a refusal a few times before concluding the
    /// recognizer is dead — a single transient failure must never discard words the
    /// user has already spoken.
    private func restartTask(after delay: TimeInterval) {
        guard delay > 0 else {
            if startTask() {
                failedStarts = 0
            } else {
                failedStarts += 1
                if failedStarts >= Self.retryBudget { finalize() }
                else { restartTask(after: Self.retryBackoff) }
            }
            return
        }
        let gen = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.state == .listening, gen == self.generation else { return }
            self.restartTask(after: 0)
        }
    }

    /// Terminal path for a session that can't continue: tear down, go idle, and hand
    /// the transcript to `onFinish`. Guards on `.listening` so a manual `stop()`
    /// (which already routed the transcript) can't also fire the callback.
    private func finalize() {
        guard state == .listening else { return }
        let final = transcript
        endEngine()
        state = .idle
        clearWords()
        onFinish?(final)
    }

    /// Drop the accumulated words, once they have been handed to the caller.
    private func clearWords() {
        transcript = ""
        banked = ""
        segment = ""
    }

    private func publish() {
        let next = String(joined(banked, segment).prefix(Self.maxLength))
        // Only actual new words restart the countdowns.
        if next.count > transcript.count {
            lastGrowth = Date()
            armSilence()
        }
        transcript = next
    }

    private func armRoll() {
        rollTimer?.invalidate()
        lastGrowth = Date()
        rollTimer = Timer.scheduledTimer(withTimeInterval: Self.rollTick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rollIfIdle() }
        }
    }

    /// Force the banking iOS may never trigger on its own. Ending the request is what
    /// makes a buffer task finalize, and `RequestFeed.set` does exactly that — so once
    /// the words have sat still through `rollIdle`, roll on purpose. Nothing already
    /// recognized is lost: `segment` holds the latest partial and is banked first, and
    /// after that long a pause there is no speech in flight to straddle the swap. A
    /// deliberate roll always carries words, so `rollTask` reads it as progress and it
    /// never spends the silent-roll / failed-start budget.
    private func rollIfIdle() {
        guard state == .listening, !segment.isEmpty,
              Date().timeIntervalSince(lastGrowth) >= Self.rollIdle else { return }
        lastGrowth = Date()
        rollTask()
    }

    private func armSilence() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finalize() }
        }
    }

    private func joined(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }
        return lhs + " " + rhs
    }

    private func endEngine() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        rollTimer?.invalidate()
        rollTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        feed.finish()
        task?.cancel()
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateLevel(_ new: CGFloat) {
        // Light smoothing so the bars breathe rather than jitter.
        level = level * 0.6 + new * 0.4
    }

    /// RMS amplitude of a buffer, mapped to a 0…1 display level. Pure — runs on the
    /// realtime audio thread, so it touches no actor state.
    nonisolated static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { let s = channel[i]; sum += s * s }
        let rms = sqrt(sum / Float(count))
        return min(1, max(0, CGFloat(rms) * 12))
    }
}

/// The current recognition request, swappable under a lock: the audio tap appends
/// from the realtime thread while restarts happen on the main actor.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); let old = request; request = new; lock.unlock()
        old?.endAudio()
    }

    func finish() { set(nil) }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let current = request; lock.unlock()
        current?.append(buffer)
    }
}
