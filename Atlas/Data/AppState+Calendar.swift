import SwiftUI

/// Calendar-feature helpers on the shared store. METHODS ONLY (no stored
/// properties) so this stays additive and merge-safe. The event/task source of
/// truth lives on `AppState` itself (`events`, `events(on:)`, `unscheduledTasks`,
/// `schedule(taskId:at:)`); these are just lookups the Calendar UI needs.
extension AppState {

    /// Brand color for a space name, falling back to the accent.
    func calendarSpaceColor(named name: String) -> Color {
        spaces.first { $0.name == name }?.color ?? AtlasTheme.Colors.accent
    }

    /// Reverse-map a space color back to its name (used to give a just-scheduled
    /// task a `spaceName` so the space filter still applies to it).
    func calendarSpaceName(matching color: Color) -> String {
        spaces.first { $0.color == color }?.name ?? ""
    }
}
