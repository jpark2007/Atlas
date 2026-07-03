import SwiftUI
import AtlasCore

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

    /// Docs → Notes import: the project-scoped reference pool. Empty until the
    /// notes-import migration (0013) is live and references are imported; the
    /// write-through CRUD lives in `AppState+References.swift`.
    @Published var references: [Reference] = []
    /// Reference ⇄ task/event attachments (many-to-many join rows).
    @Published var referenceAttachments: [ReferenceAttachment] = []

    /// Last Google calendar sync error (nil when the most recent pull succeeded). Set on
    /// the main actor by the calendar load path; surfaced as a small status indicator so
    /// sync failures are visible instead of silently swallowed.
    @Published var lastCalendarSyncError: String? = nil

    /// The calendar item open in the full-page detail view (a snapshot of the clicked tile).
    /// Nil when closed. Snapshotting rather than an id lets ephemeral external events open
    /// without a dangling lookup.
    @Published var calendarDetailItem: CalendarEvent? = nil

    /// Supabase persistence layer — nil when offline / not yet bootstrapped.
    /// `internal` (not `private`) so that `AppState+*.swift` extensions can
    /// fire write-through Tasks without crossing Swift's file-private boundary.
    var db: AtlasDB?

    /// Google account, attached by `AppGate` once it's in scope. Drives Calendar
    /// write-back (Atlas → Google) for user-created events when connected. `weak`
    /// because the `GoogleAuthService` is owned by the app, not by `AppState`.
    weak var googleAuth: GoogleAuthService?

    /// Wire the Google account in so event write-back can reach it.
    func attachGoogle(_ auth: GoogleAuthService) { googleAuth = auth }

    // MARK: - Server-owned Google sync (cloud sync)

    private static let serverSyncKey = "calendar.sync.serverOwned"

    /// True when the **server** owns Google↔DB sync — the Mac then makes ZERO Google
    /// API calls (single-owner invariant): every write-back / backfill / reap / poll
    /// path short-circuits, and Google events arrive as DB rows via `loadAll()`.
    /// Persisted so it is authoritative from launch (before the bootstrap select
    /// returns); re-derived from `google_connections.status` at bootstrap and flipped
    /// by the Settings "Sync in the cloud" toggle. When false: exactly today's behavior.
    @Published var serverSyncEnabled: Bool = UserDefaults.standard.bool(forKey: AppState.serverSyncKey) {
        didSet { UserDefaults.standard.set(serverSyncEnabled, forKey: AppState.serverSyncKey) }
    }

    /// Snapshot of the user's `google_connections` row (nil = no cloud connection).
    /// Drives Settings' "Last synced Xm ago" / error + Reconnect UI.
    @Published var googleConnection: GoogleConnectionRow?

    /// Re-reads the cloud connection and updates the server-owned gate. Server-owned
    /// whenever a connection exists and isn't `revoked` (see `GoogleConnectionRow`).
    /// Never throws to the caller and never flips to a state that could create a
    /// second Google writer: on a read failure the persisted gate is left untouched.
    func refreshGoogleConnection() async {
        guard let db else { return }
        do {
            let conn = try await db.loadGoogleConnection()
            self.googleConnection = conn
            self.serverSyncEnabled = conn?.isServerOwned ?? false
        } catch {
            print("[AtlasDB] google_connections read failed — keeping current sync mode. Error: \(error.localizedDescription)")
        }
    }

    /// Snapshot of the user's `canvas_connections` row (nil = no Canvas connection).
    /// Drives Settings' Canvas "Last synced Xm ago" / error + paste-form UI. There is
    /// no client-side Canvas polling to stand down: the old `CanvasService` only
    /// validated a token and never imported, so this is a display signal only (unlike
    /// `serverSyncEnabled`, which gates the Mac's live Google writers).
    @Published var canvasConnection: CanvasConnectionRow?

    /// Re-reads the Canvas connection for Settings. Never throws to the caller; on a
    /// read failure the current snapshot is left untouched. Mirrors `refreshGoogleConnection()`.
    func refreshCanvasConnection() async {
        guard let db else { return }
        do {
            self.canvasConnection = try await db.loadCanvasConnection()
        } catch {
            print("[AtlasDB] canvas_connections read failed — keeping current state. Error: \(error.localizedDescription)")
        }
    }

    /// Guards against double-bootstrap if `bootstrap(db:)` is called more than once.
    private var didBootstrap = false

    /// Quick-capture pill presentation (toggled by the ⌘ hotkey / Tasks card).
    @Published var presentCapture: Bool = false

    /// ⌘K command palette / search presentation.
    @Published var presentSearch: Bool = false

    /// Which section the full-page Settings route shows (General / Integrations / Metrics).
    @Published var settingsSection: SettingsSection = .general

    /// Obsidian-style relationship graph overlay (opened from the Metrics logo button).
    @Published var presentGraph: Bool = false

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
            self.references = snapshot.references
            self.referenceAttachments = snapshot.referenceAttachments

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

        // Re-derive server-owned Google sync mode from the cloud connection.
        await refreshGoogleConnection()
        // Load the Canvas connection so Settings shows its live status from launch.
        await refreshCanvasConnection()
    }

    func project(_ id: UUID) -> Project? {
        for space in spaces {
            if let match = space.projects.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Spaces (follow-up: add a top-level bucket)

    /// Create a new top-level Space and persist it via the existing
    /// `SpaceRow`/`AtlasDB.upsertSpace` write-through (mirrors `addProject`).
    /// `name` is trimmed; a blank/empty name is rejected (returns `nil` and
    /// appends nothing). The new space starts with no projects and is immediately
    /// usable as an AI routing bucket (capture context reads `state.spaces`).
    @discardableResult
    func addSpace(name: String, color: Color) -> Space? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let space = Space(name: trimmed, color: color, projects: [])
        let sort = spaces.count
        spaces.append(space)
        Task { try? await self.db?.upsertSpace(space, sort: sort) }
        return space
    }

    // MARK: - Projects (WS-8)

    /// Create a Project inside the Space named `spaceName` and persist it.
    /// The new project mirrors the parent space's `spaceName`/`spaceColor` so it
    /// renders and re-derives correctly. Returns `nil` (and appends nowhere) if
    /// no space matches `spaceName`.
    @discardableResult
    func addProject(toSpaceNamed spaceName: String,
                    name: String,
                    code: String? = nil,
                    isClass: Bool = false,
                    overview: String = "") -> Project? {
        guard let si = spaces.firstIndex(where: { $0.name == spaceName }) else { return nil }
        let trimmedCode = code?.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            name: name,
            code: (trimmedCode?.isEmpty == true) ? nil : trimmedCode,
            isClass: isClass,
            spaceName: spaceName,
            spaceColor: spaces[si].color,
            overview: overview
        )
        spaces[si].projects.append(project)
        Task { try? await self.db?.upsertProject(project) }
        return project
    }

    /// Update a project's overview/description in place and persist it.
    /// Searches every space; no-op if the id matches nothing.
    func updateProjectOverview(projectID: UUID, overview: String) {
        for si in spaces.indices {
            if let pi = spaces[si].projects.firstIndex(where: { $0.id == projectID }) {
                spaces[si].projects[pi].overview = overview
                let updated = spaces[si].projects[pi]
                Task { try? await self.db?.upsertProject(updated) }
                return
            }
        }
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
    /// Today's calendar entries for the dashboard schedule: store events plus the
    /// scheduled work-blocks (dragged tasks), in time order — a scheduled task is
    /// something to do, so it belongs on the schedule too.
    var todaysEvents: [CalendarEvent] {
        (events(on: Date()) + scheduledWorkBlocks(on: Date()))
            .sorted { $0.start < $1.start }
    }

    /// Scheduled tasks rendered as work-block events for `date` — the calendar's
    /// drag-to-schedule tiles. Excludes completed tasks; a scheduled block whose slot has
    /// elapsed but isn't yet overdue STAYS on the grid (rendered dimmed/"passed"). Once it is
    /// overdue AND its slot has elapsed (`needsReplan`) it leaves the grid and returns to the
    /// tray to be re-planned. Shared by the calendar grid and the dashboard.
    func scheduledWorkBlocks(on date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return tasks.compactMap { task in
            guard !task.done,
                  !task.needsReplan(now: now),
                  let at = task.scheduledAt,
                  cal.isDate(at, inSameDayAs: date) else { return nil }
            let end = cal.date(byAdding: .minute, value: task.durationMin ?? 60, to: at) ?? at
            return CalendarEvent(
                id: task.id,
                title: task.title,
                subtitle: "Scheduled",
                start: at,
                end: end,
                color: task.spaceColor,
                spaceName: task.spaceName,
                notes: task.notes,
                noteID: task.noteID,
                isWorkBlock: true
            )
        }
    }

    /// Open to-dos that need a (new) slot — the calendar's drag-to-schedule tray. Includes
    /// never-scheduled tasks AND scheduled tasks that have gone overdue with their slot
    /// elapsed (`needsReplan`), which return here (shown red) to be re-planned. A scheduled
    /// task whose slot merely passed (not yet overdue) stays on the grid, not here.
    var unscheduledTasks: [TaskItem] {
        tasks.filter { !$0.done && ($0.scheduledAt == nil || $0.needsReplan(now: now)) }
    }

    /// The space a new/quick-captured task falls into when none is otherwise chosen.
    /// Reads the `tasks.defaultSpaceName` setting, falls back to "Personal", and
    /// finally to the first space — so a created task is never space-less.
    var defaultTaskSpaceName: String {
        if let stored = UserDefaults.standard.string(forKey: "tasks.defaultSpaceName"),
           spaces.contains(where: { $0.name == stored }) {
            return stored
        }
        if spaces.contains(where: { $0.name == "Personal" }) { return "Personal" }
        return spaces.first?.name ?? "Personal"
    }

    /// Pick the real space a created task should live in — never empty. Order:
    /// 1. an explicit `hint` (AI/capture category, or caller-supplied) that names
    ///    a real space (case-insensitive), 2. a case-insensitive mention of a
    ///    space name inside `text`, 3. the configured default space.
    func resolvedTaskSpaceName(hint: String = "", text: String = "") -> String {
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty,
           let match = spaces.first(where: { $0.name.caseInsensitiveCompare(trimmedHint) == .orderedSame }) {
            return match.name
        }
        let lower = text.lowercased()
        if !lower.isEmpty,
           let mentioned = spaces.first(where: { !$0.name.isEmpty && lower.contains($0.name.lowercased()) }) {
            return mentioned.name
        }
        return defaultTaskSpaceName
    }

    /// Quick-capture entry point. Appends a task with an optional due date and space.
    /// Every task ends up in a real space (guess → default), so `spaceName` here is
    /// a HINT — the resolver matches it (or the title) against existing spaces.
    @discardableResult
    func addTask(title: String,
                 dueDate: Date? = nil,
                 durationMin: Int? = nil,
                 spaceName: String = "",
                 projectName: String = "") -> TaskItem {
        let resolvedSpace = resolvedTaskSpaceName(hint: spaceName, text: title)
        var task = TaskItem(title: title,
                            dueLabel: TaskItem.dueLabel(for: dueDate),
                            dueDate: dueDate,
                            durationMin: durationMin)
        task.spaceName = resolvedSpace
        task.spaceColor = calendarSpaceColor(named: resolvedSpace)
        task.projectName = projectName
        tasks.append(task)
        Task { try? await self.db?.upsertTask(task) }
        return task
    }

    /// Reassign a task to a different project (or clear it with "").
    func setTaskProject(taskId: UUID, projectName: String) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].projectName = projectName
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    /// Move a task to a different space, syncing its brand color and dropping a
    /// project that doesn't belong to the new space (the project picker re-scopes).
    func setTaskSpace(taskId: UUID, spaceName: String) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].spaceName = spaceName
        tasks[i].spaceColor = calendarSpaceColor(named: spaceName)
        let projects = spaces.first { $0.name == spaceName }?.projects ?? []
        if !projects.contains(where: { $0.name == tasks[i].projectName }) {
            tasks[i].projectName = ""
        }
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
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
            pushWorkBlockToGoogle(taskID: taskId)
        }
    }

    /// Mirrors a scheduled task's work-block (its planned work time) to Google — create on
    /// first schedule, patch on reschedule — storing the returned id on the task. Gated by
    /// the sync toggle. The task's *deadline* is never pushed (deadlines stay Atlas-native).
    private func pushWorkBlockToGoogle(taskID: UUID) {
        guard !serverSyncEnabled,  // work-block mirroring is Mac-owned and OFF in server mode (v1)
              UserDefaults.standard.bool(forKey: "calendar.google.enabled"),
              let auth = googleAuth, auth.isConnected,
              let i = tasks.firstIndex(where: { $0.id == taskID }),
              let at = tasks[i].scheduledAt else { return }
        let task = tasks[i]
        let end = Calendar.current.date(byAdding: .minute, value: task.durationMin ?? 60, to: at) ?? at
        let block = CalendarEvent(title: task.title, subtitle: "", start: at, end: end,
                                  color: task.spaceColor, spaceName: task.spaceName)
        let service = GoogleCalendarService(auth: auth)
        Task { @MainActor in
            if let gid = task.workBlockGoogleEventId, !gid.isEmpty {
                try? await service.updateEvent(googleEventID: gid, block)
            } else {
                guard let gid = try? await service.createEvent(block), !gid.isEmpty else { return }
                if let j = self.tasks.firstIndex(where: { $0.id == taskID }) {
                    self.tasks[j].workBlockGoogleEventId = gid
                    // Persist the freshly-created Google id so the read-back de-dupe survives
                    // relaunch — without this the column stays NULL and the block duplicates.
                    let persisted = self.tasks[j]
                    try? await self.db?.upsertTask(persisted)
                }
            }
        }
    }

    /// Write-through for editing a scheduled task (its work-block) from the detail view —
    /// title / time / duration / description / note link. A work-block IS a task, so this
    /// never touches `events`; it persists the task and patches the mirrored Google block.
    func updateScheduledTask(id: UUID, title: String, start: Date, durationMin: Int,
                             notes: String?, noteID: UUID?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].title = title
        tasks[i].scheduledAt = start
        tasks[i].durationMin = durationMin
        tasks[i].notes = notes ?? ""
        tasks[i].noteID = noteID
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
        pushWorkBlockToGoogle(taskID: id)
    }

    /// Removes a task's calendar work-block (returns it to the tray) and deletes its mirrored
    /// Google event. The task itself is kept.
    func unscheduleTask(id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let gid = tasks[i].workBlockGoogleEventId
        tasks[i].scheduledAt = nil
        tasks[i].workBlockGoogleEventId = nil
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
        if let gid, !gid.isEmpty { deleteGoogleEvent(googleEventID: gid) }
    }

    /// Remove a task's calendar slot, returning it to the unscheduled tray.
    func unschedule(taskId: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].scheduledAt = nil
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    /// Permanently delete a task (used after completion grace period).
    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        Task { try? await self.db?.deleteTask(id: id) }
    }

    /// Update a task's notes body.
    func updateTaskNotes(taskId: UUID, notes: String) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].notes = notes
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    // MARK: - Event CRUD (in-memory + DB write-through + Google write-back)

    func addEvent(_ event: CalendarEvent, attachingReferences refIDs: Set<UUID> = []) {
        events.append(event)
        // Optimistic in-memory attachments (dedup against any already present).
        var newAttachments: [ReferenceAttachment] = []
        for rid in refIDs
        where !referenceAttachments.contains(where: { $0.referenceID == rid && $0.eventID == event.id }) {
            let attachment = ReferenceAttachment(referenceID: rid, eventID: event.id)
            referenceAttachments.append(attachment)
            newAttachments.append(attachment)
        }
        // Sequence the writes: the `events` row must land before its attachments, or
        // the reference_attachments.event_id FK rejects them (they'd survive only in
        // memory until a reload dropped them).
        Task {
            try? await self.db?.upsertEvent(event)
            for attachment in newAttachments {
                try? await self.db?.upsertReferenceAttachment(attachment)
            }
        }
        pushNewEventToGoogle(event)
    }

    func updateEvent(_ event: CalendarEvent) {
        // Google-origin events live in `externalEvents`, not the Atlas store. Edit them by
        // patching Google and reflecting optimistically — never write them to the Atlas DB
        // (which would orphan a ghost row) or relabel their source.
        if event.source == .google, let gid = event.googleEventId,
           !events.contains(where: { $0.id == event.id }) {
            if let i = externalEvents.firstIndex(where: { $0.id == event.id }) {
                externalEvents[i] = event
            }
            pushExternalGoogleEdit(event, googleEventID: gid)
            return
        }
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        }
        Task { try? await self.db?.upsertEvent(event) }
        pushUpdatedEventToGoogle(event)
    }

    func deleteEvent(id: UUID) {
        // Google-origin event in the external pool — delete it on Google and drop the
        // optimistic copy; never touch the Atlas DB.
        if let ext = externalEvents.first(where: { $0.id == id }),
           ext.source == .google, let gid = ext.googleEventId {
            externalEvents.removeAll { $0.id == id }
            deleteGoogleEvent(googleEventID: gid)
            return
        }
        let removed = events.first { $0.id == id }
        events.removeAll { $0.id == id }
        Task { try? await self.db?.deleteEvent(id: id) }
        if let removed { pushDeletedEventToGoogle(removed) }
    }

    /// Patches an edited Google-origin event back to Google. Always appropriate when
    /// connected (the event came from Google) — not gated on the new-events picker.
    private func pushExternalGoogleEdit(_ event: CalendarEvent, googleEventID gid: String) {
        // Single-owner: in server mode the edit persists to Supabase; the server's
        // origin-edit pushback (I2) PATCHes it to Google — the Mac must not PATCH directly.
        guard !serverSyncEnabled, let auth = googleAuth, auth.isConnected else { return }
        let service = GoogleCalendarService(auth: auth)
        Task { try? await service.updateEvent(googleEventID: gid, event) }
    }

    /// Deletes a Google-origin event on Google (when the user deletes it in Atlas).
    private func deleteGoogleEvent(googleEventID gid: String) {
        // Single-owner: in server mode the Supabase delete drives the Google delete.
        guard !serverSyncEnabled, let auth = googleAuth, auth.isConnected else { return }
        let service = GoogleCalendarService(auth: auth)
        Task { try? await service.deleteEvent(googleEventID: gid) }
    }

    /// Removes events locally (memory + DB) **without** echoing a delete to Google — used
    /// by the sync reaper when the event was already deleted on Google. No-op on empty.
    func removeEventsLocally(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idset = Set(ids)
        events.removeAll { idset.contains($0.id) }
        for id in ids { Task { try? await self.db?.deleteEvent(id: id) } }
    }

    // MARK: - Google Calendar write-back (Atlas → Google)
    //
    // Only user-created Atlas events are mirrored — never external/read-only
    // events (Apple/Google reads live in `externalEvents`, not `events`). All
    // calls no-op until the account is connected. The Google event id is held in
    // memory on the `CalendarEvent`; durable persistence (an events-table column
    // + migration) is deferred to the live-Google session, so after a relaunch an
    // edit re-creates rather than patches. Failures are swallowed: write-back must
    // never block the local edit, which already succeeded.

    /// True only for user-created events while the account is connected.
    private func shouldWriteBack(_ event: CalendarEvent) -> Bool {
        // Single-owner invariant: when the server owns Google↔DB sync, the Mac never
        // writes to Google. Gates the new / update / delete push paths below.
        guard !serverSyncEnabled else { return false }
        guard let auth = googleAuth, auth.isConnected else { return false }
        // Gated by the single "Sync calendar with Google" toggle (calendar.google.enabled).
        guard UserDefaults.standard.bool(forKey: "calendar.google.enabled") else { return false }
        return !event.isReadOnly
    }

    /// Pushes existing Atlas-origin events that were never mirrored (no `googleEventId`)
    /// to Google — used when the user turns sync on so the toggle backfills, not just
    /// new events. Safe to call repeatedly: events that gained an id are skipped, and the
    /// reaper's pre-fetch snapshot guards a just-backfilled event from an in-flight pull.
    func backfillEventsToGoogle() {
        // Single-owner: when the server owns sync it does the backfill, not the Mac.
        guard !serverSyncEnabled else { return }
        for event in events where event.source == .atlas && event.googleEventId == nil {
            pushNewEventToGoogle(event)
        }
    }

    private func pushNewEventToGoogle(_ event: CalendarEvent) {
        guard shouldWriteBack(event), event.googleEventId == nil, let auth = googleAuth else { return }
        let service = GoogleCalendarService(auth: auth)
        Task { @MainActor in
            guard let gid = try? await service.createEvent(event), !gid.isEmpty else { return }
            // Remember the Google id so later edits patch instead of duplicating.
            if let i = self.events.firstIndex(where: { $0.id == event.id }) {
                self.events[i].googleEventId = gid
            }
        }
    }

    private func pushUpdatedEventToGoogle(_ event: CalendarEvent) {
        guard shouldWriteBack(event), let auth = googleAuth else { return }
        let service = GoogleCalendarService(auth: auth)
        Task { @MainActor in
            if let gid = event.googleEventId, !gid.isEmpty {
                try? await service.updateEvent(googleEventID: gid, event)
            } else {
                // Connected but never pushed (e.g. created before connecting) — create now.
                guard let gid = try? await service.createEvent(event), !gid.isEmpty else { return }
                if let i = self.events.firstIndex(where: { $0.id == event.id }) {
                    self.events[i].googleEventId = gid
                }
            }
        }
    }

    private func pushDeletedEventToGoogle(_ event: CalendarEvent) {
        guard shouldWriteBack(event), let auth = googleAuth,
              let gid = event.googleEventId, !gid.isEmpty else { return }
        let service = GoogleCalendarService(auth: auth)
        Task { try? await service.deleteEvent(googleEventID: gid) }
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
