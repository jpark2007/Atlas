import Foundation

/// Pure derivation of anonymized busy intervals from a set of calendar events.
/// Never carries titles into the output — `AvailabilityBlockRow` has no title
/// field at all, so this is structurally enforced, not just a convention.
public enum AvailabilityDerivation {
    public static func busyBlocks(from events: [CalendarEvent], excludingDeadlines: Bool) -> [AvailabilityBlockRow] {
        events
            .filter { !$0.isAllDay }
            .filter { !(excludingDeadlines && $0.isDeadline) }
            .filter { $0.end > $0.start }
            .map { ev in
                AvailabilityBlockRow(id: UUID(), userId: UUID(), startAt: ev.start, endAt: ev.end,
                                     source: sourceString(for: ev.source), updatedAt: "")
            }
    }

    private static func sourceString(for source: EventSource) -> String {
        switch source {
        case .apple:  return "apple"
        case .google: return "google"
        case .atlas:  return "atlas"
        case .canvas: return "canvas"
        }
    }
}
