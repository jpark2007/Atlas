import Foundation
import Speech
import AVFoundation

// MARK: - Pure, testable core
//
// The audio engine itself is integration-only, but the lifecycle decisions
// (can we start? what state should we show? how does live dictation merge with
// already-typed text?) are pure functions and are unit-tested in
// `SpeechCaptureCoreTests`. Keep this section Foundation-only — no Speech /
// AVFoundation symbols — so it stays trivially testable.

/// Observable lifecycle state of click-to-talk dictation.
enum SpeechCaptureState: Equatable {
    case idle          // not listening; ready
    case listening     // mic live, transcript streaming
    case denied        // mic and/or speech permission refused
    case unavailable   // recognizer unavailable (locale/device/offline-on-device unsupported)
}

/// Pure decision helpers for the speech capture lifecycle.
enum SpeechCaptureCore {

    /// The state a *start* attempt should resolve to, given current permissions
    /// and recognizer availability. Permission gating wins over availability so a
    /// user who refused the mic always sees `.denied` (the actionable problem).
    static func resolveStartState(
        speechAuthorized: Bool,
        micAuthorized: Bool,
        recognizerAvailable: Bool
    ) -> SpeechCaptureState {
        guard speechAuthorized && micAuthorized else { return .denied }
        guard recognizerAvailable else { return .unavailable }
        return .listening
    }

    /// Next state for a click-to-talk toggle. If currently `.listening`, stop
    /// (→ `.idle`); otherwise begin and adopt whatever the start attempt resolves to.
    static func nextStateOnToggle(
        from current: SpeechCaptureState,
        resolvedStart: SpeechCaptureState
    ) -> SpeechCaptureState {
        current == .listening ? .idle : resolvedStart
    }

    /// Merge the live transcript onto text the user had already typed. The typed
    /// text stays as a prefix; the recognizer's running transcript follows it,
    /// separated by a single space. Either side empty → just the other side.
    static func compose(base: String, transcript: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty { return trimmedTranscript }
        if trimmedTranscript.isEmpty { return trimmedBase }
        return trimmedBase + " " + trimmedTranscript
    }
}

// MARK: - SpeechCaptureService
//
// On-device click-to-talk dictation for the capture overlay. NEVER auto-listens:
// recording only begins when `toggle`/`start` is called (i.e. the mic button is
// tapped). Streams a composed transcript (typed-base + live recognition) back via
// an `onTranscript` callback so it flows into the existing capture text field.

@MainActor
final class SpeechCaptureService: ObservableObject {

    @Published private(set) var state: SpeechCaptureState = .idle
    /// The latest live transcript from the recognizer (without the typed base).
    @Published private(set) var liveTranscript: String = ""

    var isListening: Bool { state == .listening }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Text the field already held when listening began; the live transcript is
    /// composed onto this so dictation appends rather than clobbers.
    private var base: String = ""
    private var onTranscript: ((String) -> Void)?

    init(locale: Locale = .autoupdatingCurrent) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: Click-to-talk

    /// Mic-button handler. Stops if already listening; otherwise requests
    /// permissions (once) and begins streaming dictation into `onTranscript`.
    func toggle(currentText: String, onTranscript: @escaping (String) -> Void) {
        if isListening {
            stop()
        } else {
            start(currentText: currentText, onTranscript: onTranscript)
        }
    }

    func start(currentText: String, onTranscript: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.base = currentText
        self.onTranscript = onTranscript
        self.liveTranscript = ""

        requestPermissions { [weak self] speechAuthorized, micAuthorized in
            guard let self else { return }
            let available = self.recognizer?.isAvailable ?? false
            let resolved = SpeechCaptureCore.resolveStartState(
                speechAuthorized: speechAuthorized,
                micAuthorized: micAuthorized,
                recognizerAvailable: available
            )
            self.state = resolved
            guard resolved == .listening else { return }
            self.beginEngine()
        }
    }

    func stop() {
        endEngine()
        if state == .listening { state = .idle }
    }

    // MARK: Permissions

    /// Requests speech + microphone authorization, resolving on the main actor.
    private func requestPermissions(_ completion: @escaping (_ speech: Bool, _ mic: Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechOK = speechStatus == .authorized
            // macOS microphone permission flows through AVCaptureDevice (not the
            // iOS-only AVAudioSession). Request audio access, then resolve on main.
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                Task { @MainActor in completion(speechOK, micOK) }
            }
        }
    }

    // MARK: Audio engine (integration-only)

    private func beginEngine() {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }

        // Tear down any prior session before starting a fresh one.
        endEngine()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            endEngine()
            state = .unavailable
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let spoken = result.bestTranscription.formattedString
                    self.liveTranscript = spoken
                    // Guard against empty results from cancel/cleanup callbacks —
                    // an empty spoken string would compose to "" and wipe the field.
                    if !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let merged = SpeechCaptureCore.compose(base: self.base, transcript: spoken)
                        self.onTranscript?(merged)
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    private func endEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
