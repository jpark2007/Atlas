import SwiftUI
import AtlasCore

/// The single app-wide store for the iOS companion. Owns the session, the loaded
/// data snapshot, and the shared space filter; wraps `AtlasDB` / `AtlasAI` (both
/// built from the live session). Injected via `.environmentObject`.
@MainActor
final class MobileStore: ObservableObject {

    @Published var session: SupabaseSession?          // nil = show SignInView
    @Published var snapshot: AtlasSnapshot = MobileStore.emptySnapshot
    @Published var spaceFilter: UUID?                 // nil = All; shared by Schedule + Tasks
    @Published var loading = false
    /// Set by `onOpenURL`; consumed by `RootTabView` to switch tabs.
    @Published var pendingDeepLink: DeepLink?
    /// Raised by `atlas://capture?mic=1`; `CaptureView` consumes it to begin
    /// listening as soon as the Capture screen appears, then resets it.
    @Published var autoStartMic = false
    /// Raised by the Schedule-family deep links (`today`/`unscheduled`/`today?space`);
    /// `ScheduleView` consumes it to snap back to today, then resets it.
    @Published var scheduleFocusToday = false
    /// Last failed-write message (calm copy). Views may surface it; nil = no error.
    @Published var lastError: String?
    /// Set only when a token refresh fails and we force a sign-out; `SignInView`
    /// surfaces it as a muted line. Cleared on the next successful `signIn`.
    @Published var authNotice: String?

    /// Non-zero while an optimistic mutation is persisting — `refresh()` defers so a
    /// wholesale snapshot replace can't clobber an in-flight local write.
    private var mutationsInFlight = 0

    /// True while a `refresh()` is in flight so overlapping foreground/pull triggers coalesce.
    private var isRefreshing = false

    private let sessionStore = SessionStore()
    private let auth = SupabaseAuth()

    /// Read the live session so a token refresh is picked up on the next request.
    lazy var db  = AtlasDB(session: { [weak self] in self?.session })
    lazy var ai  = AtlasAI(session: { [weak self] in self?.session })

    private static let emptySnapshot = AtlasSnapshot(
        spaces: [], projects: [], tasks: [], events: [], notes: [], goals: [])

    init() {
        session = sessionStore.session
        if session != nil {
            if let cached = WidgetSnapshotWriter.loadCache() { snapshot = recolored(cached) }
            Task { await bootstrap() }
        }
    }

    /// Launch path for an already-signed-in user: refresh an expired token, then load.
    private func bootstrap() async {
        session = await sessionStore.refreshIfNeeded()
        await refresh()
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let s = try await auth.signIn(email: email, password: password)
        sessionStore.save(s)
        session = s
        authNotice = nil
        await refresh()
    }

    func signOut() {
        if let token = session?.accessToken {
            Task { await auth.signOut(accessToken: token) }
        }
        sessionStore.clear()
        session = nil
        snapshot = MobileStore.emptySnapshot
        spaceFilter = nil
    }

    // MARK: - Data

    /// Load every table into `snapshot`. Two guarantees: overlapping calls coalesce
    /// (`isRefreshing` gate), and a mutation that starts mid-load discards the stale
    /// result instead of clobbering the local write (`mutationsInFlight` re-checked
    /// after every `loadAll()`). On a 401, try one token refresh + retry; else sign out.
    func refresh() async {
        guard session != nil, mutationsInFlight == 0, !isRefreshing else { return }
        isRefreshing = true
        loading = true
        defer { isRefreshing = false; loading = false }
        do {
            let loaded = recolored(try await db.loadAll())
            if mutationsInFlight == 0 { snapshot = loaded }
        } catch AtlasDBError.requestFailed(401, _), AtlasDBError.notAuthenticated {
            if let fresh = await sessionStore.forceRefresh() {
                session = fresh
                if let reloaded = try? await db.loadAll(), mutationsInFlight == 0 {
                    snapshot = recolored(reloaded)
                }
            } else {
                signOut()
                authNotice = "Your session expired — please sign in again."
            }
        } catch {
            // Keep the existing snapshot; a later refresh retries.
        }
    }

    /// `EventRow.toDomain()`/`TaskRow.toDomain()` stamp every event/task
    /// `AtlasTheme.Colors.accent` and leave re-deriving the real color to the client
    /// (the Mac does it in AppState bootstrap). Without this, every event dot AND
    /// task check-circle renders accent (the "orange circles" bug) instead of its
    /// space color.
    private func recolored(_ snap: AtlasSnapshot) -> AtlasSnapshot {
        var s = snap
        s.events = s.events.map { event in
            var e = event
            if let space = s.spaces.first(where: {
                $0.name.caseInsensitiveCompare(e.spaceName) == .orderedSame
            }) { e.color = space.color }
            return e
        }
        s.tasks = s.tasks.map { task in
            var t = task
            if let space = s.spaces.first(where: {
                $0.name.caseInsensitiveCompare(t.spaceName) == .orderedSame
            }) { t.spaceColor = space.color }
            return t
        }
        return s
    }

    // MARK: - Mutations (optimistic local write, then persist)

    func addTask(_ t: TaskItem) async {
        snapshot.tasks.append(t)
        await persist({ try await self.db.upsertTask(t) },
                      rollback: { self.snapshot.tasks.removeAll { $0.id == t.id } })
    }

    func updateTask(_ t: TaskItem) async {
        let prior = snapshot.tasks.first { $0.id == t.id }
        if let i = snapshot.tasks.firstIndex(where: { $0.id == t.id }) {
            snapshot.tasks[i] = t
        }
        await persist({ try await self.db.upsertTask(t) },
                      rollback: {
                          guard let prior, let i = self.snapshot.tasks.firstIndex(where: { $0.id == t.id }) else { return }
                          self.snapshot.tasks[i] = prior
                      })
    }

    func deleteTask(id: UUID) async {
        let prior = snapshot.tasks.first { $0.id == id }
        snapshot.tasks.removeAll { $0.id == id }
        await persist({ try await self.db.deleteTask(id: id) },
                      rollback: { if let prior { self.snapshot.tasks.append(prior) } })
    }

    func addEvent(_ e: CalendarEvent) async {
        snapshot.events.append(e)
        await persist({ try await self.db.upsertEvent(e) },
                      rollback: { self.snapshot.events.removeAll { $0.id == e.id } })
    }

    func updateEvent(_ e: CalendarEvent) async {
        let prior = snapshot.events.first { $0.id == e.id }
        if let i = snapshot.events.firstIndex(where: { $0.id == e.id }) {
            snapshot.events[i] = e
        }
        await persist({ try await self.db.upsertEvent(e) },
                      rollback: {
                          guard let prior, let i = self.snapshot.events.firstIndex(where: { $0.id == e.id }) else { return }
                          self.snapshot.events[i] = prior
                      })
    }

    func deleteEvent(id: UUID) async {
        let prior = snapshot.events.first { $0.id == id }
        snapshot.events.removeAll { $0.id == id }
        await persist({ try await self.db.deleteEvent(id: id) },
                      rollback: { if let prior { self.snapshot.events.append(prior) } })
    }

    /// Run a persist call for an already-applied optimistic mutation: on a 401 do one
    /// forced token refresh + retry; on final failure roll the local change back and
    /// publish a calm `lastError`. Counted in `mutationsInFlight` so `refresh()` waits.
    private func persist(_ op: @escaping () async throws -> Void, rollback: () -> Void) async {
        mutationsInFlight += 1
        defer { mutationsInFlight -= 1 }
        do {
            try await op()
        } catch AtlasDBError.requestFailed(401, _), AtlasDBError.notAuthenticated {
            if let fresh = await sessionStore.forceRefresh() {
                session = fresh
                do { try await op(); return } catch { /* fall through to rollback */ }
            }
            rollback()
            lastError = "Couldn’t save that change — we’ll try again later."
        } catch {
            rollback()
            lastError = "Couldn’t save that change — we’ll try again later."
        }
    }

    // MARK: - AI context

    /// Spaces with their projects re-nested from the flat `snapshot.projects`
    /// (`loadAll()` returns spaces with `projects: []`). Feeds `AtlasAI.context` so
    /// capture routing sees real project names/codes/overviews.
    var contextSpaces: [Space] {
        snapshot.spaces.map { space in
            var s = space
            s.projects = snapshot.projects.filter {
                $0.spaceName.caseInsensitiveCompare(space.name) == .orderedSame
            }
            return s
        }
    }

    // MARK: - Deep links

    /// Record a parsed deep link (and apply its space filter). `RootTabView` reacts
    /// to `pendingDeepLink` to switch tabs.
    func handle(_ link: DeepLink) {
        switch link {
        case .today, .unscheduled:
            scheduleFocusToday = true
        case .todaySpace(let id):
            spaceFilter = id
            scheduleFocusToday = true
        case .capture(let mic):
            if mic { autoStartMic = true }
        }
        pendingDeepLink = link
    }
}

/// A parsed `atlas://` deep link. Tasks 5/9 flesh out the per-link behavior; Task 1
/// parses the URL and switches the tab.
enum DeepLink: Equatable {
    case today
    case capture(mic: Bool)
    case unscheduled
    case todaySpace(UUID)

    init?(url: URL) {
        guard url.scheme == "atlas",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch comps.host {
        case "today":
            if let value = comps.queryItems?.first(where: { $0.name == "space" })?.value,
               let id = UUID(uuidString: value) {
                self = .todaySpace(id)
            } else {
                self = .today
            }
        case "capture":
            let mic = comps.queryItems?.first(where: { $0.name == "mic" })?.value == "1"
            self = .capture(mic: mic)
        case "unscheduled":
            self = .unscheduled
        default:
            return nil
        }
    }
}
