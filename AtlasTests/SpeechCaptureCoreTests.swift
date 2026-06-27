import XCTest
@testable import Atlas

/// Pure-logic tests for the click-to-talk lifecycle. The audio engine itself is
/// integration-only; these cover the gating + transcript-merge decisions.
final class SpeechCaptureCoreTests: XCTestCase {

    // MARK: resolveStartState

    func testResolveStart_allGood_isListening() {
        XCTAssertEqual(
            SpeechCaptureCore.resolveStartState(
                speechAuthorized: true, micAuthorized: true, recognizerAvailable: true),
            .listening
        )
    }

    func testResolveStart_micDenied_isDenied() {
        XCTAssertEqual(
            SpeechCaptureCore.resolveStartState(
                speechAuthorized: true, micAuthorized: false, recognizerAvailable: true),
            .denied
        )
    }

    func testResolveStart_speechDenied_isDenied() {
        XCTAssertEqual(
            SpeechCaptureCore.resolveStartState(
                speechAuthorized: false, micAuthorized: true, recognizerAvailable: true),
            .denied
        )
    }

    func testResolveStart_permissionGatingBeatsAvailability() {
        // Even with the recognizer unavailable, a refused permission is the
        // actionable problem, so .denied wins.
        XCTAssertEqual(
            SpeechCaptureCore.resolveStartState(
                speechAuthorized: false, micAuthorized: false, recognizerAvailable: false),
            .denied
        )
    }

    func testResolveStart_authorizedButUnavailable_isUnavailable() {
        XCTAssertEqual(
            SpeechCaptureCore.resolveStartState(
                speechAuthorized: true, micAuthorized: true, recognizerAvailable: false),
            .unavailable
        )
    }

    // MARK: nextStateOnToggle

    func testToggle_fromIdle_adoptsResolvedStart() {
        XCTAssertEqual(
            SpeechCaptureCore.nextStateOnToggle(from: .idle, resolvedStart: .listening),
            .listening
        )
    }

    func testToggle_fromListening_stopsToIdle() {
        // A resolved-start of .listening is irrelevant while already listening:
        // a toggle must stop.
        XCTAssertEqual(
            SpeechCaptureCore.nextStateOnToggle(from: .listening, resolvedStart: .listening),
            .idle
        )
    }

    func testToggle_fromDenied_canRetryStart() {
        XCTAssertEqual(
            SpeechCaptureCore.nextStateOnToggle(from: .denied, resolvedStart: .listening),
            .listening
        )
    }

    // MARK: compose

    func testCompose_emptyBase_returnsTranscript() {
        XCTAssertEqual(SpeechCaptureCore.compose(base: "", transcript: "buy milk"), "buy milk")
    }

    func testCompose_emptyTranscript_returnsBase() {
        XCTAssertEqual(SpeechCaptureCore.compose(base: "draft email", transcript: ""), "draft email")
    }

    func testCompose_bothPresent_joinedBySingleSpace() {
        XCTAssertEqual(
            SpeechCaptureCore.compose(base: "essay due thursday", transcript: "and gym at five"),
            "essay due thursday and gym at five"
        )
    }

    func testCompose_trimsEdgeWhitespace_noDoubleSpace() {
        XCTAssertEqual(
            SpeechCaptureCore.compose(base: "remember  ", transcript: "  call mom"),
            "remember call mom"
        )
    }

    func testCompose_bothEmpty_isEmpty() {
        XCTAssertEqual(SpeechCaptureCore.compose(base: "   ", transcript: "  "), "")
    }
}
