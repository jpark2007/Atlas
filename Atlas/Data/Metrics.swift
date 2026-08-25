import SwiftUI
import AtlasCore

/// `AtlasMetrics`'s AppState entry-point. The computation itself is pure and lives in
/// `AtlasCore.Metrics`; this only decides which of AppState's pools it reads.
extension AtlasMetrics {

    @MainActor
    static func compute(from state: AppState) -> AtlasMetrics {
        // Class meetings exist only while School is on and a term is active — the same
        // gate the calendar's own synthesis uses, so Metrics counts exactly the meetings
        // the grid draws.
        let term = state.schoolEnabled ? state.activeTerm : nil
        return compute(
            tasks:  state.tasks,
            // `externalEvents` (Apple, in-memory only) joins the stored pool so a meeting
            // that lives in Apple Calendar still counts. It is loaded for whichever range
            // the Calendar screen last showed, so its coverage of this week can be partial —
            // never wrong, only incomplete. Dedup keeps a Google-synced copy from counting twice.
            events: state.events + state.externalEvents,
            goals:  state.goals,
            spaces: state.spaces,
            notes:  state.notes,
            classes: term.map { state.classes(in: $0) } ?? [],
            term:   term
        )
    }
}
