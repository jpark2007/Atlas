import Foundation

/// User-facing result of a quick-capture, with its confirmation string.
/// Centralizes copy and makes the "AI unavailable → saved as plain task"
/// degraded path explicit, so a down backend is never silently identical
/// to a healthy task save.
enum CaptureOutcome: Equatable {
    case task(hasDate: Bool)
    case event
    case note
    case degraded   // AI unreachable / unparseable → saved as a plain task

    var confirmation: String {
        switch self {
        case .task(let hasDate): return hasDate ? "✓ Added task · due set" : "✓ Added task"
        case .event:             return "✓ Added event"
        case .note:              return "✓ Added note"
        case .degraded:          return "⚠︎ AI offline — saved as plain task"
        }
    }
}
