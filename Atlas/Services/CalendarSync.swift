import Foundation

/// Pure reconciliation helpers for Atlas ⇄ Google calendar sync. Deliberately free of
/// network and app state so the data-loss-critical rules can be unit-tested in isolation.
enum CalendarSync {

    /// Local ids of **Atlas-origin** events that were mirrored to Google but are now
    /// absent from a fresh Google listing for `[windowStart, windowEnd)` — i.e. deleted
    /// on Google, and therefore safe to delete locally.
    ///
    /// Safety rules (design review):
    /// - **Window-scoped (B1):** only events whose `start ∈ [windowStart, windowEnd)` are
    ///   eligible — an event outside the fetched window is absent for benign reasons.
    /// - **Pending-push guard (B2):** `eligibleGoogleIDs` is a snapshot of mirror ids taken
    ///   *before* the pull's fetch began. An id assigned during the fetch isn't in it, so a
    ///   freshly-created event can't be reaped by a listing that predates it.
    static func reapableEventIDs(
        events: [CalendarEvent],
        presentGoogleIDs: Set<String>,
        eligibleGoogleIDs: Set<String>,
        windowStart: Date,
        windowEnd: Date
    ) -> [UUID] {
        events.compactMap { event in
            guard event.source == .atlas,                    // only our own mirrors
                  let gid = event.googleEventId,             // that were actually pushed
                  eligibleGoogleIDs.contains(gid),           // and existed before this pull (B2)
                  !presentGoogleIDs.contains(gid),           // and are now gone from Google
                  event.start >= windowStart,                // within the fetched window (B1)
                  event.start < windowEnd
            else { return nil }
            return event.id
        }
    }
}
