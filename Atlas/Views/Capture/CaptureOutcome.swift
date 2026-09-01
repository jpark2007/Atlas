import Foundation

/// User-facing result of a quick-capture, with its confirmation string.
/// Centralizes copy and makes the "AI unavailable → saved as plain task"
/// degraded path explicit, so a down backend is never silently identical
/// to a healthy task save.
enum CaptureOutcome: Equatable {
    case task(hasDate: Bool)
    case event
    /// A repeating event expanded into `count` real sessions. Distinct from `.event` so
    /// the confirmation reports the whole series — "added 1 event" after typing a
    /// recurring schedule would read as a failure.
    case eventSeries(count: Int)
    case note
    case updated    // attached to an item the user already had, instead of duplicating it
    case degraded   // AI unreachable / unparseable → saved as a plain task

    var confirmation: String {
        switch self {
        case .task(let hasDate): return hasDate ? "✓ Added task · due set" : "✓ Added task"
        case .event:             return "✓ Added event"
        case .eventSeries(let n): return "✓ Added \(n) repeating events"
        case .note:              return "✓ Added note"
        case .updated:           return "✓ Updated what you already had"
        case .degraded:          return "⚠︎ AI offline — saved as plain task"
        }
    }

    /// Confirmation for a whole capture. A single item keeps its per-kind copy;
    /// a multi-item paragraph collapses to a count ("✓ Added 3 items"). An empty
    /// set is treated as the degraded fallback.
    static func confirmation(for outcomes: [CaptureOutcome]) -> String {
        switch outcomes.count {
        case 0:  return CaptureOutcome.degraded.confirmation
        case 1:  return outcomes[0].confirmation
        default: return "✓ Added \(outcomes.count) items"
        }
    }
}
