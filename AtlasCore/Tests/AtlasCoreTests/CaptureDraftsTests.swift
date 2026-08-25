import XCTest
@testable import AtlasCore

/// Phase 4 §1 — "if I typed it, Atlas saved it." The draft buffer and the pending
/// queue are the two things standing between a typed dump and losing it.
final class CaptureDraftStoreTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "atlas.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_loadIsEmptyWhenNothingSaved() {
        XCTAssertEqual(CaptureDraftStore.load(from: defaults), "")
    }

    func test_saveThenLoadRoundTrips() {
        CaptureDraftStore.save("pset 3 due friday", to: defaults)
        XCTAssertEqual(CaptureDraftStore.load(from: defaults), "pset 3 due friday")
    }

    func test_saveKeepsTrailingSpaceMidTyping() {
        // Mid-word typing must not be normalized away — restore what was typed.
        CaptureDraftStore.save("call mom ", to: defaults)
        XCTAssertEqual(CaptureDraftStore.load(from: defaults), "call mom ")
    }

    func test_whitespaceOnlySaveClearsInsteadOfStoring() {
        CaptureDraftStore.save("something", to: defaults)
        CaptureDraftStore.save("   \n ", to: defaults)
        XCTAssertEqual(CaptureDraftStore.load(from: defaults), "")
    }

    func test_clearRemovesTheDraft() {
        CaptureDraftStore.save("draft", to: defaults)
        CaptureDraftStore.clear(from: defaults)
        XCTAssertEqual(CaptureDraftStore.load(from: defaults), "")
    }
}

@MainActor
final class PendingCaptureQueueTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "atlas.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_enqueuePreservesFIFOOrder() {
        let q = PendingCaptureQueue(defaults: defaults)
        q.enqueue("first")
        q.enqueue("second")
        XCTAssertEqual(q.items.map(\.text), ["first", "second"])
    }

    func test_enqueueTrimsAndIgnoresBlankText() {
        let q = PendingCaptureQueue(defaults: defaults)
        q.enqueue("  padded  ")
        q.enqueue("   ")
        XCTAssertEqual(q.items.map(\.text), ["padded"])
    }

    func test_queueSurvivesAppRelaunch() {
        let q = PendingCaptureQueue(defaults: defaults)
        q.enqueue("held offline")
        let relaunched = PendingCaptureQueue(defaults: defaults)
        XCTAssertEqual(relaunched.items.map(\.text), ["held offline"])
    }

    func test_removeIsPersisted() {
        let q = PendingCaptureQueue(defaults: defaults)
        q.enqueue("a")
        q.enqueue("b")
        q.remove(q.items[0].id)
        XCTAssertEqual(PendingCaptureQueue(defaults: defaults).items.map(\.text), ["b"])
    }

    /// The drain removes BEFORE parsing and re-enqueues on failure — the item must
    /// come back rather than vanish, even though its id changes.
    func test_removeThenReEnqueueKeepsTheText() {
        let q = PendingCaptureQueue(defaults: defaults)
        q.enqueue("survive me")
        let item = q.items[0]
        q.remove(item.id)
        XCTAssertTrue(q.items.isEmpty)
        q.enqueue(item.text)
        XCTAssertEqual(q.items.map(\.text), ["survive me"])
    }

    /// Existing on-disk queues were written before this type moved to AtlasCore;
    /// the {id, text} shape must still decode so nothing already queued is dropped.
    func test_decodesLegacyOnDiskShape() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","text":"legacy"}]"#
        defaults.set(Data(json.utf8), forKey: PendingCaptureQueue.key)
        XCTAssertEqual(PendingCaptureQueue(defaults: defaults).items.map(\.text), ["legacy"])
    }
}

final class URLErrorConnectivityTests: XCTestCase {

    func test_connectivityCodesQueueForLater() {
        for code in [URLError.notConnectedToInternet, .networkConnectionLost, .timedOut,
                     .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                     .dataNotAllowed, .internationalRoamingOff] {
            XCTAssertTrue(URLError(code).isConnectivity, "\(code) should queue")
        }
    }

    func test_nonConnectivityCodesDoNotQueue() {
        for code in [URLError.badURL, .cancelled, .unsupportedURL] {
            XCTAssertFalse(URLError(code).isConnectivity, "\(code) should not queue")
        }
    }
}
