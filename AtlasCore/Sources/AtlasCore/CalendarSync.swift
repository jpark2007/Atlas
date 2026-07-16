import Foundation

/// Pure reconciliation helpers for Atlas ⇄ Google calendar sync. Deliberately free of
/// network and app state so the data-loss-critical rules can be unit-tested in isolation.
public enum CalendarSync {

    /// True when an Atlas-origin event should be mirrored into Apple Calendar. Pure gate
    /// (no EventKit / app-state access) so the decision is unit-testable; the live caller
    /// supplies the device-local toggle + EventKit authorization. Work-blocks never reach
    /// here — the mirror trio only sees first-class `events`, matching the Google trio.
    public static func shouldWriteBackApple(
        enabled: Bool,
        authorized: Bool,
        event: CalendarEvent
    ) -> Bool {
        guard enabled, authorized else { return false }
        // Task 12 adds: && event.rrule == nil  (recurring events aren't mirrored)
        return event.source == .atlas && !event.isReadOnly
    }

    /// External (read-only) events to display after dropping any that are actually our own
    /// mirrors already shown natively: a Google event we pushed (matched by `googleEventId`)
    /// or an Apple event we mirrored (matched by `appleEventId`, which EventKit re-reads on
    /// the next tick). Without this, every mirrored event double-displays — once as the
    /// native Atlas tile, once as its external copy.
    public static func excludingOwnMirrors(
        external: [CalendarEvent],
        ownGoogleIDs: Set<String>,
        ownAppleIDs: Set<String>
    ) -> [CalendarEvent] {
        external.filter { ev in
            if let gid = ev.googleEventId, ownGoogleIDs.contains(gid) { return false }
            if let aid = ev.appleEventId, ownAppleIDs.contains(aid) { return false }
            return true
        }
    }
}
