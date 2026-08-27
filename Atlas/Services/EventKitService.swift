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

/// The user's per-calendar choice for Apple Calendar, stored DEVICE-LOCAL (EKCalendar
/// identifiers are per-device, so this key is never synced). macOS has no iOS-style
/// "limited calendars" OS picker; this is Atlas's in-app equivalent.
///
/// HIDDEN ids are stored rather than selected ones so the default (empty) means "show
/// every calendar", a newly-added Apple calendar shows up on its own, and "hide them
/// all" is still representable — which an empty selected-set could not express.
enum AppleCalendarSelection {
    static let hiddenKey = "calendar.apple.hiddenCalendarIds"

    static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    static func encode(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: "\n")
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
/// • macOS 14 can also land on `.writeOnly` ("Add Only"): the grant permits adding
///   events but not seeing them. Every surface here — reads AND the write methods —
///   requires `.fullAccess`, because the mirror needs to read its own events back
///   (`store.event(withIdentifier:)`) to update or delete them. So write-only is a
///   non-working state, and Settings says so instead of looking connected.
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
    ///   - hiddenCalendarIds: EKCalendar identifiers the user unchecked in Settings.
    ///     Empty ⇒ every calendar is read.
    /// - Returns: Mapped events, or `[]` when access isn't full (write-only can add
    ///   events but cannot see them) or every calendar is hidden.
    func fetchEvents(start: Date, end: Date, defaultSpaceName: String,
                     hiddenCalendarIds: Set<String> = []) async -> [CalendarEvent] {
        let status = authorizationStatus()
        guard status == .fullAccess else { return [] }

        let visible = store.calendars(for: .event)
            .filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { ekEvent in
            // Editable in Atlas only when the backing calendar allows edits AND the event
            // isn't recurring (series editing is out of scope until Task 12). Subscribed /
            // recurring events stay read-only. `isRecurring` is carried so recurring Apple
            // events are labeled (they previously showed unlabeled — the Apple labeling gap).
            let recurring = ekEvent.hasRecurrenceRules
            let editable = (ekEvent.calendar?.allowsContentModifications ?? false) && !recurring
            let rawStart: Date = ekEvent.startDate
            let rawEnd: Date = ekEvent.endDate ?? rawStart.addingTimeInterval(3600)
            let (start, end) = ekEvent.isAllDay
                ? Self.normalizedAllDay(start: rawStart, end: rawEnd)
                : (rawStart, rawEnd)
            return CalendarEvent(
                id: stableUUID(from: ekEvent.eventIdentifier ?? UUID().uuidString),
                title: ekEvent.title ?? "Untitled",
                subtitle: ekEvent.calendar?.title ?? "",
                start: start,
                end: end,
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

    // MARK: - All-day normalization (the EventKit boundary)
    //
    // EventKit is the one source that speaks a different all-day dialect: it hands back
    // LOCAL midnight and an INCLUSIVE last day (23:59:59). Atlas's canonical encoding is
    // UTC midnight of the intended calendar date with an EXCLUSIVE end — what Google, ICS
    // and the editors all store (`AllDayDate`). Both directions are converted here so
    // nothing downstream, and nothing in Apple Calendar, ever sees the other convention.

    /// EventKit all-day pair → canonical (UTC midnight, exclusive UTC midnight).
    private static func normalizedAllDay(start: Date, end: Date) -> (Date, Date) {
        let cal = Calendar.current
        let startDay = AllDayDate.anchor(forDayOf: start, in: cal)
        // Step back a second before reading the last day, so both shapes EventKit uses
        // (23:59:59 on the last day, or the next day's midnight) name the same day.
        let lastDay = AllDayDate.anchor(forDayOf: max(end.addingTimeInterval(-1), start), in: cal)
        let exclusiveEnd = AllDayDate.utc.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return (startDay, max(exclusiveEnd, startDay))
    }

    /// Canonical all-day pair → what EventKit expects (local midnight, inclusive last day).
    private static func eventKitAllDay(start: Date, end: Date) -> (Date, Date) {
        let cal = Calendar.current
        let startDay = AllDayDate.localDay(of: start, calendar: cal)
        let endDay = AllDayDate.localDay(of: end, calendar: cal)
        let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: endDay) ?? startDay
        return (startDay, max(inclusiveEnd, startDay))
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

    /// Every calendar Atlas can READ — the rows behind the per-calendar checkbox list in
    /// Settings. Empty when access isn't full.
    func readableCalendars() -> [(id: String, title: String)] {
        guard authorizationStatus() == .fullAccess else { return [] }
        return store.calendars(for: .event)
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
        let (start, end) = event.isAllDay
            ? Self.eventKitAllDay(start: event.start, end: event.end)
            : (event.start, event.end)
        ekEvent.startDate = start
        ekEvent.endDate = end
        ekEvent.notes = event.notes
        ekEvent.isAllDay = event.isAllDay
    }
}
