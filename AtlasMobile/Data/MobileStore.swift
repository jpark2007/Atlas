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

    /// Load every table into `snapshot`. On a 401, try one token refresh + retry;
    /// if that fails, sign out.
    func refresh() async {
        guard session != nil else { return }
        loading = true
        defer { loading = false }
        do {
            snapshot = try await db.loadAll()
        } catch AtlasDBError.requestFailed(401, _), AtlasDBError.notAuthenticated {
            if let fresh = await sessionStore.forceRefresh() {
                session = fresh
                snapshot = (try? await db.loadAll()) ?? snapshot
            } else {
                signOut()
            }
        } catch {
            // Keep the existing snapshot; a later refresh retries.
        }
    }

    // MARK: - Mutations (optimistic local write, then persist)

    func addTask(_ t: TaskItem) async {
        snapshot.tasks.append(t)
        try? await db.upsertTask(t)
    }

    func updateTask(_ t: TaskItem) async {
        if let i = snapshot.tasks.firstIndex(where: { $0.id == t.id }) {
            snapshot.tasks[i] = t
        }
        try? await db.upsertTask(t)
    }

    func deleteTask(id: UUID) async {
        snapshot.tasks.removeAll { $0.id == id }
        try? await db.deleteTask(id: id)
    }

    func addEvent(_ e: CalendarEvent) async {
        snapshot.events.append(e)
        try? await db.upsertEvent(e)
    }

    // MARK: - Deep links

    /// Record a parsed deep link (and apply its space filter). `RootTabView` reacts
    /// to `pendingDeepLink` to switch tabs.
    func handle(_ link: DeepLink) {
        if case .todaySpace(let id) = link { spaceFilter = id }
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
