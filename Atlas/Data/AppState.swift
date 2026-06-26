import SwiftUI

/// Single source of truth for the UI. Backed by mock data today;
/// the same surface will later be backed by Supabase (see docs/specs/01-architecture.md).
@MainActor
final class AppState: ObservableObject {
    @Published var route: Route = .dashboard

    @Published var userName: String = "Jordan"
    @Published var spaces: [Space] = MockData.spaces
    @Published var schedule: [ScheduleEntry] = MockData.schedule
    @Published var tasks: [TaskItem] = MockData.tasks
    @Published var goals: [Goal] = MockData.goals

    /// Which spaces are expanded in the sidebar.
    @Published var expandedSpaces: Set<UUID> = []

    init() {
        // Expand the first two spaces by default (matches the prototype).
        expandedSpaces = Set(spaces.prefix(2).map(\.id))
    }

    func project(_ id: UUID) -> Project? {
        for space in spaces {
            if let match = space.projects.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    func toggleSpace(_ id: UUID) {
        if expandedSpaces.contains(id) {
            expandedSpaces.remove(id)
        } else {
            expandedSpaces.insert(id)
        }
    }

    func toggleTask(_ id: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].done.toggle()
        }
    }
}
