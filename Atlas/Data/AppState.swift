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

    /// Supabase persistence layer — nil when offline / not yet bootstrapped.
    /// `internal` (not `private`) so that `AppState+*.swift` extensions can
    /// fire write-through Tasks without crossing Swift's file-private boundary.
    var db: AtlasDB?

    /// Guards against double-bootstrap if `bootstrap(db:)` is called more than once.
    private var didBootstrap = false

    /// Quick-capture pill presentation (toggled by the ⌘ hotkey / Tasks card).
    @Published var presentCapture: Bool = false

    /// ⌘K command palette / search presentation.
    @Published var presentSearch: Bool = false

    /// Account / integrations settings sheet.
    @Published var presentSettings: Bool = false

    /// Metrics popup sheet.
    @Published var presentMetrics: Bool = false

    /// External (read-only) events aggregated from Apple Calendar. Never persisted.
    @Published var externalEvents: [CalendarEvent] = []

    /// Event editor sheet — set `eventEditorSeed` first, then flip `presentEventEditor`.
    @Published var presentEventEditor: Bool = false
    @Published var eventEditorSeed: CalendarEvent? = nil

    /// Which spaces are expanded in the sidebar.
    @Published var expandedSpaces: Set<UUID> = []

    /// A coarse "now" the UI can observe so time-derived state (the unscheduled
    /// tray's resurface rule, the grid's scheduled-task rendering) refreshes as
    /// slots pass. Updated every 60 s by `startClock()`.
    @Published var now: Date = Date()
    private var clockTimer: Timer?

    init() {
        // Expand the first two spaces by default (matches the prototype).
        expandedSpaces = Set(spaces.prefix(2).map(\.id))
        startClock()
    }

    deinit { clockTimer?.invalidate() }

    /// Starts (or restarts) the 60 s clock that publishes `now`. Idempotent.
    func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    // MARK: - Supabase Bootstrap

    /// Load all persisted data for the signed-in user. Seeds from MockData on
    /// first run (empty DB). On any failure keeps the existing in-memory MockData
    /// so the UI is never left blank. Stores the `db` reference for write-through.
    func bootstrap(db: AtlasDB) async {
        guard !didBootstrap else { return }
        didBootstrap = true
        self.db = db
        do {
            var snapshot = try await db.loadAll()

            // First-run detection: no spaces means a fresh account.
            if snapshot.spaces.isEmpty {
                // Flatten nested MockData into the AtlasSnapshot shape AtlasDB expects.
                let flatSpaces = MockData.spaces.map {
                    Space(id: $0.id, name: $0.name, color: $0.color, projects: [])
                }
                let flatProjects = MockData.spaces.flatMap { $0.projects }
                let seed = AtlasSnapshot(
                    spaces:   flatSpaces,
                    projects: flatProjects,
                    tasks:    MockData.tasks,
                    events:   MockData.events,
                    notes:    MockData.notes,
                    goals:    MockData.goals
                )
                try await db.seedInitial(seed)
                snapshot = try await db.loadAll()
            }

            // Re-nest flat projects back into their parent spaces by spaceName.
            let projectsBySpace = Dictionary(grouping: snapshot.projects, by: \.spaceName)
            var nestedSpaces = snapshot.spaces
            for i in nestedSpaces.indices {
                nestedSpaces[i].projects = projectsBySpace[nestedSpaces[i].name] ?? []
            }

            // Debug: log any projects whose spaceName has no matching loaded space.
            let loadedSpaceNames = Set(nestedSpaces.map(\.name))
            let orphanCount = snapshot.projects.filter { !loadedSpaceNames.contains($0.spaceName) }.count
            if orphanCount > 0 {
                print("[AtlasDB] \(orphanCount) project(s) have spaceName that matches no loaded space — they will not appear in the sidebar.")
            }

            // Assign to @Published properties (already on @MainActor).
            self.spaces = nestedSpaces
            self.tasks  = snapshot.tasks
            self.events = snapshot.events
            self.notes  = snapshot.notes
            self.goals  = snapshot.goals

            // Re-derive colors from spaceName.
            // Spaces already carry real colors from `color_token` — don't touch those.
            for i in self.events.indices {
                self.events[i].color = calendarSpaceColor(named: self.events[i].spaceName)
            }
            for i in self.tasks.indices {
                self.tasks[i].spaceColor = calendarSpaceColor(named: self.tasks[i].spaceName)
            }
            for i in self.spaces.indices {
                for j in self.spaces[i].projects.indices {
                    self.spaces[i].projects[j].spaceColor =
                        calendarSpaceColor(named: self.spaces[i].projects[j].spaceName)
                }
            }

            // Re-seed sidebar expansion to first 2 loaded space ids
            // (old MockData ids no longer match after DB load).
            expandedSpaces = Set(self.spaces.prefix(2).map(\.id))

        } catch {
            // Keep existing in-memory MockData — never blank the UI on a DB error.
            print("[AtlasDB] bootstrap failed — keeping MockData. Error: \(error.localizedDescription)")
        }
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
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    // MARK: - Calendar / capture surface (shared by Stage 1 screens)

    /// Events occurring on the given day, sorted by start time.
    func events(on day: Date) -> [CalendarEvent] {
        events
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// External (read-only) events occurring on the given day, sorted by start time.
    /// Mirrors `events(on:)` but draws from the non-persisted `externalEvents` pool.
    func externalEvents(on day: Date) -> [CalendarEvent] {
        externalEvents
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Today's events, sorted — the Dashboard schedule reads this.
    var todaysEvents: [CalendarEvent] { events(on: Date()) }

    /// Open to-dos that need a (new) slot — the calendar's drag-to-schedule tray.
    /// Includes never-scheduled tasks AND tasks whose slot has elapsed without
    /// being completed (non-destructive resurface; see
    /// `TaskItem.isEffectivelyUnscheduled(now:)`). Completed tasks are excluded.
    var unscheduledTasks: [TaskItem] {
        tasks.filter { $0.isEffectivelyUnscheduled(now: now) && !$0.done }
    }

    /// Quick-capture entry point. Appends a task with an optional structured due date.
    @discardableResult
    func addTask(title: String, dueDate: Date? = nil, durationMin: Int? = nil) -> TaskItem {
        let task = TaskItem(title: title,
                            dueLabel: TaskItem.dueLabel(for: dueDate),
                            dueDate: dueDate,
                            durationMin: durationMin)
        tasks.append(task)
        Task { try? await self.db?.upsertTask(task) }
        return task
    }

    /// Set (or clear) a task's structured due date, keeping the derived
    /// `dueLabel` in sync. Backs the manual due-date picker in the tray.
    func setDueDate(taskId: UUID, date: Date?) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].dueDate = date
            tasks[i].dueLabel = TaskItem.dueLabel(for: date)
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    /// Place an unscheduled task onto the calendar at `date` (drag-to-schedule).
    func schedule(taskId: UUID, at date: Date) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].scheduledAt = date
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    // MARK: - Event CRUD (in-memory; DB write-through layered in Task 2)

    func addEvent(_ event: CalendarEvent) {
        events.append(event)
        Task { try? await self.db?.upsertEvent(event) }
    }

    func updateEvent(_ event: CalendarEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        }
        Task { try? await self.db?.upsertEvent(event) }
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        Task { try? await self.db?.deleteEvent(id: id) }
    }

    // MARK: - Goal CRUD (in-memory; DB write-through layered in Task 2)

    func addGoal(_ goal: Goal) {
        goals.append(goal)
        Task { try? await self.db?.upsertGoal(goal) }
    }

    func updateGoal(_ goal: Goal) {
        if let i = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[i] = goal
        }
        Task { try? await self.db?.upsertGoal(goal) }
    }
}
