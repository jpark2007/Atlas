import SwiftUI

/// Single source of truth for the UI. Backed by mock data today;
/// the same surface will later be backed by Supabase (see docs/specs/01-architecture.md).
@MainActor
final class AppState: ObservableObject {
    @Published var route: Route = .dashboard

    @Published var userName: String = "Jordan"
    @Published var spaces: [Space] = MockData.spaces
    @Published var events: [CalendarEvent] = MockData.events
    @Published var tasks: [TaskItem] = MockData.tasks
    @Published var notes: [Note] = MockData.notes
    @Published var goals: [Goal] = MockData.goals

    /// Quick-capture pill presentation (toggled by the ⌘ hotkey / Tasks card).
    @Published var presentCapture: Bool = false

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

    // MARK: - Calendar / capture surface (shared by Stage 1 screens)

    /// Events occurring on the given day, sorted by start time.
    func events(on day: Date) -> [CalendarEvent] {
        events
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Today's events, sorted — the Dashboard schedule reads this.
    var todaysEvents: [CalendarEvent] { events(on: Date()) }

    /// Open to-dos with no time yet — the calendar's drag-to-schedule tray.
    var unscheduledTasks: [TaskItem] {
        tasks.filter { $0.scheduledAt == nil && !$0.done }
    }

    /// Quick-capture entry point. Appends a task; AI bucketing wires in at Stage 3.
    @discardableResult
    func addTask(title: String) -> TaskItem {
        let task = TaskItem(title: title, dueLabel: "")
        tasks.append(task)
        return task
    }

    /// Place an unscheduled task onto the calendar at `date` (drag-to-schedule).
    func schedule(taskId: UUID, at date: Date) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].scheduledAt = date
        }
    }
}
