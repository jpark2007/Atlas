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
