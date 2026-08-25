import EventKit
import AtlasCore
import SwiftUI

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

    /// Apple Calendar events in `start..<end`, mapped to read-only `.apple` events.
    /// The stable id mirrors the Mac's derivation, so the same on-device event keys the
    /// same UUID on both platforms.
    func fetchEvents(start: Date, end: Date, defaultSpaceName: String) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { ekEvent in
            CalendarEvent(
                id: CalendarSync.stableUUID(from: ekEvent.eventIdentifier ?? UUID().uuidString),
                title: ekEvent.title ?? "Untitled",
                subtitle: ekEvent.calendar?.title ?? "",
                start: ekEvent.startDate,
                end: ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600),
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

    /// EventKit's "the on-device store changed" notification — the refresh trigger.
    var changeNotification: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
    }
}
