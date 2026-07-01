import Foundation
import AtlasCore

/// Persists the Supabase session across launches. Mirrors the Mac `AuthService`
/// storage approach: a JSON-encoded `SupabaseSession` in `UserDefaults`. On launch
/// an expired access token is swapped for a fresh one via `SupabaseAuth.refresh`.
///
/// A plain helper (not `ObservableObject`) — `MobileStore` composes it and owns the
/// published `session`.
@MainActor
final class SessionStore {

    private let key = "atlas.supabase.session"
    private let api = SupabaseAuth()

    /// The last-known session (restored at init, updated on save/clear).
    private(set) var session: SupabaseSession?

    init() {
        session = load()
    }

    // MARK: - Persistence

    private func load() -> SupabaseSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        session = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Refresh

    /// Refresh only when the token is expired (or within a minute of it). Used at
    /// launch. Returns the current valid session, or the stale one if refresh fails.
    func refreshIfNeeded() async -> SupabaseSession? {
        guard let current = session else { return nil }
        guard isExpired(current) else { return current }
        return await forceRefresh() ?? current
    }

    /// Unconditionally exchange the refresh token for a new session. Used to recover
    /// from a 401. Returns nil when the refresh token itself is rejected.
    func forceRefresh() async -> SupabaseSession? {
        guard let current = session else { return nil }
        guard let fresh = try? await api.refresh(refreshToken: current.refreshToken) else { return nil }
        save(fresh)
        return fresh
    }

    private func isExpired(_ session: SupabaseSession) -> Bool {
        guard let expiresAt = session.expiresAt else { return false }
        return Date().timeIntervalSince1970 >= expiresAt - 60   // 60 s skew
    }
}
