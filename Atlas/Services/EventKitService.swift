import EventKit
import SwiftUI

/// Thin wrapper around EventKit that provides read-only access to Apple Calendar
/// events. All results are returned as `[CalendarEvent]` with `isReadOnly: true`
/// so the rest of the app can display them without risk of accidental mutation.
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

    // MARK: - Fetch

    /// Fetches Apple Calendar events in the given date range and maps them to
    /// `[CalendarEvent]` tagged `isReadOnly: true`.
    ///
    /// - Parameters:
    ///   - start: Range start.
    ///   - end: Range end.
    ///   - defaultSpaceName: The Atlas space name to assign when no better
    ///     mapping exists (driven by `@AppStorage("calendar.apple.defaultSpace")`).
    /// - Returns: Mapped events, or `[]` when access is denied / unavailable.
    func fetchEvents(start: Date, end: Date, defaultSpaceName: String) async -> [CalendarEvent] {
        let status = authorizationStatus()
        guard status == .fullAccess || status == .authorized else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { ekEvent in
            CalendarEvent(
                id: UUID(),
                title: ekEvent.title ?? "Untitled",
                subtitle: ekEvent.calendar?.title ?? "",
                start: ekEvent.startDate,
                end: ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600),
                color: AtlasTheme.Colors.textSecondary,
                spaceName: defaultSpaceName,
                isAllDay: ekEvent.isAllDay,
                isReadOnly: true
            )
        }
    }
}
