import Foundation

/// Canvas server-sync connect client. Hands the user's Canvas Calendar Feed URL to
/// the `canvas-connect` edge function so the Supabase cron (migration 0012) can pull
/// Canvas assignments + events while every Atlas client is closed.
///
/// The feed URL is a CAPABILITY URL (its token IS the auth): it is sent once to the
/// server, stored in Vault, and never held on the client. The persisted connection
/// status ("Last synced Xm ago" / error) is read back separately via
/// `AtlasDB.loadCanvasConnection()` — this service only performs the connect /
/// disconnect action. Mirrors `GoogleAuthService`'s server-sync handoff.
@MainActor
public final class CanvasService: ObservableObject {

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// POST the feed URL + destination space to `canvas-connect`. `jwt` is the caller's
    /// Supabase user access token (verified server-side by `auth.getUser`). Throws on any
    /// non-2xx so the caller can show a calm error and stay disconnected.
    public func connect(feedUrl: String, spaceName: String, jwt: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "feedUrl": feedUrl,
            "spaceName": spaceName,
        ])
        try await call(method: "POST", jwt: jwt, body: body)
    }

    /// PATCH the destination space (`canvas-connect`) → updates only where unmatched
    /// Canvas items land; the feed secret and conditional-GET cache are untouched, so a
    /// space change never resets sync. `jwt` is the caller's Supabase access token
    /// (verified server-side). Throws on any non-2xx so the caller can revert the picker.
    public func updateSpace(spaceName: String, jwt: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "spaceName": spaceName,
        ])
        try await call(method: "PATCH", jwt: jwt, body: body)
    }

    /// DELETE the connection (`canvas-connect`) → the row is marked revoked and the Vault
    /// secret removed. The client returns to the paste form.
    public func disconnect(jwt: String) async throws {
        try await call(method: "DELETE", jwt: jwt, body: nil)
    }

    /// Client-side shape check for a Canvas Calendar Feed URL: https + a host + a
    /// Canvas ICS feed path (`.ics` suffix or a `/feeds/calendars` segment). A calm
    /// gate before we bother the server (which re-validates and Vaults the URL).
    /// Shared by the Mac and iOS paste fields. `nonisolated` — a pure function, so
    /// callers (views, tests) invoke it synchronously off the main actor.
    public nonisolated static func isValidFeedURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              !(url.host ?? "").isEmpty else { return false }
        let path = url.path.lowercased()
        return path.hasSuffix(".ics") || path.contains("/feeds/calendars")
    }

    private func call(method: String, jwt: String, body: Data?) async throws {
        let url = SupabaseConfig.functionsBase.appendingPathComponent("canvas-connect")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            throw CanvasConnectError.requestFailed(detail)
        }
    }
}

public enum CanvasConnectError: Error {
    case requestFailed(String)
}

// ─────────────────────────────────────────────────────────────────────────────
// FeedService — multi-ICS calendar feeds (generalizes CanvasService)
// ─────────────────────────────────────────────────────────────────────────────

/// Connect client for the `calendar_feeds` model — N subscribed calendar feeds, each
/// either a Canvas feed or a generic ICS feed. Generalizes `CanvasService`: the feed
/// URL is still a CAPABILITY URL sent once to the `feeds-connect` edge function and
/// Vaulted server-side, never held on the client. Persisted per-feed status is read
/// back separately via `AtlasDB.loadCalendarFeeds()`. Same auth/request idioms as
/// `CanvasService`; the UI agent migrates call sites off `CanvasService` later.
@MainActor
public final class FeedService: ObservableObject {

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// POST a new feed to `feeds-connect`: the capability URL, its type ("canvas"|"ics"),
    /// a display name, and the destination space. `jwt` is the caller's Supabase access
    /// token (verified server-side). Throws on any non-2xx so the caller can show a calm
    /// error and stay disconnected.
    public func connect(feedUrl: String, feedType: String,
                        displayName: String, spaceName: String, jwt: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "feedUrl": feedUrl,
            "feedType": feedType,
            "displayName": displayName,
            "spaceName": spaceName,
        ])
        try await call(method: "POST", jwt: jwt, body: body)
    }

    /// PATCH an existing feed (`feeds-connect`) by id — change its destination space
    /// and/or display name. Omitted fields are left untouched server-side (the feed
    /// secret and conditional-GET cache are never reset). `jwt` is the caller's access
    /// token. Throws on any non-2xx so the caller can revert the edit.
    public func updateFeed(id: UUID, spaceName: String? = nil,
                           displayName: String? = nil, jwt: String) async throws {
        var payload: [String: Any] = ["id": id.uuidString]
        if let spaceName { payload["spaceName"] = spaceName }
        if let displayName { payload["displayName"] = displayName }
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await call(method: "PATCH", jwt: jwt, body: body)
    }

    /// DELETE a feed (`feeds-connect`) by id → the row is marked revoked and its Vault
    /// secret removed. The client drops the feed from its list.
    public func disconnect(id: UUID, jwt: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["id": id.uuidString])
        try await call(method: "DELETE", jwt: jwt, body: body)
    }

    /// Permissive client-side shape check for a generic ICS feed URL: https + a host +
    /// an ICS-ish path (a `.ics` suffix OR an "ics"/"calendar"/"feed" segment — many
    /// providers, e.g. Schoology/Outlook, don't end in `.ics`). A calm gate before we
    /// bother the server (which re-validates and Vaults the URL). Looser than the Canvas
    /// check (`CanvasService.isValidFeedURL`), which stays available for Canvas paste
    /// fields. `nonisolated` — a pure function callable off the main actor.
    public nonisolated static func isValidICSURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              !(url.host ?? "").isEmpty else { return false }
        let path = url.path.lowercased()
        return path.hasSuffix(".ics")
            || path.contains("ics")
            || path.contains("calendar")
            || path.contains("feed")
    }

    private func call(method: String, jwt: String, body: Data?) async throws {
        let url = SupabaseConfig.functionsBase.appendingPathComponent("feeds-connect")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            throw CanvasConnectError.requestFailed(detail)
        }
    }
}
