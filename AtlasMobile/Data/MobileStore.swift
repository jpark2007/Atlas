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
    /// Raised by a long-press on a task row (Tasks or Needs-a-time). `RootTabView`
    /// switches to the Schedule tab; `ScheduleView` consumes it to enter grid mode
    /// with a floating placement chip (the same path as picking in `PlaceTaskSheet`).
    @Published var pendingPlacement: TaskItem?
    /// Last failed-write message (calm copy). Views may surface it; nil = no error.
    @Published var lastError: String?
    /// Apple Calendar events for the visible window (Phase 3, "Apple Calendar from
    /// iPhone"). Read-only, device-local and never persisted — EventKit is per-device, so
    /// no server pass can see these; `MobileStore+Calendar` merges them at display time.
    @Published var appleEvents: [CalendarEvent] = []
    /// Set only when a token refresh fails and we force a sign-out; `SignInView`
    /// surfaces it as a muted line. Cleared on the next successful `signIn`.
    @Published var authNotice: String?

    /// Non-zero while an optimistic mutation is persisting — `refresh()` defers so a
    /// wholesale snapshot replace can't clobber an in-flight local write.
    private var mutationsInFlight = 0

    /// True while a `refresh()` is in flight so overlapping foreground/pull triggers coalesce.
    private var isRefreshing = false

    /// Set when a `refresh()` was turned away (or its result discarded) because a write
    /// was in flight. Drained by `persist` when the last mutation settles — without it a
    /// foreground refresh that collided with a tap was dropped for the whole session, and
    /// the phone kept showing pre-background data with no spinner and no error.
    private var refreshDeferred = false

    /// Consecutive failed `refresh()` attempts, to bound the auto-retry so a long offline
    /// stretch doesn't spin. Reset on any successful load.
    private var refreshFailures = 0

    /// Foreground poll, mirroring the Mac's 5-minute `startBackgroundRefreshTimer`.
    private var pollTask: Task<Void, Never>?

    private let sessionStore = SessionStore()
    private let auth = SupabaseAuth()

    /// Read the live session so a token refresh is picked up on the next request.
    lazy var db  = AtlasDB(session: { @MainActor [weak self] in self?.session })
    lazy var ai  = AtlasAI(session: { [weak self] in self?.session })

    /// Apple Calendar read path (`MobileStore+Calendar` drives it).
    let eventKit = MobileEventKitService()

    /// Cross-device preference sync (user_settings, 0025). Mirrors the Mac: bootstrap
    /// + foreground pull is server-wins; a user-initiated change of a synced setting
    /// pushes (debounced). Owned here so the pull and every push share one
    /// `lastPulledRow` cache — the push overlays local changes onto it.
    let settingsSync = SettingsSyncService()

    /// Pull cross-device preferences (server wins). Best-effort — no-ops until the
    /// `user_settings` table is deployed.
    func pullSyncedSettings() async {
        await settingsSync.pullAndApply(db: db)
    }

    /// Debounced push after a user-initiated change of a synced setting — the one
    /// entry point the Settings/Tasks `.onChange` handlers call.
    func pushSyncedSettings() {
        Task { await settingsSync.push(db: db) }
    }

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
        // Pull cross-device preferences (server wins) once data is loaded.
        await pullSyncedSettings()

        // Fire-and-forget launch ping so the owner dashboard can count iOS
        // actives. Best-effort: silent on any failure (offline / pre-migration).
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Task { [db] in try? await db.recordAppPing(platform: "ios", appVersion: appVersion) }
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let s = try await auth.signIn(email: email, password: password)
        sessionStore.save(s)
        session = s
        authNotice = nil
        await refresh()
        // Fresh sign-in must pull cross-device preferences too (best-effort) — no
        // scene transition fires here, so the foreground pull won't cover it.
        await pullSyncedSettings()
    }

    /// Email/password account creation (GoTrue `signup`). If the project
    /// requires email confirmation, `SupabaseAuth.signUp` returns no session —
    /// surface a notice through the same muted channel `SignInView` already
    /// renders for session-expiry, rather than building new UI for it.
    func signUp(email: String, password: String) async throws {
        if let s = try await auth.signUp(email: email, password: password) {
            sessionStore.save(s)
            session = s
            authNotice = nil
            await refresh()
            await pullSyncedSettings()   // fresh sign-in pulls preferences (best-effort)
        } else {
            authNotice = "Check \(email) to confirm your account, then sign in."
        }
    }

    /// Native Sign in with Apple: run the ASAuthorization flow, then exchange the
    /// id_token (+ raw nonce) for a Supabase session (GoTrue creates first-time
    /// users during the exchange), landing exactly like a password sign-in.
    func signInWithApple() async throws {
        let nonce = AppleNonce.random()
        let credential = try await AppleSignInCoordinator().signIn(hashedNonce: AppleNonce.sha256(nonce))
        let s = try await auth.signInWithIdToken(provider: "apple", idToken: credential.idToken, nonce: nonce)
        sessionStore.save(s)
        session = s
        authNotice = nil
        await refresh()
        await pullSyncedSettings()   // fresh sign-in pulls preferences (best-effort)
    }

    /// A fresh Supabase access token for an authenticated edge-function call
    /// (calendar-feed connect/disconnect/space). Refreshes an expired JWT first — mirrors
    /// the `deleteAccount` path. nil ⇒ no session or the refresh token was rejected.
    func validAccessToken() async -> String? {
        await sessionStore.refreshIfNeeded()?.accessToken
    }

    func signOut() {
        if let token = session?.accessToken {
            Task { await auth.signOut(accessToken: token) }
        }
        sessionStore.clear()
        session = nil
        snapshot = MobileStore.emptySnapshot
        spaceFilter = nil
        // Clear the settings-sync cache + synced keys so a next sign-in on a
        // shared device starts clean (its pull repopulates them).
        settingsSync.reset()
    }

    /// Permanently deletes the signed-in user via the `delete-account` edge function
    /// (service-role `auth.admin.deleteUser`, which cascade-wipes every user-scoped
    /// row). Refreshes an expired JWT first — the function verifies the caller.
    /// On success the local session is cleared so the user lands back at SignInView.
    /// Returns `nil` on success, or a message to show inline.
    func deleteAccount() async -> String? {
        guard let token = (await sessionStore.refreshIfNeeded())?.accessToken else {
            return "Your session expired — sign in again, then delete your account."
        }
        let url = SupabaseConfig.functionsBase.appendingPathComponent("delete-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: await appleRevocationBody())
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "Couldn't delete your account. Please try again in a moment."
            }
        } catch {
            return "Couldn't delete your account. Check your connection and try again."
        }
        // The auth user no longer exists — clear local state (no server logout to call).
        sessionStore.clear()
        session = nil
        snapshot = MobileStore.emptySnapshot
        spaceFilter = nil
        settingsSync.reset()           // same clean-slate as signOut
        PendingCaptureQueue.clearStorage()   // undrained dumps must not outlive the account
        CaptureDraftStore.clear()            // in-progress draft text must not outlive the account
        return nil
    }

    /// The optional Apple-revocation fields of the delete-account request body.
    /// App Store guideline 5.1.1(v) requires revoking the Apple token, and Apple
    /// only accepts a refresh/access token — neither of which Supabase keeps for the
    /// native id_token sign-in. So we re-run the Apple authorization here to get a
    /// fresh one-shot code for the server to exchange and revoke. Best-effort: a
    /// dismissed sheet returns an empty body and the account still deletes.
    private func appleRevocationBody() async -> [String: String] {
        guard session?.user.signedInWithApple == true,
              let clientID = Bundle.main.bundleIdentifier,
              let credential = try? await AppleSignInCoordinator()
                  .signIn(hashedNonce: AppleNonce.sha256(AppleNonce.random())),
              let code = credential.authorizationCode else { return [:] }
        return ["apple_authorization_code": code, "apple_client_id": clientID]
    }

    // MARK: - Data

    /// Load every table into `snapshot`. Two guarantees: overlapping calls coalesce
    /// (`isRefreshing` gate), and a mutation that starts mid-load discards the stale
    /// result instead of clobbering the local write (`mutationsInFlight` re-checked
    /// after every `loadAll()`). On a 401, try one token refresh + retry; else sign out.
    func refresh() async {
        guard session != nil, !isRefreshing else { return }
        // A write is mid-flight — don't clobber it, but remember to come back.
        guard mutationsInFlight == 0 else { refreshDeferred = true; return }
        isRefreshing = true
        loading = true
        defer { isRefreshing = false; loading = false }
        do {
            let loaded = recolored(try await db.loadAll())
            if mutationsInFlight == 0 {
                snapshot = loaded
                refreshFailures = 0
            } else {
                refreshDeferred = true   // a write started mid-load; re-pull once it lands
            }
        } catch AtlasDBError.requestFailed(401, _), AtlasDBError.notAuthenticated {
            if let fresh = await sessionStore.forceRefresh() {
                session = fresh
                if let reloaded = try? await db.loadAll() {
                    if mutationsInFlight == 0 {
                        snapshot = recolored(reloaded)
                        refreshFailures = 0
                    } else {
                        refreshDeferred = true
                    }
                }
            } else {
                signOut()
                authNotice = "Your session expired — please sign in again."
            }
        } catch {
            // Keep the existing snapshot, but RETRY: nothing else re-pulls until the user
            // pulls down or re-foregrounds, so one flaky load would otherwise leave the
            // phone quietly stale — looking fully loaded — for the rest of the session.
            refreshFailures += 1
            if refreshFailures <= 3 {
                let delay = UInt64(refreshFailures) * 5_000_000_000   // 5s, 10s, 15s
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    await self?.refresh()
                }
            }
        }
        // Refresh the connect-source onboarding tip's gate (best-effort, fire-and-forget).
        Task { await refreshConnectionTipState() }
    }

    /// Sets `AtlasTips.ConnectSource.hasConnection` from the live connection rows — any
    /// Google account or a Canvas feed. A failed load coalesces to empty/nil, so on error
    /// `hasConnection` becomes false and the tip's remaining rules still apply. A
    /// successful in-app feed connect also sets it directly (Settings), so this mainly seeds
    /// the "already connected" case at launch — including connections made on another device.
    private func refreshConnectionTipState() async {
        guard session != nil else { return }
        let google = (try? await db.loadGoogleConnections()) ?? []
        let canvas = (try? await db.loadCanvasConnection()) ?? nil
        let hasAny = !google.isEmpty || canvas != nil
        AtlasTips.ConnectSource.hasConnection = hasAny
        // Mirror into the "Get started" checklist so a cross-device (e.g. Mac-made) Google
        // connection ticks the Connect row. Set true only — absence must not untick it.
        if hasAny { UserDefaults.standard.set(true, forKey: "checklist.connected") }
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
        // A task's project link persists as `projectID`; `projectName` is the display
        // copy `TaskRow.toDomain()` leaves empty, so re-derive it here (the Mac does the
        // same in its bootstrap). Without this pass every class-linked task arrives with
        // no project name — it falls out of its class and into a generic space bucket,
        // and the class page's Work section reads empty.
        let projectsByID = Dictionary(s.projects.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        s.tasks = s.tasks.map { task in
            var t = task
            if let space = s.spaces.first(where: {
                $0.name.caseInsensitiveCompare(t.spaceName) == .orderedSame
            }) { t.spaceColor = space.color }
            if let pid = t.projectID, let project = projectsByID[pid] {
                t.projectName = project.name
            }
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

    /// Done-flips persist via the scoped PATCH (done/completed_at only): a full-row
    /// upsert omits a nil completedAt, so an un-check would leave the stale stamp
    /// in the DB — and it could stomp a collaborator's concurrent column edits.
    func setTaskDone(_ t: TaskItem) async {
        let prior = snapshot.tasks.first { $0.id == t.id }
        if let i = snapshot.tasks.firstIndex(where: { $0.id == t.id }) {
            snapshot.tasks[i] = t
        }
        await persist({
            let matched = try await self.db.setTaskDone(id: t.id, done: t.done, completedAt: t.completedAt)
            if !matched { try await self.db.upsertTask(t) }   // row never landed — self-heal
        },
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

    /// Appends many events at once — the expansion of one repeating series. One batched
    /// upsert instead of N, and one rollback that removes them all, so a failed write
    /// can't leave half a series on the calendar.
    func addEvents(_ events: [CalendarEvent]) async {
        guard !events.isEmpty else { return }
        let ids = Set(events.map(\.id))
        snapshot.events.append(contentsOf: events)
        await persist({ try await self.db.upsertEvents(events) },
                      rollback: { self.snapshot.events.removeAll { ids.contains($0.id) } })
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

    func addNote(_ n: Note) async {
        snapshot.notes.append(n)
        await persist({ try await self.db.upsertNote(n) },
                      rollback: { self.snapshot.notes.removeAll { $0.id == n.id } })
    }

    func updateNote(_ n: Note) async {
        let prior = snapshot.notes.first { $0.id == n.id }
        if let i = snapshot.notes.firstIndex(where: { $0.id == n.id }) {
            snapshot.notes[i] = n
        }
        await persist({ try await self.db.upsertNote(n) },
                      rollback: {
                          guard let prior, let i = self.snapshot.notes.firstIndex(where: { $0.id == n.id }) else { return }
                          self.snapshot.notes[i] = prior
                      })
    }

    func deleteNote(id: UUID) async {
        let prior = snapshot.notes.first { $0.id == id }
        snapshot.notes.removeAll { $0.id == id }
        await persist({ try await self.db.deleteNote(id: id) },
                      rollback: { if let prior { self.snapshot.notes.append(prior) } })
    }

    /// Run a persist call for an already-applied optimistic mutation: on a 401 do one
    /// forced token refresh + retry; on final failure roll the local change back and
    /// publish a calm `lastError`. Counted in `mutationsInFlight` so `refresh()` waits.
    private func persist(_ op: @escaping () async throws -> Void, rollback: () -> Void) async {
        mutationsInFlight += 1
        defer {
            mutationsInFlight -= 1
            // Last write settled and a refresh was turned away while it ran — run it now,
            // or the incoming changes it would have brought stay invisible until the next
            // foreground transition.
            if mutationsInFlight == 0 && refreshDeferred {
                refreshDeferred = false
                Task { [weak self] in await self?.refresh() }
            }
        }
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

    // MARK: - Foreground polling

    /// Re-pull every 5 minutes while the app is foregrounded, mirroring the Mac's
    /// `startBackgroundRefreshTimer`. Without this iOS only ever refreshed on a scene
    /// transition or a pull-to-refresh, so a phone left open on the Schedule tab never
    /// saw anything written elsewhere — a Mac edit, a teammate's change, or what the
    /// server's Google (5 min) and feed (15 min) crons wrote.
    func startForegroundPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// Stops the poll when the app leaves the foreground; `scenePhase == .active` already
    /// triggers its own refresh on the way back in.
    func stopForegroundPolling() {
        pollTask?.cancel()
        pollTask = nil
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

    /// The id of the project named `projectName` inside `spaceName`, or nil when the
    /// name is empty or matches nothing. This id — not the name — is what persists
    /// (`tasks.project_id` / `events.project_id`); writing only the name is what used
    /// to lose the class on the next snapshot load. Mirrors the Mac's
    /// `AppState.project(spaceName:projectName:)`.
    func projectID(spaceName: String, projectName: String) -> UUID? {
        guard !projectName.isEmpty else { return nil }
        return snapshot.projects.first {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
                && $0.spaceName.caseInsensitiveCompare(spaceName) == .orderedSame
        }?.id
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

// MARK: - Per-project day-grid colors (mirrors the Mac's AppState+Calendar `gridColored`)

extension MobileStore {

    /// The color a DAY-GRID tile should wear: the tile's project color when that project
    /// set its own `colorToken`, else the space color already on the event. Applied ONLY
    /// to grid tiles — agenda dots, month dots, filters and widgets keep the space color
    /// (Option B). An event with no project link, or whose project inherits the space
    /// color, is returned unchanged.
    func gridColored(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.map { ev in
            guard let token = projectColorToken(for: ev) else { return ev }
            var e = ev
            e.color = ColorToken.color(for: token)
            return e
        }
    }

    /// Work-block tiles (scheduled tasks) wear their project's color on the day grid.
    /// The task's `spaceColor` is swapped so `DayGridView`'s task blocks pick it up; the
    /// agenda's check-circles read the untouched space-colored tasks and stay unchanged.
    func gridColored(tasks: [TaskItem]) -> [TaskItem] {
        tasks.map { t in
            guard let token = projectColorToken(spaceName: t.spaceName, projectName: t.projectName) else { return t }
            var x = t
            x.spaceColor = ColorToken.color(for: token)
            return x
        }
    }

    /// The custom color token of the project a grid tile belongs to, or `nil` when the
    /// tile has no project link / the project inherits the space color. Work-blocks
    /// (id == task.id) resolve through the backing task's project; other events resolve
    /// through `projectID`.
    private func projectColorToken(for event: CalendarEvent) -> String? {
        if event.isWorkBlock, let task = snapshot.tasks.first(where: { $0.id == event.id }) {
            return projectColorToken(spaceName: task.spaceName, projectName: task.projectName)
        }
        if let pid = event.projectID,
           let project = snapshot.projects.first(where: { $0.id == pid }) {
            return project.colorToken
        }
        return nil
    }

    /// The custom color token of the project matching `projectName` inside `spaceName`
    /// (empty name ⇒ no project). `nil` when nothing matches or the project inherits.
    private func projectColorToken(spaceName: String, projectName: String) -> String? {
        guard !projectName.isEmpty else { return nil }
        return snapshot.projects
            .first { $0.name == projectName && $0.spaceName == spaceName }?
            .colorToken
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
