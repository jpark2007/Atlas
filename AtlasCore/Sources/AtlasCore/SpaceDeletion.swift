import Foundation

/// Whether a space may be deleted. Only an EMPTY space goes: deleting never
/// takes anyone's projects, tasks, events or notes with it — the user moves or
/// deletes those first. An item belongs to a space by `spaceID` or, for rows
/// written before 0015, by `spaceName` (either match counts, erring toward keeping).
public enum SpaceDeletion {
    public enum Verdict: Equatable {
        case allowed
        /// The app assumes at least one space exists (every task lands in a real one).
        case lastSpace
        /// Other people are members — deleting would pull it out from under them.
        case shared
        case notEmpty(projects: Int, tasks: Int, events: Int, notes: Int)

        /// The message shown when deletion is refused; nil when it's allowed.
        public var blockedReason: String? {
            switch self {
            case .allowed:
                return nil
            case .lastSpace:
                return "This is your only space. Create another space before deleting this one."
            case .shared:
                return "This space is shared with other people. Remove its members before deleting it."
            case let .notEmpty(projects, tasks, events, notes):
                let parts = [(projects, "project"), (tasks, "task"), (events, "event"), (notes, "note")]
                    .filter { $0.0 > 0 }
                    .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
                return "This space still has \(parts.joined(separator: ", ")). Move or delete them first — only an empty space can be deleted."
            }
        }
    }

    public static func verdict(for space: Space,
                               allSpaces: [Space],
                               tasks: [TaskItem],
                               events: [CalendarEvent],
                               notes: [Note],
                               isShared: Bool) -> Verdict {
        guard allSpaces.count > 1 else { return .lastSpace }
        guard !isShared else { return .shared }
        let taskCount  = tasks.filter  { $0.spaceID == space.id || $0.spaceName == space.name }.count
        let eventCount = events.filter { $0.spaceID == space.id || $0.spaceName == space.name }.count
        let noteCount  = notes.filter  { $0.spaceID == space.id || $0.spaceName == space.name }.count
        guard space.projects.isEmpty, taskCount == 0, eventCount == 0, noteCount == 0 else {
            return .notEmpty(projects: space.projects.count, tasks: taskCount,
                             events: eventCount, notes: noteCount)
        }
        return .allowed
    }
}
