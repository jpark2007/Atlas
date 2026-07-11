import EventKit
import AtlasCore
import SwiftUI

/// Errors thrown by `EventKitService`'s write surface. Reads never throw (they degrade
/// to `[]`); writes must surface failure so a mirror attempt isn't silently lost.
enum EventKitWriteError: LocalizedError {
    /// Full calendar access hasn't been granted — no write is possible.
    case noAccess
    /// The `eventIdentifier` no longer resolves to an EKEvent (deleted on-device, or the
    /// id came from a different device — EventKit ids are per-device).
    case notFound

    var errorDescription: String? {
        switch self {
        case .noAccess: return "Calendar access isn't granted — enable it in System Settings → Privacy."
        case .notFound: return "That event no longer exists in Apple Calendar."
        }
    }
}

/// Thin wrapper around EventKit for reading and writing Apple Calendar events.
/// Fetched events are tagged `source: .apple`; `isReadOnly` reflects whether the
/// backing calendar allows edits and the event isn't recurring, so writable one-off
/// events can be edited in Atlas while subscribed / recurring events stay read-only.
///
/// Access semantics
/// ─────────────────
/// • macOS 14+: `requestFullAccessToEvents()` (new entitlement-aware API).
/// • macOS 13 and below: `requestAccess(to: .event)` (legacy path, gated by
///   `if #available(macOS 14, *)`).
/// • On denial / restricted status, all fetch calls return `[]` gracefully —
///   this service never throws to its callers.
final class EventKitService {
    private let store = EKEventStore()

    init() {}

    // MARK: - Access

    /// Requests full read access to the user's calendars.
    /// Returns `true` when access is granted, `false` otherwise.
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    /// The current EKAuthorizationStatus for calendar events.
    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Stable ID derivation

    /// Derives a deterministic UUID from an EKEvent identifier using FNV-1a.
    /// Avoids per-fetch `UUID()` calls that cause re-render flicker.
    private func stableUUID(from identifier: String) -> UUID {
        var h: UInt64 = 14695981039346656037
        for byte in identifier.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        let h2 = h.byteSwapped
        return UUID(uuid: (
            UInt8((h >> 56) & 0xFF), UInt8((h >> 48) & 0xFF),
            UInt8((h >> 40) & 0xFF), UInt8((h >> 32) & 0xFF),
            UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF),
            UInt8((h >>  8) & 0xFF), UInt8( h         & 0xFF),
            UInt8((h2 >> 56) & 0xFF), UInt8((h2 >> 48) & 0xFF),
            UInt8((h2 >> 40) & 0xFF), UInt8((h2 >> 32) & 0xFF),
            UInt8((h2 >> 24) & 0xFF), UInt8((h2 >> 16) & 0xFF),
            UInt8((h2 >>  8) & 0xFF), UInt8( h2         & 0xFF)
        ))
    }

    // MARK: - Fetch

    /// Fetches Apple Calendar events in the given date range and maps them to
    /// `[CalendarEvent]` tagged `source: .apple`, with `isReadOnly` and `isRecurring`
    /// derived from the backing calendar and the event's recurrence rules.
    ///
    /// - Parameters:
    ///   - start: Range start.
    ///   - end: Range end.
    ///   - defaultSpaceName: The Atlas space name to assign when no better
    ///     mapping exists (driven by `@AppStorage("calendar.apple.defaultSpace")`).
    /// - Returns: Mapped events, or `[]` when access is denied / unavailable.
    func fetchEvents(start: Date, end: Date, defaultSpaceName: String) async -> [CalendarEvent] {
        let status = authorizationStatus()
        guard status == .fullAccess else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { ekEvent in
            // Editable in Atlas only when the backing calendar allows edits AND the event
            // isn't recurring (series editing is out of scope until Task 12). Subscribed /
            // recurring events stay read-only. `isRecurring` is carried so recurring Apple
            // events are labeled (they previously showed unlabeled — the Apple labeling gap).
            let recurring = ekEvent.hasRecurrenceRules
            let editable = (ekEvent.calendar?.allowsContentModifications ?? false) && !recurring
            return CalendarEvent(
                id: stableUUID(from: ekEvent.eventIdentifier ?? UUID().uuidString),
                title: ekEvent.title ?? "Untitled",
                subtitle: ekEvent.calendar?.title ?? "",
                start: ekEvent.startDate,
                end: ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600),
                color: AtlasTheme.Colors.textSecondary,
                spaceName: defaultSpaceName,
                // Carry existing notes so an in-Atlas edit round-trips them instead of
                // blanking the EKEvent's notes on save-back.
                notes: ekEvent.notes,
                isAllDay: ekEvent.isAllDay,
                isReadOnly: !editable,
                source: .apple,
                appleEventId: ekEvent.eventIdentifier,
                isRecurring: recurring
            )
        }
    }

    // MARK: - Write (Track C mirror)
    //
    // These four methods are the write plumbing for mirroring Atlas events/work-blocks
    // into Apple Calendar. They are NOT unit-testable: EKEventStore hits the live on-device
    // store and requires granted calendar permission, so there is no seam to mock without
    // inventing a protocol the app doesn't otherwise need. The testable slice — the
    // `apple_event_id` row round-trip — is covered in AtlasDBMappingTests instead. Behavior
    // here is verified live on-device (Task 11 wires these into the UI).

    /// Creates a new EKEvent from `event` and saves it. Resolves `calendarId` via
    /// `store.calendar(withIdentifier:)`, falling back to `defaultCalendarForNewEvents`.
    /// - Returns: the saved event's `eventIdentifier` (persist it as `appleEventId`).
    func createEvent(_ event: CalendarEvent, calendarId: String?) async throws -> String {
        guard authorizationStatus() == .fullAccess else { throw EventKitWriteError.noAccess }

        let ekEvent = EKEvent(eventStore: store)
        apply(event, to: ekEvent)
        ekEvent.calendar = calendarId.flatMap { store.calendar(withIdentifier: $0) }
            ?? store.defaultCalendarForNewEvents

        try store.save(ekEvent, span: .thisEvent)
        return ekEvent.eventIdentifier
    }

    /// Patches the EKEvent identified by `appleEventID` with `event`'s fields.
    /// - Throws: `.notFound` when the identifier no longer resolves to an event.
    func updateEvent(appleEventID: String, with event: CalendarEvent) async throws {
        guard authorizationStatus() == .fullAccess else { throw EventKitWriteError.noAccess }
        guard let ekEvent = store.event(withIdentifier: appleEventID) else {
            throw EventKitWriteError.notFound
        }
        apply(event, to: ekEvent)
        try store.save(ekEvent, span: .thisEvent)
    }

    /// Removes the EKEvent identified by `appleEventID`.
    /// - Throws: `.notFound` when the identifier no longer resolves to an event.
    func deleteEvent(appleEventID: String) async throws {
        guard authorizationStatus() == .fullAccess else { throw EventKitWriteError.noAccess }
        guard let ekEvent = store.event(withIdentifier: appleEventID) else {
            throw EventKitWriteError.notFound
        }
        try store.remove(ekEvent, span: .thisEvent)
    }

    /// The calendars the user can write to — the pickable destinations for a mirrored
    /// event. Empty when access is denied.
    func writableCalendars() -> [(id: String, title: String)] {
        guard authorizationStatus() == .fullAccess else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { (id: $0.calendarIdentifier, title: $0.title) }
    }

    /// Maps the writable fields of a `CalendarEvent` onto an `EKEvent`. Shared by
    /// create + update so both stay in lockstep.
    private func apply(_ event: CalendarEvent, to ekEvent: EKEvent) {
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.notes = event.notes
        ekEvent.isAllDay = event.isAllDay
    }
}
