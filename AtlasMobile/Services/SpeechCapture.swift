import Foundation
import Speech
import AVFoundation

/// On-device dictation for the Capture screen (iOS). Mirrors the Mac
/// `SpeechCaptureService` lifecycle, adapted for iOS permissions
/// (`AVAudioApplication`/`AVAudioSession`) and publishing a live input `level`
/// for the waveform. NEVER auto-listens — `start()` is called only when the mic
/// is tapped (or an `atlas://capture?mic=1` deep link fires).
@MainActor
final class SpeechCapture: ObservableObject {

    enum State: Equatable {
        case idle          // ready, not listening
        case listening     // mic live, transcript streaming
        case denied        // mic and/or speech permission refused
        case unavailable   // recognizer unavailable (locale/device/offline unsupported)
    }

    @Published private(set) var state: State = .idle
    /// Latest live transcript from the recognizer.
    @Published private(set) var transcript: String = ""
    /// Smoothed input level, 0…1 — drives the waveform bars.
    @Published private(set) var level: CGFloat = 0

    /// Fired once when dictation ends on its own (recognizer `isFinal` / error) while
    /// still listening — a manual `stop()` never fires it. Carries the final
    /// transcript so the caller can route it through the same flow as the Stop button.
    var onFinish: ((String) -> Void)?

    var isListening: Bool { state == .listening }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .autoupdatingCurrent) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Control

    func start() {
        guard !isListening else { return }
        transcript = ""
        level = 0
        requestPermissions { [weak self] speechOK, micOK in
            guard let self else { return }
            guard speechOK && micOK else { self.state = .denied; return }
            guard self.recognizer?.isAvailable == true else { self.state = .unavailable; return }
            self.beginEngine()
        }
    }

    func stop() {
        endEngine()
        if state == .listening { state = .idle }
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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
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

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self.finalize() }
            }
        }
    }

    /// Terminal path for a self-finalized recognition: tear down, go idle, and hand
    /// the transcript to `onFinish`. Guards on `.listening` so a manual `stop()`
    /// (which already routed the transcript) can't also fire the callback.
    private func finalize() {
        guard state == .listening else { return }
        let final = transcript
        endEngine()
        state = .idle
        onFinish?(final)
    }

    private func endEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
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
