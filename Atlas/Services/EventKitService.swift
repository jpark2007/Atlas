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
        guard status == .fullAccess else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { ekEvent in
            CalendarEvent(
                id: stableUUID(from: ekEvent.eventIdentifier ?? UUID().uuidString),
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
