import EventKit
import AtlasCore
import SwiftUI

/// The user's per-calendar choice for Apple Calendar, stored DEVICE-LOCAL (EKCalendar
/// identifiers are per-device, so this key is never synced). Mirrors the Mac's
/// `AppleCalendarSelection` (`Atlas/Services/EventKitService.swift`) — same key, same
/// hidden-ids-not-selected-ids shape — but kept in the app layer here too, since each
/// platform's EventKit ids are its own.
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

/// Apple Calendar on iPhone — **read only** (Phase 3, "Apple Calendar from iPhone").
///
/// The Mac's `EventKitService` also writes (the Atlas→Apple mirror); write-back stays
/// device-local per the existing design, and the phone deliberately doesn't build it. So
/// every event this returns is `isReadOnly: true` and carries `source: .apple` — the
/// source is set here, at ingest, and never relabelled downstream.
///
/// iOS 17+ requires `requestFullAccessToEvents()` plus
/// `NSCalendarsFullAccessUsageDescription`; reads degrade to `[]` on denial, never throw.
@MainActor
final class MobileEventKitService {
    private let store = EKEventStore()

    /// Prompts for (or re-checks) full calendar access. `false` on denial.
    @discardableResult
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool { authorizationStatus == .fullAccess }

    /// Every calendar Atlas can read, sorted for display — the picker's source list.
    /// Empty when access isn't full.
    func readableCalendars() -> [(id: String, title: String)] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Apple Calendar events in `start..<end`, mapped to read-only `.apple` events.
    /// The stable id mirrors the Mac's derivation, so the same on-device event keys the
    /// same UUID on both platforms.
    /// - Parameter hiddenCalendarIds: EKCalendar identifiers the user unchecked in
    ///   Settings. Empty ⇒ every calendar is read.
    func fetchEvents(start: Date, end: Date, defaultSpaceName: String,
                     hiddenCalendarIds: Set<String> = []) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let visible = store.calendars(for: .event)
            .filter { !hiddenCalendarIds.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: predicate).map { ekEvent in
            let rawEnd = ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600)
            return CalendarEvent(
                id: CalendarSync.stableUUID(from: ekEvent.eventIdentifier ?? UUID().uuidString),
                title: ekEvent.title ?? "Untitled",
                subtitle: ekEvent.calendar?.title ?? "",
                start: ekEvent.isAllDay ? Self.canonicalAllDayStart(ekEvent.startDate) : ekEvent.startDate,
                end: ekEvent.isAllDay ? Self.canonicalAllDayEnd(rawEnd) : rawEnd,
                color: AtlasTheme.Colors.textSecondary,
                spaceName: defaultSpaceName,
                notes: ekEvent.notes,
                isAllDay: ekEvent.isAllDay,
                isReadOnly: true,           // the phone never writes back to Apple Calendar
                source: .apple,
                appleEventId: ekEvent.eventIdentifier,
                isRecurring: ekEvent.hasRecurrenceRules
            )
        }
    }

    // MARK: - All-day normalization

    // EventKit is the one ingest path that anchors all-day events at LOCAL midnight, and it
    // ends them at 23:59:59 on the last day. Google and ICS both hand us the canonical
    // anchor — UTC midnight of the calendar date (`AllDayDate`) — with an exclusive end.
    // Convert here, at the boundary, so nothing downstream ever sees two conventions.

    /// UTC midnight of the calendar date `instant` falls on locally.
    private static func canonicalAllDayStart(_ instant: Date) -> Date {
        AllDayDate.anchor(forDayOf: instant, in: .current)
    }

    /// EventKit's inclusive last-day end → the exclusive next-midnight end Google uses.
    private static func canonicalAllDayEnd(_ instant: Date) -> Date {
        canonicalAllDayStart(instant).addingTimeInterval(86_400)
    }

    /// EventKit's "the on-device store changed" notification — the refresh trigger.
    var changeNotification: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
    }
}
