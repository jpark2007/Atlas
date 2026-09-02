import XCTest
@testable import AtlasCore

/// `CanvasFeedHealth.evaluate` — the pure rule behind the Mac sidebar's "Canvas feed
/// stopped syncing" nudge: broken (revoked/error) beats staleness, and a fresh
/// `active` feed with no sync yet is stale, not ok (never silently hide a feed that
/// has never once synced).
final class CanvasFeedHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_revoked_isBroken() {
        let health = CanvasFeedHealth.evaluate(status: "revoked", lastError: nil,
                                               lastSyncedAt: now, now: now)
        XCTAssertEqual(health, .broken(reason: nil))
    }

    func test_error_isBrokenWithReason() {
        let health = CanvasFeedHealth.evaluate(status: "error", lastError: "feed URL returned 404",
                                               lastSyncedAt: now, now: now)
        XCTAssertEqual(health, .broken(reason: "feed URL returned 404"))
    }

    func test_error_withNoReason_stillBroken() {
        let health = CanvasFeedHealth.evaluate(status: "error", lastError: nil,
                                               lastSyncedAt: now, now: now)
        XCTAssertEqual(health, .broken(reason: nil))
    }

    func test_active_recentSync_isOk() {
        let syncedOneHourAgo = now.addingTimeInterval(-60 * 60)
        let health = CanvasFeedHealth.evaluate(status: "active", lastError: nil,
                                               lastSyncedAt: syncedOneHourAgo, now: now)
        XCTAssertEqual(health, .ok)
    }

    func test_active_syncOlderThan24h_isStale() {
        let syncedTwoDaysAgo = now.addingTimeInterval(-48 * 60 * 60)
        let health = CanvasFeedHealth.evaluate(status: "active", lastError: nil,
                                               lastSyncedAt: syncedTwoDaysAgo, now: now)
        XCTAssertEqual(health, .stale(lastSyncedAt: syncedTwoDaysAgo))
    }

    func test_active_exactlyAt24h_isStale() {
        let syncedExactly24hAgo = now.addingTimeInterval(-24 * 60 * 60)
        let health = CanvasFeedHealth.evaluate(status: "active", lastError: nil,
                                               lastSyncedAt: syncedExactly24hAgo, now: now)
        XCTAssertEqual(health, .stale(lastSyncedAt: syncedExactly24hAgo))
    }

    func test_active_neverSynced_isStale() {
        let health = CanvasFeedHealth.evaluate(status: "active", lastError: nil,
                                               lastSyncedAt: nil, now: now)
        XCTAssertEqual(health, .stale(lastSyncedAt: nil))
    }
}
