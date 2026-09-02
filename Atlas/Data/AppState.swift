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

    /// Quick-capture history for the signed-in user (newest first, capped). Loaded
    /// from Application Support on bootstrap; see `CaptureHistory.swift` (which owns
    /// the record / undo / persistence logic in an extension).
    @Published var captureHistory: [CaptureHistoryEntry] = []

    /// School terms (0042). Loaded with the snapshot; empty until the user has one.
    /// Classes hang off these — see `activeTerm` / `classes(in:)`.
    @Published var terms: [Term] = []

    /// Syllabus-scan receipts (0046) — what a task's/event's `scanID` resolves to for
    /// the "From <file>" source line. Empty until the user commits a scan.
    @Published var scans: [ScanRecord] = []

    /// A `.ics` file opened from Finder ("Open with Atlas") or dropped on the app icon.
    /// The sidebar watches this and opens the class importer on it. Cleared when the
    /// importer closes — it is a one-time hand-off, not stored state.
    @Published var pendingICSImport: URL?

    /// The term the School section is *looking at* when the user picked one from the
    /// header menu. nil ⇒ follow `activeTerm` (today's term). Session-only: which
    /// semester is current is a date fact, not a stored preference.
    @Published var schoolTermOverride: UUID?

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
            AtlasTips.ConnectSource.hasConnection = hasAnyConnection
        } catch {
            print("[AtlasDB] google_connections read failed — keeping current sync mode. Error: \(error.localizedDescription)")
            AtlasLog.append("google_connections read failed: \(error.localizedDescription)")
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

    /// The user's subscribed calendar feeds (`calendar_feeds`) — Canvas + generic ICS,
    /// managed via `FeedService`. Drives Settings' Calendars feed list. Loaded at launch
    /// and refreshed after every feed connect / space-change / disconnect.
    @Published var calendarFeeds: [CalendarFeedRow] = []

    /// True when at least one external source is connected (any Google account, a legacy
    /// Canvas connection, or a subscribed calendar feed). Gates the "connect a source" tip.
    var hasAnyConnection: Bool {
        !googleConnections.isEmpty
            || canvasConnection != nil
            || calendarFeeds.contains { $0.isServerOwned }
    }

    /// The signed-in user's public identity (collab). Nil until loaded.
    @Published var profile: ProfileRow? = nil

    /// The user's chosen first name / nickname for greetings, stored in the
    /// profile's `display_name` (empty ⇒ never set). Set by the post-signup name
    /// prompt and Settings → Account; read by the dashboard greeting.
    var nickname: String { profile?.displayName ?? "" }

    /// Persists a nickname to the profile's `display_name` (server + local).
    /// Optimistically updates `profile` so the greeting refreshes at once; the
    /// server write is best-effort (a nil db / undeployed table degrades silently).
    func saveNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile?.displayName = trimmed
        guard let db else { return }
        Task { try? await db.updateDisplayName(trimmed) }
    }

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
            AtlasTips.ConnectSource.hasConnection = hasAnyConnection
        } catch {
            print("[AtlasDB] canvas_connections read failed — keeping current state. Error: \(error.localizedDescription)")
            AtlasLog.append("canvas_connections read failed: \(error.localizedDescription)")
        }
    }

    /// Re-reads the subscribed calendar feeds (`calendar_feeds`) for Settings. Never throws
    /// to the caller; on a read failure the current snapshot is left untouched. Mirrors
    /// `refreshCanvasConnection()`.
    func refreshCalendarFeeds() async {
        guard let db else { return }
        do {
            self.calendarFeeds = try await db.loadCalendarFeeds()
            AtlasTips.ConnectSource.hasConnection = hasAnyConnection
        } catch {
            print("[AtlasDB] calendar_feeds read failed — keeping current state. Error: \(error.localizedDescription)")
            AtlasLog.append("calendar_feeds read failed: \(error.localizedDescription)")
        }
    }

    /// Guards against double-bootstrap if `bootstrap(db:)` is called more than once.
    private var bootstrappedUser: String?

    /// The user id whose real snapshot is currently loaded into the published model
    /// arrays. `nil` until the first load lands (or after a sign-out). `AppGate` gates
    /// the signed-in UI on this matching the authenticated user, so the seed `MockData`
    /// — or a previous account's rows — can never render for even one frame before the
    /// correct data arrives. Set only after `applySnapshot` (or on an error, to the
    /// blanked-but-correct user); reset to `nil` by `clearUserData`/sign-out.
    @Published private(set) var loadedUserID: String?

    /// Quick-capture pill presentation (toggled by the ⌘ hotkey / Tasks card).
    @Published var presentCapture: Bool = false

    /// When set (by a project page's "Add Task"), the next Quick-Capture entry is
    /// force-tagged to this project/space instead of AI-routed — so a task added
    /// from a project always lands in that project. Cleared when capture dismisses.
    @Published var captureContext: CaptureContext? = nil

    /// ⌘K command palette / search presentation.
    @Published var presentSearch: Bool = false

    /// "Report a bug" sheet presentation (command palette, sidebar, error surfaces).
    /// `bugReportPrefillTitle` seeds the sheet's Title field — set it before flipping
    /// the flag so an error's "Report this" affordance can pre-fill the report.
    @Published var presentBugReport: Bool = false
    var bugReportPrefillTitle: String? = nil

    /// Opens the bug-report sheet, optionally pre-filling its Title from an error
    /// message (truncated to the column's 200-char bound).
    func reportBug(prefillTitle: String? = nil) {
        bugReportPrefillTitle = prefillTitle.map { String($0.prefix(200)) }
        presentBugReport = true
    }

    /// Which section the full-page Settings route shows (General / Connections / History / Metrics).
    @Published var settingsSection: SettingsSection = .account

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

    /// Periodic timer that re-pulls the full snapshot every 5 min so the running app
    /// surfaces what the server crons wrote (Google every 5 min, feeds every 15) instead
    /// of staying stale until relaunch. Invalidated in `deinit` alongside `clockTimer`.
    private var backgroundRefreshTimer: Timer?

    /// Serializes background re-pulls so an overlapping tick (e.g. a foreground trigger
    /// firing while the timer's pull is still in flight) can't race a second `loadAll`.
    private var isRefreshingFromServer = false

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
        backgroundRefreshTimer?.invalidate()
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

    /// Starts (or restarts) the 5-min timer that re-pulls the server snapshot so
    /// cron-written changes (Google sync every 5 min, feeds every 15) surface in the
    /// running app instead of waiting for a relaunch. Idempotent; mirrors
    /// `startAvailabilityPublishTimer`. Each tick no-ops when signed out / mid-bootstrap
    /// or when an editor is open (see `refreshFromServer`).
    func startBackgroundRefreshTimer() {
        backgroundRefreshTimer?.invalidate()
        backgroundRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshFromServer() }
        }
    }

    /// True while the user has an editor / edit-bearing sheet open, so a background
    /// re-pull would swap the model arrays out from under in-flight work. Uses the
    /// existing presentation flags (least invasive check — no new tracking). The note
    /// editor is intentionally excluded: it edits a `@State` draft and self-reconciles
    /// against newer synced versions (`isDirty` / newer-version banner), so a snapshot
    /// swap never clobbers it.
    private var isEditInFlight: Bool {
        presentCapture           // typing a quick-capture task
            || presentEventEditor    // editing an event
            || presentBugReport      // typing a bug report
            || presentSearch         // command palette open (avoid list churn under it)
            || calendarDetailItem != nil  // event detail open
    }

    /// Re-pulls the full server snapshot (`loadAll` → `applySnapshot`, the same path
    /// bootstrap uses) plus the connection/feed metadata, surfacing whatever the server
    /// crons wrote to Supabase. Driven by `backgroundRefreshTimer` and by
    /// `didBecomeActive`. Quiet by design: no UI, logs only on failure.
    ///
    /// SAFETY: `applySnapshot` replaces the model arrays wholesale, so this DEFERS while
    /// an editor is open (`isEditInFlight`) rather than merging — a skipped tick simply
    /// runs at the next interval. It also:
    ///   • no-ops unless a user's snapshot is loaded (`loadedUserID != nil`), which is
    ///     false while signed out AND during the initial bootstrap `loadAll`, covering
    ///     the mid-bootstrap case; and
    ///   • serializes on `isRefreshingFromServer` so overlapping pulls can't race.
    /// Local edits already push up optimistically, so the re-pull returns what the client
    /// has plus any cron-written changes.
    func refreshFromServer() async {
        guard let db, loadedUserID != nil else { return }  // signed in and past bootstrap
        guard !isRefreshingFromServer else { return }      // one pull at a time
        guard !isEditInFlight else { return }              // don't stomp open editors
        isRefreshingFromServer = true
        defer { isRefreshingFromServer = false }
        do {
            let snapshot = try await db.loadAll()
            applySnapshot(snapshot)
        } catch {
            AtlasLog.append("background refresh loadAll failed: \(error.localizedDescription)")
        }
        // Keep Settings' connection/feed metadata fresh too (both degrade silently).
        await refreshCalendarFeeds()
        await refreshCanvasConnection()
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
            // Class meetings are real occupancy — you can't take a study slot during Bio 201.
            relevant += classMeetingEvents(on: day)
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

            // Open the render gate: the model now holds THIS user's real data.
            loadedUserID = userID

        } catch {
            // A load failure must not leave another dataset (the seed MockData or a
            // previous account's rows) on screen. Blank to the correct-but-empty user
            // and open the gate anyway so the UI isn't stuck on the loading spinner.
            // `bootstrappedUser` stays nil so the next foreground/appearance retries.
            print("[AtlasDB] bootstrap failed — showing empty state for this user. Error: \(error.localizedDescription)")
            AtlasLog.append("bootstrap loadAll failed: \(error.localizedDescription)")
            clearUserData()
            loadedUserID = userID
            bootstrappedUser = nil
        }

        // Load this user's client-side quick-capture history (Application Support).
        loadCaptureHistory(userID: userID)

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
        async let feedsDone: Void = self.refreshCalendarFeeds()       // subscribed calendar feeds (Canvas + ICS)

        self.profile = try? await profileRow
        await collabDone
        await startRealtimeSync(supabaseURL: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
        await googleDone
        await canvasDone
        await feedsDone

        // Pull cross-device preferences (server wins). Best-effort: no-ops until the
        // user_settings table is deployed.
        await settingsSync.pullAndApply(db: db)

        // Collab phase 3: publish this device's derived availability, then keep it
        // fresh on an hourly timer (local edits also trigger a debounced publish).
        await publishAvailability()
        startAvailabilityPublishTimer()

        // Keep the running app fresh: re-pull the server snapshot every 5 min so cron
        // writes (Google/feeds) surface without a relaunch. Defers while an editor is open.
        startBackgroundRefreshTimer()

        // Fire-and-forget launch ping so the owner dashboard can count Mac
        // actives. Best-effort: silent on any failure (offline / pre-migration).
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Task { [db] in try? await db.recordAppPing(platform: "macos", appVersion: appVersion) }
    }

    /// Blanks every user-scoped model array so a signed-out / just-switched account
    /// leaves nothing of the previous user's data on screen. Called on account switch
    /// from `bootstrap`; the fresh `loadAll()` (or a re-sign-in) repopulates.
    private func clearUserData() {
        spaces = []
        terms = []
        scans = []
        schoolTermOverride = nil
        tasks = []
        events = []
        notes = []
        goals = []
        captureHistory = []
        references = []
        referenceAttachments = []
        externalEvents = []
        googleConnections = []
        canvasConnection = nil
        calendarFeeds = []
        profile = nil
        pendingInvites = []
        projectMembers = [:]
        sharedWithMeProjects = []
        spaceMembers = [:]
        teammateAvailability = [:]
        expandedSpaces = []
        calendarDetailItem = nil
        // Close the render gate — nothing is loaded for any user until the next
        // `loadAll()` lands (or the error path re-opens it for the same user).
        loadedUserID = nil
    }

    /// Wipes every per-user in-memory model AND the bootstrap/gate bookkeeping on
    /// sign-out, so the next account starts from a clean slate with nothing of the
    /// previous user retained. `AuthService` already dropped the persisted session;
    /// this drops the only in-memory cross-account cache. Called by `AppGate` when
    /// auth transitions to signed-out.
    func resetForSignOut() {
        clearUserData()          // blanks the arrays and nils `loadedUserID`
        bootstrappedUser = nil
        db = nil
        route = .dashboard
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
        self.terms  = snapshot.terms
        self.scans  = snapshot.scans
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
        // A task's project link persists as `projectID`; `projectName` is the display
        // copy, so re-derive it from the id here. Without this pass a snapshot re-pull
        // (bootstrap, the 5-min background refresh, a realtime tick) blanks the name and
        // every class chip silently degrades to the space tag.
        let projectsByID = Dictionary(spaces.flatMap(\.projects).map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        for i in tasks.indices {
            tasks[i].spaceColor = calendarSpaceColor(named: tasks[i].spaceName)
            if let pid = tasks[i].projectID, let project = projectsByID[pid] {
                tasks[i].projectName = project.name
            }
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
            AtlasLog.append("project invite failed: \(error.localizedDescription)")
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
            AtlasLog.append("space invite failed: \(error.localizedDescription)")
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
            AtlasLog.append("respond to invite failed: \(error.localizedDescription)")
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

    // MARK: - School framework (terms + classes, 0042)

    /// Every project across every space, flattened. Classes are `projects` rows, so
    /// the School queries below read through this.
    var allProjects: [Project] { spaces.flatMap(\.projects) }

    /// The term the app should be showing — today's term, else the most recent
    /// (see `TermSelection`). Nil when the user has no terms yet.
    var activeTerm: Term? { TermSelection.active(in: terms) }

    /// The live classes of `term`: `is_class`, in that term, not archived. Ending a
    /// term archives its classes, so they drop out here while staying queryable.
    func classes(in term: Term) -> [Project] {
        allProjects.filter { $0.isClass && $0.termID == term.id && $0.archivedAt == nil }
    }

    /// True when the user has classes that predate the term model (`term_id` nil) —
    /// the UI stage uses this to prompt "date your term once". Nothing is guessed
    /// here: no term is auto-created with invented dates.
    var unassignedClassesNeedTerm: Bool {
        allProjects.contains { $0.isClass && $0.termID == nil && $0.archivedAt == nil }
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
        // A checked task's FUTURE work sessions clear from the grid (`scheduledWorkBlocks`),
        // so the reserved time is freed — its Apple mirror has to go with them, or the block
        // lingers on a calendar Atlas no longer shows. Past sessions stay: they're history.
        // Unchecking re-pushes (the id was cleared, so a fresh mirror is created).
        var clearedMirror = false
        if let at = tasks[i].scheduledAt, at > now {
            if tasks[i].done {
                removeWorkSessionFromApple(tasks[i])
                tasks[i].appleEventId = nil
                clearedMirror = true
            } else {
                pushWorkSessionToApple(tasks[i])
            }
        }
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
            // Clearing the Apple handle needs the whole row, so that case skips the scoped
            // PATCH and falls through to the full upsert below.
            let matched = clearedMirror ? false
                : ((try? await db.setTaskDone(id: id, done: updated.done,
                                              completedAt: updated.completedAt)) ?? false)
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
    ///
    /// Buckets by `bucketDate(in:)`, never by `start`: an all-day event is a floating date
    /// anchored at UTC midnight (`AllDayDate`), so reading its raw instant in the local
    /// calendar lands it on the previous day everywhere west of Greenwich.
    func events(on day: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.bucketDate(in: cal), inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// External (read-only) events occurring on the given day, sorted by start time.
    /// Mirrors `events(on:)` but draws from the non-persisted `externalEvents` pool.
    func externalEvents(on day: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return externalEvents
            .filter { cal.isDate($0.bucketDate(in: cal), inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Today's calendar entries for the dashboard schedule, in time order — the shared
    /// `displayEvents(on:)` pool, so the dashboard shows exactly what the Calendar tab
    /// does for today (class meetings and Apple events included, duplicates collapsed).
    var todaysEvents: [CalendarEvent] {
        displayEvents(on: Date()).sorted { $0.start < $1.start }
    }

    /// Scheduled tasks rendered as work-block events for `date` — the calendar's
    /// drag-to-schedule tiles. Excludes completed tasks; a scheduled block whose slot has
    /// elapsed but isn't yet overdue STAYS on the grid (rendered dimmed/"passed"). Once it is
    /// overdue AND its slot has elapsed (`needsReplan`) it leaves the grid and returns to the
    /// tray to be re-planned. Shared by the calendar grid and the dashboard.
    ///
    /// A CHECKED-OFF task keeps its session on the grid only when the session is already in
    /// the past: that block becomes faded *history* (`isHistory`) — proof you worked. Its
    /// FUTURE sessions clear the instant the task is checked, per the completion mechanics
    /// (the task checkbox is the only checkbox; a session completes nothing).
    func scheduledWorkBlocks(on date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return tasks.compactMap { task in
            guard let at = task.scheduledAt, cal.isDate(at, inSameDayAs: date) else { return nil }
            let end = cal.date(byAdding: .minute, value: task.durationMin ?? 60, to: at) ?? at
            if task.done {
                guard end < now else { return nil }   // future sessions of a done task clear
            } else {
                guard !task.needsReplan(now: now) else { return nil }
            }
            return CalendarEvent(
                id: task.id,
                title: task.title,
                subtitle: task.done ? "Worked" : "Planned",
                start: at,
                end: end,
                color: task.spaceColor,
                spaceName: task.spaceName,
                notes: task.notes,
                noteID: task.noteID,
                isWorkBlock: true,
                isHistory: task.done
            )
        }
    }

    // MARK: - Phase 2 time model (estimates · late triage · more time)

    /// Set (or clear, with `nil`) a task's optional total time estimate — the number the
    /// due marker's "2.5 of 4h planned" fill is measured against.
    func setEstimate(taskId: UUID, minutes: Int?) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].estimateMin = minutes
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
    }

    /// Dismiss the "Due date moved" chip (migration 0047) — a client-only clear, since
    /// the server only ever sets `dueMovedFrom`, never resets it.
    func dismissDueMoved(taskId: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].dueMovedFrom = nil
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
    }

    /// A past session's "+ more time": plan the next session at the SAME clock time
    /// tomorrow. Deliberately predictable — Atlas never auto-picks a "free gap" (auto-slot
    /// scheduling is cut), and the new session drags like any other block.
    func addMoreTime(taskId: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }),
              let previous = tasks[i].scheduledAt else { return }
        tasks[i].scheduledAt = TimeModel.nextSessionSlot(after: previous, now: now)
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
        schedulePublish()
    }

    /// Late-bar triage: move every overdue open task's due date to `date`, stamping
    /// `originalDueDate` once so the ORIGINAL date survives as a faded marker in the past.
    /// Never automatic — this only ever runs from an explicit "Reschedule N late items" click.
    func rescheduleLateItems(to date: Date) {
        for updated in TimeModel.rescheduleLate(tasks: tasks, to: date, now: now) {
            guard let i = tasks.firstIndex(where: { $0.id == updated.id }) else { continue }
            tasks[i] = updated
            Task { try? await self.db?.upsertTask(updated) }
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
    /// - Parameter scanID: the syllabus-scan receipt this task was imported by, or nil
    ///   (the default) for every hand-made task — provenance is stamped at creation,
    ///   never inferred afterwards.
    /// - Parameter allDay: true when `dueDate` names a calendar DATE rather than an
    ///   instant — it must then be the canonical UTC-midnight anchor (`AllDayDate`),
    ///   which is what `effectiveDueDate` unpacks.
    func addTask(title: String,
                 dueDate: Date? = nil,
                 allDay: Bool = false,
                 durationMin: Int? = nil,
                 spaceName: String = "",
                 projectName: String = "",
                 scanID: UUID? = nil) -> TaskItem {
        let resolvedSpace = resolvedTaskSpaceName(hint: spaceName, text: title)
        var task = TaskItem(title: title,
                            dueLabel: TaskItem.dueLabel(for: dueDate, allDay: allDay),
                            dueDate: dueDate,
                            durationMin: durationMin)
        task.allDay = allDay
        task.scanID = scanID
        task.spaceName = resolvedSpace
        task.spaceID = spaceID(named: resolvedSpace)
        task.spaceColor = calendarSpaceColor(named: resolvedSpace)
        task.projectName = projectName
        task.projectID = project(spaceName: resolvedSpace, projectName: projectName)?.id
        tasks.append(task)
        Task { try? await self.db?.upsertTask(task) }
        return task
    }

    /// Reassign a task to a different project (or clear it with "").
    ///
    /// Stamps the project's `id` alongside the name: the id is what persists
    /// (`tasks.project_id`), the name is the display copy. Setting only the name is
    /// what used to lose a class on the next snapshot load.
    func setTaskProject(taskId: UUID, projectName: String) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i].projectName = projectName
            tasks[i].projectID = project(spaceName: tasks[i].spaceName, projectName: projectName)?.id
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
        if let kept = projects.first(where: { $0.name == tasks[i].projectName }) {
            tasks[i].projectID = kept.id
        } else {
            tasks[i].projectName = ""
            tasks[i].projectID = nil
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
            pushWorkSessionToApple(updated)
            schedulePublish()
            AtlasChecklist.mark(AtlasChecklist.scheduled)   // Get-started card
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
        pushWorkSessionToApple(updated)
        schedulePublish()
    }

    /// Removes a task's calendar work-block (returns it to the tray) and deletes its mirrored
    /// Google event. The task itself is kept.
    func unscheduleTask(id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let gid = tasks[i].workBlockGoogleEventId
        removeWorkSessionFromApple(tasks[i])
        tasks[i].scheduledAt = nil
        tasks[i].workBlockGoogleEventId = nil
        tasks[i].appleEventId = nil
        let updated = tasks[i]
        Task { try? await self.db?.upsertTask(updated) }
        if let gid, !gid.isEmpty { deleteGoogleEvent(googleEventID: gid) }
        schedulePublish()
    }

    /// Remove a task's calendar slot, returning it to the unscheduled tray.
    func unschedule(taskId: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            removeWorkSessionFromApple(tasks[i])
            tasks[i].scheduledAt = nil
            tasks[i].appleEventId = nil
            let updated = tasks[i]
            Task { try? await self.db?.upsertTask(updated) }
            schedulePublish()
        }
    }

    /// Permanently delete a task (used after completion grace period).
    func deleteTask(id: UUID) {
        if let task = tasks.first(where: { $0.id == id }) { removeWorkSessionFromApple(task) }
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
        AtlasChecklist.mark(AtlasChecklist.scheduled)   // Get-started card
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
        AtlasLog.append("Apple Calendar write failed: \(lastCalendarSyncError ?? "unknown")")
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

    // MARK: - Work-session mirror (Atlas → Apple)
    //
    // Outbound push rules per object type: events ON (above), work sessions ON by default
    // with a toggle, deadlines OFF, tasks NEVER. A work session is a scheduled task, not an
    // `events` row, so its mirror handle is `tasks.apple_event_id` (migration 0026) — the
    // same shape as the event mirror, persisted so a relaunch patches instead of duplicating
    // and the EventKit read-back de-dupes it (CalendarSync.excludingOwnMirrors).

    /// Default ON — a reserved slot is real busy time. `object(forKey:)` rather than `bool`
    /// so an untouched install gets the ON default instead of UserDefaults' implicit false.
    private var workSessionPushEnabled: Bool {
        UserDefaults.standard.object(forKey: "calendar.workSessions.push") as? Bool ?? true
    }

    /// User-adjustable mirror label; empty falls back to the shared default. Also read by
    /// `displayEvents(on:)` so dedup can strip the prefix off an inbound "Work: X" copy and
    /// recognise it as the native session it mirrors.
    var workSessionTitlePrefix: String {
        let stored = UserDefaults.standard.string(forKey: "calendar.workSessions.titlePrefix") ?? ""
        return stored.isEmpty ? CalendarSync.defaultWorkSessionPrefix : stored
    }

    private var mirrorsWorkSessionsToApple: Bool {
        workSessionPushEnabled
            && UserDefaults.standard.bool(forKey: "calendar.apple.writeback")
            && eventKit.authorizationStatus() == .fullAccess
    }

    /// The session as an external calendar sees it: prefixed title over the task's slot.
    private func appleMirror(for task: TaskItem) -> CalendarEvent? {
        guard let at = task.scheduledAt else { return nil }
        let end = Calendar.current.date(byAdding: .minute, value: task.durationMin ?? 60, to: at) ?? at
        return CalendarEvent(
            title: CalendarSync.mirroredWorkSessionTitle(task.title, prefix: workSessionTitlePrefix),
            subtitle: "",
            start: at,
            end: end,
            color: task.spaceColor,
            spaceName: task.spaceName,
            notes: task.notes,
            isWorkBlock: true)
    }

    /// Creates or patches the Apple mirror of a scheduled task. Failures are swallowed —
    /// the local schedule already succeeded.
    private func pushWorkSessionToApple(_ task: TaskItem) {
        guard mirrorsWorkSessionsToApple, let mirror = appleMirror(for: task) else { return }
        Task { @MainActor in
            if let aid = task.appleEventId, !aid.isEmpty {
                try? await self.eventKit.updateEvent(appleEventID: aid, with: mirror)
            } else {
                guard let aid = try? await self.eventKit.createEvent(mirror, calendarId: self.appleWritebackCalendarId),
                      !aid.isEmpty else { return }
                self.stampTaskAppleEventId(aid, on: task.id)
            }
        }
    }

    /// Removes a session's Apple mirror when the slot goes away (unschedule / task delete).
    /// Runs regardless of the push toggle — a mirror we created must still be cleaned up
    /// after the toggle is switched off.
    private func removeWorkSessionFromApple(_ task: TaskItem) {
        guard let aid = task.appleEventId, !aid.isEmpty,
              eventKit.authorizationStatus() == .fullAccess else { return }
        Task { try? await eventKit.deleteEvent(appleEventID: aid) }
    }

    /// Mirrors already-scheduled sessions that were never pushed — fired when the toggle
    /// flips on. Safe to repeat: sessions that already gained an id are patched, not doubled.
    func backfillWorkSessionsToApple() {
        for task in tasks where !task.done && task.scheduledAt != nil {
            pushWorkSessionToApple(task)
        }
    }

    private func stampTaskAppleEventId(_ aid: String, on taskID: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[i].appleEventId = aid
        let persisted = tasks[i]
        Task { try? await self.db?.upsertTask(persisted) }
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
