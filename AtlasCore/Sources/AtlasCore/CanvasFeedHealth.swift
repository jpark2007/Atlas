import Foundation

/// A `calendar_feeds` (or `canvas_connections`) row's health, judged for the sidebar
/// nudge that surfaces a dead or stale feed. Pure and platform-agnostic so both Mac
/// (built first) and iOS can share the same 24h-staleness rule later.
public enum CanvasFeedHealth: Equatable {
    /// Syncing normally — nothing to show.
    case ok
    /// The server marked the feed `error` or `revoked` — `reason` is `last_error` when
    /// the server sent one.
    case broken(reason: String?)
    /// The feed is `active` but hasn't synced successfully in over 24h.
    case stale(lastSyncedAt: Date?)

    /// Judges a feed's health from its server-reported `status`, `lastError`, and
    /// `lastSyncedAt`, as of `now`. `status` is one of "active" | "error" | "revoked"
    /// (the check constraint every `canvas_connections`/`calendar_feeds` row satisfies).
    ///
    /// - `revoked` or `error` ⇒ `.broken` (server has already given up or is retrying
    ///   after a failure — `reason` carries `last_error` when the server sent one).
    /// - `active` with no successful sync in the last 24h ⇒ `.stale`.
    /// - Anything else ⇒ `.ok`.
    public static func evaluate(status: String, lastError: String?, lastSyncedAt: Date?,
                                now: Date = Date()) -> CanvasFeedHealth {
        if status == "revoked" || status == "error" {
            return .broken(reason: lastError)
        }
        let staleThreshold: TimeInterval = 24 * 60 * 60
        guard let lastSyncedAt, now.timeIntervalSince(lastSyncedAt) < staleThreshold else {
            return .stale(lastSyncedAt: lastSyncedAt)
        }
        return .ok
    }
}
