import SwiftUI
import AtlasCore

/// The project a Quick-Capture entry should be force-tagged to (set by a project
/// page's "Add Task"). Carries both the space and project name so the created
/// task lands in the right project regardless of AI routing.
struct CaptureContext: Equatable {
    var spaceName: String
    var projectName: String
}

/// Single source of truth for the UI. Backed by mock data today;
/// the same surface will later be backed by Supabase (see docs/specs/01-architecture.md).
@MainActor
final class AppState: ObservableObject {
    @Published var route: Route = .dashboard

    @Published var userName: String = "Jordan"
    @Published var spaces: [Space] = MockData.spaces
    @Published var events: [CalendarEvent] = MockData.events
    @Published var tasks: [TaskItem] = MockData.tasks

    /// Tasks checked off moments ago that still linger (struck-through) in pending
    /// lists before sliding out — see `toggleTask`. Pending filters treat a task as
    /// visible while its id is in here.
    @Published var recentlyCompleted: Set<UUID> = []
    /// Per-task linger timers, cancelled on re-toggle so a fresh check-off always
    /// gets its full 0.9s.
    private var lingerTasks: [UUID: Task<Void, Never>] = [:]
    /// Per-task done-write chain — rapid check→uncheck must persist in order.
    private var doneWrites: [UUID: Task<Void, Never>] = [:]
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

    /// Last Canvas sync error (nil when the most recent sync succeeded or Canvas is disconnected).
    @Published var lastCanvasSyncError: String? = nil

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

    /// EventKit access for Apple Calendar write-back (editing Apple-origin events + the
    /// optional Atlas→Apple mirror). EventKit identifiers are stable across `EKEventStore`
    /// instances on the same device, so this owns its own store independent of the read path.
    let eventKit = EventKitService()

    /// Cross-device preference sync (user_settings, 0025). Owned here so the
    /// bootstrap/foreground pull and the Settings/RootView push share one cache
    /// (`lastPulledRow`) — the push overlays local changes onto it.
    let settingsSync = SettingsSyncService()

    /// Debounced push of the synced preferences after a user-initiated change —
    /// the one entry point SettingsView/RootView `.onChange` handlers call.
    func pushSyncedSettings() {
        guard let db else { return }
        Task { await settingsSync.push(db: db) }
    }

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

    /// All of the user's connected Google accounts (multi-account, 0028). Empty ⇒ no
    /// Google connection. Drives Settings' CALENDARS list (per-connection rows + detail).
    @Published var googleConnections: [GoogleConnection] = []

    /// Re-reads every cloud connection and updates the server-owned gate. Cloud sync is
    /// now implicit per connection: the server owns Google↔DB sync whenever ANY connection
    /// exists and isn't `revoked`, so the Mac stands its local Google writers down.
    /// Never throws to the caller and never flips to a state that could create a second
    /// Google writer: on a read failure the persisted gate is left untouched.
    func refreshGoogleConnections() async {
        guard let db else { return }
        do {
            let conns = try await db.loadGoogleConnections()
            self.googleConnections = conns
            self.serverSyncEnabled = conns.contains { $0.status != "revoked" }
        } catch {
            print("[AtlasDB] google_connections read failed — keeping current sync mode. Error: \(error.localizedDescription)")
        }
    }

    /// The Google account (connection) an event's space routes OUT to, or nil when the
    /// space is linked to no account (the event then stays in Atlas). One space maps to
    /// at most one connection (unique `space_id`, 0028).
    func connectionId(forSpaceId spaceId: UUID?) -> UUID? {
        guard let spaceId else { return nil }
        return googleConnections.first { $0.spaceId == spaceId }?.id
    }

    /// Snapshot of the user's `canvas_connections` row (nil = no Canvas connection).
    /// Drives Settings' Canvas "Last synced Xm ago" / error + paste-form UI. There is
    /// no client-side Canvas polling to stand down: the old `CanvasService` only
    /// validated a token and never imported, so this is a display signal only (unlike
    /// `serverSyncEnabled`, which gates the Mac's live Google writers).
    @Published var canvasConnection: CanvasConnectionRow?

    /// The signed-in user's public identity (collab). Nil until loaded.
    @Published var profile: ProfileRow? = nil

    /// Invites addressed to me, awaiting accept/decline (collab phase 2).
    @Published var pendingInvites: [InviteRow] = []
    /// Membership rosters for shared projects, keyed by project id.
    @Published var projectMembers: [UUID: [ProjectMemberRow]] = [:]
    /// Projects owned by someone else that I'm a member of — surfaced in the
    /// sidebar's "Shared with me" section, never nested under my own spaces.
    @Published var sharedWithMeProjects: [Project] = []

    /// True once a project has more than just its owner as a member — drives
    /// the sidebar's shared-project marker and the Team-view affordances.
    func isShared(_ project: Project) -> Bool {
        (projectMembers[project.id]?.count ?? 0) > 1
    }

    /// Membership rosters for shared spaces, keyed by space id — mirrors
    /// `projectMembers` one level up.
    @Published var spaceMembers: [UUID: [SpaceMemberRow]] = [:]

    /// True once a space has more than just its owner as a member.
    func isSharedSpace(_ space: Space) -> Bool {
        (spaceMembers[space.id]?.count ?? 0) > 1
    }

    /// True if `blocks`' most recent `updatedAt` is more than 48h old — the
    /// Team view shows a quiet "as of <day>" annotation instead of pretending
    /// a stale window is current.
    func isStale(_ blocks: [AvailabilityBlockRow], now: Date = Date()) -> Bool {
        guard let mostRecent = blocks.compactMap({ ReferenceRow.date(from: $0.updatedAt) }).max() else { return true }
        return now.timeIntervalSince(mostRecent) > 48 * 3600
    }

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
    private var bootstrappedUser: String?

    /// Quick-capture pill presentation (toggled by the ⌘ hotkey / Tasks card).
    @Published var presentCapture: Bool = false

    /// When set (by a project page's "Add Task"), the next Quick-Capture entry is
    /// force-tagged to this project/space instead of AI-routed — so a task added
    /// from a project always lands in that project. Cleared when capture dismisses.
    @Published var captureContext: CaptureContext? = nil

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

    /// Periodic timer that re-publishes availability hourly, mirroring `clockTimer`'s
    /// pattern. Invalidated in `deinit` alongside `clockTimer`.
    private var availabilityPublishTimer: Timer?

    /// Pending debounced `publishAvailability()` call, restarted by `schedulePublish()`
    /// on every local calendar/task mutation so a burst of edits collapses into one publish.
    private var publishDebounceTask: Task<Void, Never>?

    init() {
        // Expand the first two spaces by default (matches the prototype).
        expandedSpaces = Set(spaces.prefix(2).map(\.id))
        startClock()
    }

    deinit {
        clockTimer?.invalidate()
        availabilityPublishTimer?.invalidate()
        publishDebounceTask?.cancel()
    }

    /// Starts (or restarts) the 60 s clock that publishes `now`. Idempotent.
    func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    /// Starts (or restarts) the hourly timer that re-publishes availability, in case a
    /// local edit's debounce was missed (e.g. the app was asleep). Idempotent.
    func startAvailabilityPublishTimer() {
        availabilityPublishTimer?.invalidate()
        availabilityPublishTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.publishAvailability() }
        }
    }

    /// Debounces `publishAvailability()` so a burst of local calendar/task edits
    /// (e.g. dragging a task across several slots) collapses into a single publish,
    /// 5 s after the last change. Called from the calendar/task mutation points below.
    func schedulePublish() {
        publishDebounceTask?.cancel()
        publishDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.publishAvailability()
        }
    }

    /// Publishes the next 14 days of anonymized busy intervals derived from
    /// `events`, `externalEvents` (Apple/Google), and scheduled task work-blocks
    /// combined — fire-and-forget, never throws to the caller. Delete-then-insert
    /// on the server keeps this self-healing with no per-event diffing.
    func publishAvailability() async {
        guard let db, let userId = try? await db.currentUserId() else { return }
        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: Date())
        guard let windowEnd = cal.date(byAdding: .day, value: 14, to: windowStart) else { return }

        var relevant = (events + externalEvents).filter { $0.start >= windowStart && $0.start < windowEnd }
        var day = windowStart
        while day < windowEnd {
            relevant += scheduledWorkBlocks(on: day)
            day = cal.date(byAdding: .day, value: 1, to: day) ?? windowEnd
        }

        var blocks = AvailabilityDerivation.busyBlocks(from: relevant, excludingDeadlines: true)
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for i in blocks.indices {
            blocks[i].userId = userId
            blocks[i].updatedAt = nowISO
        }
        try? await db.publishAvailability(blocks, windowStart: windowStart, windowEnd: windowEnd)
    }

    /// Teammates' published availability, keyed by user id. Populated per-
    /// project on demand (Team view calls this when it appears), not eagerly
    /// for every project on every load.
    @Published var teammateAvailability: [UUID: [AvailabilityBlockRow]] = [:]

    /// Loads the next 14 days of availability for every OTHER member of
    /// `project` (excluding the signed-in user, whose own `events` are
    /// already the source of truth locally).
    func loadTeammateAvailability(forProject project: Project) async {
        guard let db, let myUserId = try? await db.currentUserId() else { return }
        let memberIds = (projectMembers[project.id] ?? []).map(\.userId).filter { $0 != myUserId }
        guard !memberIds.isEmpty else { return }
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date())
        guard let to = cal.date(byAdding: .day, value: 14, to: from) else { return }
        let blocks = (try? await db.loadAvailability(forProjectMemberIds: memberIds, from: from, to: to)) ?? []
        teammateAvailability = Dictionary(grouping: blocks, by: \.userId)
    }

    // MARK: - Supabase Bootstrap

    /// Load all persisted data for the signed-in user. Starter content for a
    /// fresh account is seeded SERVER-SIDE (migration 0024's signup trigger),
    /// so this only loads. On any failure keeps the existing in-memory MockData
    /// so the UI is never left blank. Stores the `db` reference for write-through.
    /// Keyed on `userID` so signing into a different account re-loads instead of
    /// keeping (and writing into) the previous user's data.
    func bootstrap(db: AtlasDB, userID: String?) async {
        guard bootstrappedUser != userID else { return }
        // Account switch (a different user was bootstrapped this session): blank the
        // in-memory model NOW, before the new user's `loadAll()` returns, so the
        // previous account's tasks/events can never flash under the new identity. The
        // local model is the only cross-account cache — there's no on-disk store to
        // namespace — so dropping it is the whole fix. A first bootstrap (previous nil)
        // keeps MockData, preserving the never-blank-on-error posture below.
        if bootstrappedUser != nil { clearUserData() }
        bootstrappedUser = userID
        self.db = db
        do {
            let snapshot = try await db.loadAll()

            applySnapshot(snapshot)

            // Re-seed sidebar expansion to first 2 loaded space ids
            // (old MockData ids no longer match after DB load).
            expandedSpaces = Set(self.spaces.prefix(2).map(\.id))

        } catch {
            // Keep existing in-memory MockData — never blank the UI on a DB error.
            // Reset the guard so the next appearance/sign-in retries the load.
            print("[AtlasDB] bootstrap failed — keeping MockData. Error: \(error.localizedDescription)")
            bootstrappedUser = nil
        }

        // Bootstrap tail: profile, collab, Google, and Canvas are independent
        // loads — kick them off concurrently (was four serial awaits) so their
        // network round-trips overlap. Realtime sync reads collab's
        // `sharedWithMeProjects`, so it still runs only after collab completes.
        //   • profile — collab phase 1: surface the user's profile (created by
        //     the signup trigger). Nil = migration not deployed; degrade silently.
        async let profileRow = self.db?.loadProfile()
        async let collabDone: Void = self.loadCollabState()
        async let googleDone: Void = self.refreshGoogleConnections()  // Google sync mode from the cloud connections
        async let canvasDone: Void = self.refreshCanvasConnection()   // Canvas status for Settings from launch

        self.profile = try? await profileRow
        await collabDone
        await startRealtimeSync(supabaseURL: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
        await googleDone
        await canvasDone

        // Pull cross-device preferences (server wins). Best-effort: no-ops until the
        // user_settings table is deployed.
        await settingsSync.pullAndApply(db: db)

        // Collab phase 3: publish this device's derived availability, then keep it
        // fresh on an hourly timer (local edits also trigger a debounced publish).
        await publishAvailability()
        startAvailabilityPublishTimer()
    }

    /// Blanks every user-scoped model array so a signed-out / just-switched account
    /// leaves nothing of the previous user's data on screen. Called on account switch
    /// from `bootstrap`; the fresh `loadAll()` (or a re-sign-in) repopulates.
    private func clearUserData() {
        spaces = []
        tasks = []
        events = []
        notes = []
        goals = []
        references = []
        referenceAttachments = []
        externalEvents = []
        googleConnections = []
        canvasConnection = nil
        profile = nil
        pendingInvites = []
        projectMembers = [:]
        sharedWithMeProjects = []
        spaceMembers = [:]
        teammateAvailability = [:]
        expandedSpaces = []
        calendarDetailItem = nil
    }

    /// Assigns a freshly loaded `AtlasSnapshot` onto the published model arrays —
    /// re-nesting projects into spaces and re-deriving colors from spaceName.
    /// Shared by initial `bootstrap(db:)` and the realtime refetch path so both
    /// apply a snapshot identically.
    private func applySnapshot(_ snapshot: AtlasSnapshot) {
        // Re-nest flat projects into their parent spaces — spaceID is
        // authoritative, spaceName is the pre-0015 fallback (SpaceNesting).
        let nestedSpaces = SpaceNesting.nest(projects: snapshot.projects, into: snapshot.spaces)

        // Debug: log any projects that landed in no space.
        let nestedIDs = Set(nestedSpaces.flatMap { $0.projects.map(\.id) })
        let orphanCount = snapshot.projects.filter { !nestedIDs.contains($0.id) }.count
        if orphanCount > 0 {
            print("[AtlasDB] \(orphanCount) project(s) match no loaded space — they will not appear in the sidebar.")
        }

        // Assign to @Published properties (already on @MainActor).
        self.spaces = nestedSpaces
        self.tasks  = snapshot.tasks
        self.events = snapshot.events
        self.notes  = snapshot.notes
        self.goals  = snapshot.goals
        self.references = snapshot.references
        self.referenceAttachments = snapshot.referenceAttachments

        // Re-derive every denormalized color from the loaded space colors
        // (spaces already carry real colors from `color_token`).
        rederiveDerivedColors()
    }

    /// The single color-resolution pass: re-derive every denormalized color from
    /// the live space colors. Shared by snapshot load and `setSpaceColor` so a
    /// space recolor ripples to exactly the same surfaces a fresh load would —
    /// events, tasks, nested project colors, and their Canvas assignments — with
    /// no view left resolving a stale copy. Space colors themselves are the
    /// source of truth here (loaded from `color_token`); this never touches them.
    private func rederiveDerivedColors() {
        for i in events.indices {
            events[i].color = calendarSpaceColor(named: events[i].spaceName)
        }
        for i in tasks.indices {
            tasks[i].spaceColor = calendarSpaceColor(named: tasks[i].spaceName)
        }
        for si in spaces.indices {
            let spaceColor = spaces[si].color
            for pi in spaces[si].projects.indices {
                spaces[si].projects[pi].spaceColor = spaceColor
                for ai in spaces[si].projects[pi].assignments.indices {
                    spaces[si].projects[pi].assignments[ai].spaceColor = spaceColor
                }
            }
        }
    }

    /// Realtime subscriptions for shared-project tables (tasks/events/notes) — nil
    /// until `startRealtimeSync` runs.
    private var realtimeSync: RealtimeSyncService?

    /// Starts realtime subscriptions for every shared project the user
    /// currently belongs to. Called once after `loadCollabState()` populates
    /// `spaces`/membership, and safe to re-call whenever that set changes (e.g.
    /// after accepting a new invite) — always tears down prior subscriptions first.
    func startRealtimeSync(supabaseURL: URL, anonKey: String) async {
        await realtimeSync?.unsubscribeAll()
        // Include projects shared TO me (not just ones I own and shared out) —
        // those live only in `sharedWithMeProjects`, never in `spaces`, so
        // `isShared` alone misses exactly the case that matters: seeing a
        // teammate's live edits on a project they invited me to.
        let sharedProjectIds = spaces.flatMap { $0.projects }.filter(isShared).map(\.id)
            + sharedWithMeProjects.map(\.id)
        guard !sharedProjectIds.isEmpty,
              let accessToken = try? await db?.currentAccessToken() else { return }
        let sync = RealtimeSyncService(supabaseURL: supabaseURL, anonKey: anonKey, accessToken: accessToken)
        await sync.subscribe(projectIds: sharedProjectIds) { [weak self] in
            Task { @MainActor in
                await self?.loadCollabState()
                // Re-load the full snapshot too, since a teammate's change to
                // a shared task/event/note needs to show up in the normal
                // tasks/events/notes arrays, not just the membership state.
                if let db = self?.db, let snapshot = try? await db.loadAll() {
                    self?.applySnapshot(snapshot)
                }
            }
        }
        self.realtimeSync = sync
    }

    /// Loads pending invites and every visible project's membership roster.
    /// Fire-and-forget from bootstrap, same degrade-silently posture as
    /// Phase 1's profile load — a pre-migration environment (table missing)
    /// must not crash or spam errors here.
    func loadCollabState() async {
        guard let db else { return }
        self.pendingInvites = (try? await db.loadPendingInvites()) ?? []

        // One round-trip for every visible membership row, grouped by project,
        // instead of one fetch-and-filter per project. Keep the dict shape
        // identical to before — a key (defaulting to []) for each of my
        // projects — so `isShared`/the sidebar see exactly today's values.
        let membersByAllProjects = (try? await db.loadAllProjectMembers()) ?? [:]
        var membersByProject: [UUID: [ProjectMemberRow]] = [:]
        for space in spaces {
            for project in space.projects {
                membersByProject[project.id] = membersByAllProjects[project.id] ?? []
            }
        }
        self.projectMembers = membersByProject

        // One round-trip for every visible space-membership row, grouped by
        // space, mirroring the per-project fetch above — instead of one
        // fetch-and-filter per space. Spaces themselves live only in `spaces`.
        // Runs independently of the "shared with me" lookup below, which
        // needs `myUserId` and may bail early.
        let membersByAllSpaces = (try? await db.loadAllSpaceMembers()) ?? [:]
        var membersBySpace: [UUID: [SpaceMemberRow]] = [:]
        for space in spaces {
            membersBySpace[space.id] = membersByAllSpaces[space.id] ?? []
        }
        self.spaceMembers = membersBySpace

        // Projects I'm a member of but don't own land in "Shared with me",
        // not nested under any of my own spaces (they belong to someone else's).
        guard let myUserId = try? await db.currentUserId() else { return }
        let myProjectIds = Set(spaces.flatMap { $0.projects.map(\.id) })
        let memberProjectIds = Set(membersByProject.filter { _, members in
            members.contains { $0.userId == myUserId }
        }.keys).subtracting(myProjectIds)
        // Membership rosters only tell us IDs; fetch the actual project rows
        // for anything not already in `spaces` via a dedicated small query.
        self.sharedWithMeProjects = (try? await db.loadProjectsByIds(Array(memberProjectIds))) ?? []
    }

    /// Tabs of a multi-tab Doc note, ordered. Empty for single-tab docs or on error.
    func loadDocTabs(noteID: UUID) async -> [DocNoteTab] {
        guard let db else { return [] }
        return (try? await db.fetchDocNoteTabs(noteID: noteID)) ?? []
    }

    /// Re-hosted inline images of a Doc note. Empty when none, or on error.
    func loadDocImages(noteID: UUID) async -> [DocNoteImage] {
        guard let db else { return [] }
        return (try? await db.fetchDocNoteImages(noteID: noteID)) ?? []
    }

    /// Downloads one Doc-image object's bytes from Storage. Throws so the editor can
    /// fall back to the literal placeholder when the fetch fails.
    func downloadDocImage(path: String) async throws -> Data {
        guard let db else { throw AtlasDBError.notAuthenticated }
        return try await db.downloadDocImage(path: path)
    }

    /// Send a project invite. Errors are swallowed to a debug log — the
    /// invite sheet reads `pendingInvites`/a future sent-invites list to
    /// reflect success, rather than this call throwing into the UI.
    func invite(email: String, toProject projectId: UUID) async {
        guard let db else { return }
        do {
            try await db.createProjectInvite(projectId: projectId, inviteeEmail: email)
        } catch {
            print("[Collab] failed to send invite: \(error)")
        }
    }

    /// Send a space invite. Mirrors `invite(email:toProject:)` (Phase 2) —
    /// errors are swallowed to a debug log, not thrown into the UI.
    func inviteToSpace(email: String, spaceId: UUID) async {
        guard let db else { return }
        do {
            try await db.createSpaceInvite(spaceId: spaceId, inviteeEmail: email)
        } catch {
            print("[Collab] failed to send space invite: \(error)")
        }
    }

    /// Accept or decline an invite addressed to me. On accept, the server's
    /// accept_invite RPC (migration 0016) grants membership; we then reload
    /// collab state so the newly-shared project appears immediately.
    func respondToInvite(_ invite: InviteRow, accept: Bool) async {
        guard let db else { return }
        do {
            try await db.respondToInvite(id: invite.id, accept: accept)
            pendingInvites.removeAll { $0.id == invite.id }
            if accept {
                await loadCollabState()
            }
        } catch {
            print("[Collab] failed to respond to invite: \(error)")
        }
    }

    /// Claim an unassigned shared task as the signed-in user's own.
    func claimTask(_ taskId: UUID) async {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }),
              let userId = try? await db?.currentUserId() else { return }
        tasks[i].claim(by: userId)
        try? await db?.claimTask(id: taskId, assigneeId: userId)
    }

    func project(_ id: UUID) -> Project? {
        for space in spaces {
            if let match = space.projects.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Canvas assignments mirrored onto projects — they never enter `tasks`.
    var assignmentTasks: [TaskItem] {
        spaces.flatMap(\.projects).flatMap(\.assignments)
    }

    /// Task lookup across both pools: the flat store first, then project assignments.
    func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id } ?? assignmentTasks.first { $0.id == id }
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

    /// Rename a space in place and carry every item that references it along.
    /// Items reference their space by `space_name` (text), so a rename must rewrite
    /// that text on all dependent projects/tasks/events/notes — otherwise they'd
    /// detach from the renamed space (and lose their derived color). Each touched
    /// row is re-persisted individually (no server-side cascade exists). No-op on a
    /// blank/unchanged name, an unknown id, or a collision with another space's name
    /// (which would silently merge two spaces' items).
    func renameSpace(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let si = spaces.firstIndex(where: { $0.id == id }) else { return }
        let old = spaces[si].name
        guard !trimmed.isEmpty, trimmed != old else { return }
        guard !spaces.contains(where: { $0.id != id && $0.name == trimmed }) else { return }

        spaces[si].name = trimmed

        for pi in spaces[si].projects.indices where spaces[si].projects[pi].spaceName == old {
            spaces[si].projects[pi].spaceName = trimmed
            let updated = spaces[si].projects[pi]
            Task { try? await self.db?.upsertProject(updated) }
        }
        for i in tasks.indices where tasks[i].spaceName == old {
            tasks[i].spaceName = trimmed
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
        for i in events.indices where events[i].spaceName == old {
            events[i].spaceName = trimmed
            let updated = events[i]
            Task { try? await self.db?.upsertEvent(updated) }
        }
        for i in notes.indices where notes[i].spaceName == old {
            notes[i].spaceName = trimmed
            let updated = notes[i]
            Task { try? await self.db?.upsertNote(updated) }
        }

        let updatedSpace = spaces[si]
        Task { try? await self.db?.upsertSpace(updatedSpace, sort: si) }
    }

    /// Change a space's color and re-derive the color on every item that inherits it,
    /// then persist the space. Events/tasks store a resolved `Color`, so they must be
    /// re-tinted here; projects that set their own grid color keep it. Persists via
    /// `upsertSpace` (only `spaces.color_token` is stored). No-op on an unknown id.
    func setSpaceColor(id: UUID, color: Color) {
        guard let si = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[si].color = color
        // Re-derive every dependent color through the same single path a load uses,
        // so the recolor ripples everywhere at once instead of ad-hoc re-tints.
        rederiveDerivedColors()
        let updatedSpace = spaces[si]
        Task { try? await self.db?.upsertSpace(updatedSpace, sort: si) }
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
        var project = Project(
            name: name,
            code: (trimmedCode?.isEmpty == true) ? nil : trimmedCode,
            isClass: isClass,
            spaceName: spaceName,
            spaceColor: spaces[si].color,
            overview: overview
        )
        project.spaceID = spaces[si].id
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

    /// Set (or clear, with `nil`) a project's own color token and persist it.
    /// `nil` restores "inherit the space color". Searches every space; no-op if the
    /// id matches nothing. Only day-grid tiles read this — see `gridColored`.
    func setProjectColorToken(projectID: UUID, token: String?) {
        for si in spaces.indices {
            if let pi = spaces[si].projects.firstIndex(where: { $0.id == projectID }) {
                spaces[si].projects[pi].colorToken = token
                let updated = spaces[si].projects[pi]
                Task { try? await self.db?.upsertProject(updated) }
                return
            }
        }
    }

    /// Rename a project in place and rewrite the text references that point at it
    /// by name — tasks match on `projectName`, so without this a rename would
    /// detach them from the project's task list. Events primarily link by
    /// `projectID`, but ones tagged only by `subtitle == name` are re-pointed too.
    /// No-op on a blank/unchanged name or an unknown id.
    func renameProject(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        for si in spaces.indices {
            guard let pi = spaces[si].projects.firstIndex(where: { $0.id == id }) else { continue }
            let old = spaces[si].projects[pi].name
            guard !trimmed.isEmpty, trimmed != old else { return }
            let space = spaces[si].name
            spaces[si].projects[pi].name = trimmed
            let updated = spaces[si].projects[pi]
            Task { try? await self.db?.upsertProject(updated) }
            for i in tasks.indices where tasks[i].projectName == old && tasks[i].spaceName == space {
                tasks[i].projectName = trimmed
                let t = tasks[i]
                Task { try? await self.db?.upsertTask(t) }
            }
            for i in events.indices where events[i].subtitle == old && events[i].spaceName == space {
                events[i].subtitle = trimmed
                let e = events[i]
                Task { try? await self.db?.upsertEvent(e) }
            }
            return
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
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
        tasks[i].completedAt = tasks[i].done ? Date() : nil
        let updated = tasks[i]
        lingerTasks[id]?.cancel()   // a re-toggle must not inherit the old timer
        if updated.done {
            // Mirror mobile: the checked row lingers ~0.9s (struck-through, filled
            // check) in pending lists before sliding out, so completion is felt.
            recentlyCompleted.insert(id)
            lingerTasks[id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                _ = withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.recentlyCompleted.remove(id)
                }
                self.lingerTasks[id] = nil
            }
        } else {
            recentlyCompleted.remove(id)
        }
        // Scoped PATCH (done/completed_at only) — a check-off must never stomp a
        // collaborator's concurrent edit to the task's other columns. Chained per
        // task so a rapid check→uncheck can't land out of order, with a full-
        // upsert fallback when the row never reached the DB (offline capture).
        let previousWrite = doneWrites[id]
        doneWrites[id] = Task { @MainActor in
            await previousWrite?.value
            guard let db = self.db else { return }
            let matched = (try? await db.setTaskDone(id: id, done: updated.done,
                                                     completedAt: updated.completedAt)) ?? false
            if !matched { try? await db.upsertTask(updated) }
        }
    }

    /// The one authoritative spelling of the linger rule — a task shows in pending
    /// lists while open OR just-checked and lingering; it settles into completed
    /// lists only after the linger ends. Every pending/completed filter uses these.
    func isVisiblyPending(_ task: TaskItem) -> Bool {
        !task.done || recentlyCompleted.contains(task.id)
    }

    func isSettledDone(_ task: TaskItem) -> Bool {
        task.done && !recentlyCompleted.contains(task.id)
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
        task.spaceID = spaceID(named: resolvedSpace)
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

    /// Link (or clear) a task's tagged note (`noteID` — independent of the
    /// project-scoped `ReferenceAttachment` system).
    func setTaskNote(taskId: UUID, noteID: UUID?) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].noteID = noteID
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
        }
    }

    /// Move a task to a different space, syncing its brand color and dropping a
    /// project that doesn't belong to the new space (the project picker re-scopes).
    func setTaskSpace(taskId: UUID, spaceName: String) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].spaceName = spaceName
        tasks[i].spaceID = spaceID(named: spaceName)
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
            schedulePublish()
        }
    }

    /// Write-through for editing a scheduled task (its work-block) from the detail view —
    /// title / time / duration / description / note link. A work-block IS a task, so this
    /// never touches `events`; it persists the task and patches the mirrored Google block.
    func updateScheduledTask(id: UUID, title: String, start: Date, durationMin: Int,
                             notes: String?, noteID: UUID?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Canvas owns the title (re-sync overwrites it) — never rename a Canvas task here.
        if tasks[i].canvasUID == nil { tasks[i].title = title }
        tasks[i].scheduledAt = start
        tasks[i].durationMin = durationMin
        tasks[i].notes = notes ?? ""
        tasks[i].noteID = noteID
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
        schedulePublish()
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
        schedulePublish()
    }

    /// Remove a task's calendar slot, returning it to the unscheduled tray.
    func unschedule(taskId: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].scheduledAt = nil
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
            schedulePublish()
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
        var event = event
        // Route OUT by space: stamp the connection its space is linked to (nil ⇒ stays in
        // Atlas). The server's per-connection push reads this to mirror to the right account.
        event.googleConnectionId = connectionId(forSpaceId: event.spaceID)
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
        pushNewEventToApple(event)
        schedulePublish()
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
        // Writable Apple-origin events also live in `externalEvents`. Patch the EKEvent and
        // reflect optimistically — Apple events stay unpersisted (never touch Supabase) and
        // keep their `.apple` source.
        if event.source == .apple, let aid = event.appleEventId,
           !events.contains(where: { $0.id == event.id }) {
            if let i = externalEvents.firstIndex(where: { $0.id == event.id }) {
                externalEvents[i] = event
            }
            pushExternalAppleEdit(event, appleEventID: aid)
            return
        }
        // Re-route by space: resolve the new space → connection. When that connection
        // differs from the one on the stored event, the event moved between Google
        // accounts — clear the old account's google_event_id so the server tombstones it
        // there and re-creates under the new connection (existing delete/recreate mirror
        // machinery, routed by google_connection_id; no Google "move" call exists).
        var event = event
        let previousConnectionId = events.first(where: { $0.id == event.id })?.googleConnectionId
        event.googleConnectionId = connectionId(forSpaceId: event.spaceID)
        if event.googleConnectionId != previousConnectionId {
            event.googleEventId = nil
        }
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        }
        Task { try? await self.db?.upsertEvent(event) }
        pushUpdatedEventToApple(event)
        schedulePublish()
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
        // Writable Apple-origin event in the external pool — delete it on Apple and drop the
        // optimistic copy; never touch the Atlas DB.
        if let ext = externalEvents.first(where: { $0.id == id }),
           ext.source == .apple, let aid = ext.appleEventId {
            externalEvents.removeAll { $0.id == id }
            deleteAppleEvent(appleEventID: aid)
            return
        }
        let removed = events.first { $0.id == id }
        events.removeAll { $0.id == id }
        Task { try? await self.db?.deleteEvent(id: id) }
        if let removed {
            pushDeletedEventToApple(removed)
        }
        schedulePublish()
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

    /// Patches an edited writable Apple-origin event back to Apple Calendar. Unlike the
    /// Google external edit (which swallows), an EventKit failure is surfaced on the shared
    /// calendar error channel so the user knows the on-device write didn't take — the local
    /// optimistic edit already succeeded and is never blocked.
    private func pushExternalAppleEdit(_ event: CalendarEvent, appleEventID aid: String) {
        Task {
            do { try await eventKit.updateEvent(appleEventID: aid, with: event) }
            catch { surfaceAppleWriteError(error) }
        }
    }

    /// Deletes a writable Apple-origin event on Apple Calendar (when deleted in Atlas).
    private func deleteAppleEvent(appleEventID aid: String) {
        Task {
            do { try await eventKit.deleteEvent(appleEventID: aid) }
            catch { surfaceAppleWriteError(error) }
        }
    }

    /// Surfaces an EventKit write failure on the shared calendar status channel, preferring
    /// the `LocalizedError` description (EventKitWriteError conforms) over the raw message.
    private func surfaceAppleWriteError(_ error: Error) {
        lastCalendarSyncError = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    /// Removes events locally (memory + DB) **without** echoing a delete to Google — used
    /// by the sync reaper when the event was already deleted on Google. No-op on empty.
    func removeEventsLocally(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idset = Set(ids)
        events.removeAll { idset.contains($0.id) }
        for id in ids { Task { try? await self.db?.deleteEvent(id: id) } }
        schedulePublish()
    }

    // MARK: - Apple Calendar write-back (Atlas → Apple, device-local mirror)
    //
    // Optional mirror of user-created Atlas events into a chosen Apple calendar, gated by
    // the DEVICE-LOCAL `calendar.apple.writeback` toggle (EventKit is per-device, so it is
    // never synced across devices). Mirrors the Google trio: new / update / delete push the
    // event and stamp the returned `eventIdentifier` into `appleEventId`, which — unlike the
    // Google id — is persisted via `db.upsertEvent` (migration 0026) so later edits patch the
    // same EKEvent and the read-back de-dupes it (CalendarSync.excludingOwnMirrors) instead of
    // double-displaying. Failures are swallowed: the local edit already succeeded.

    /// The chosen destination calendar for mirrored events; `nil` (unset / empty) falls back
    /// to Apple's default calendar for new events inside `EventKitService.createEvent`.
    private var appleWritebackCalendarId: String? {
        let id = UserDefaults.standard.string(forKey: "calendar.apple.writeback.calendarId")
        return (id?.isEmpty ?? true) ? nil : id
    }

    /// True only for user-created Atlas events while the mirror is on and access is granted.
    private func shouldWriteBackApple(_ event: CalendarEvent) -> Bool {
        CalendarSync.shouldWriteBackApple(
            enabled: UserDefaults.standard.bool(forKey: "calendar.apple.writeback"),
            authorized: eventKit.authorizationStatus() == .fullAccess,
            event: event)
    }

    /// Pushes existing Atlas-origin events that were never mirrored (no `appleEventId`) to
    /// Apple — fired when the mirror toggle flips on so it backfills, not just new events.
    /// Safe to call repeatedly: events that already gained an id are skipped.
    func backfillEventsToApple() {
        for event in events where event.source == .atlas && event.appleEventId == nil {
            pushNewEventToApple(event)
        }
    }

    private func pushNewEventToApple(_ event: CalendarEvent) {
        guard shouldWriteBackApple(event), event.appleEventId == nil else { return }
        Task { @MainActor in
            guard let aid = try? await eventKit.createEvent(event, calendarId: appleWritebackCalendarId),
                  !aid.isEmpty else { return }
            self.stampAppleEventId(aid, on: event.id)
        }
    }

    private func pushUpdatedEventToApple(_ event: CalendarEvent) {
        guard shouldWriteBackApple(event) else { return }
        Task { @MainActor in
            if let aid = event.appleEventId, !aid.isEmpty {
                try? await eventKit.updateEvent(appleEventID: aid, with: event)
            } else {
                // On before the event existed (or backfilled) — create now.
                guard let aid = try? await eventKit.createEvent(event, calendarId: appleWritebackCalendarId),
                      !aid.isEmpty else { return }
                self.stampAppleEventId(aid, on: event.id)
            }
        }
    }

    private func pushDeletedEventToApple(_ event: CalendarEvent) {
        guard shouldWriteBackApple(event), let aid = event.appleEventId, !aid.isEmpty else { return }
        Task { try? await eventKit.deleteEvent(appleEventID: aid) }
    }

    /// Records the freshly-created Apple id in memory AND persists it (0026) so the id
    /// survives relaunch — without this the column stays NULL and the mirror duplicates.
    private func stampAppleEventId(_ aid: String, on eventID: UUID) {
        guard let i = events.firstIndex(where: { $0.id == eventID }) else { return }
        events[i].appleEventId = aid
        let persisted = events[i]
        Task { try? await self.db?.upsertEvent(persisted) }
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
