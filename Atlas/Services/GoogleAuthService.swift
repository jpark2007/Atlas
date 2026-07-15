import Foundation
import CryptoKit
import Network
import AppKit
import AtlasCore

// MARK: - Config

/// Static configuration for the Google OAuth (Desktop-app) client.
///
/// The client id/secret are read from the generated Info.plist (fed by the
/// gitignored `Config/Secrets.xcconfig` → `INFOPLIST_KEY_GoogleOAuthClientID` /
/// `_Secret`). The client id may ship in the bundle; the secret never enters
/// committed source. For a Desktop client the secret is not a hard boundary —
/// PKCE is the real protection.
enum GoogleOAuthConfig {
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Read+write events on the user's calendars (two-way sync, WS-5) plus the
    /// Google Docs + Drive scopes for Notes ↔ Google Docs (WS-10):
    ///   • `documents`  — read/write the backing Doc's content + structure.
    ///   • `drive.file` — create/locate the Docs Atlas itself owns.
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/documents",
        "https://www.googleapis.com/auth/drive.file",
    ]

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String) ?? ""
    }

    static var clientSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String) ?? ""
    }

    /// True once a client id is present (Secrets.xcconfig wired). Gates `connect()`.
    static var isConfigured: Bool { !clientID.isEmpty }
}

// MARK: - Token model

/// The persisted OAuth token set. Stored in the Keychain as a JSON blob.
struct GoogleTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    /// Treats the token as expired 60 s early so an in-flight request never races
    /// the boundary.
    func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-60)
    }
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError, Equatable {
    case notConfigured
    case notConnected
    case authorizationFailed(String)
    case stateMismatch
    case tokenExchangeFailed(String)
    case serverSyncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google client ID missing — create Config/Secrets.xcconfig (see Secrets.example.xcconfig)."
        case .notConnected:
            return "Not connected to Google. Connect in Settings → Calendars."
        case .authorizationFailed(let reason):
            return Self.humanizedAuthorizationFailure(reason)
        case .stateMismatch:
            return "Google sign-in returned a mismatched state (possible CSRF) — try again."
        case .tokenExchangeFailed(let body):
            return "Google token exchange failed: \(body)"
        case .serverSyncFailed(let body):
            return "Cloud sync handoff failed: \(body)"
        }
    }

    /// Renders a Google OAuth failure. The well-known `access_denied` code — Google
    /// (or the user) declined the browser consent, e.g. an onepick Drive-import grant —
    /// becomes an actionable sentence instead of a raw code. Any other reason (a
    /// sentence we authored, or an unmapped code) passes through verbatim.
    private static func humanizedAuthorizationFailure(_ reason: String) -> String {
        switch reason {
        case "access_denied":
            return "Google declined the permission (access_denied) — reconnect Google in Settings → Calendars and approve the Atlas access."
        default:
            return "Google sign-in failed: \(reason)"
        }
    }
}

// MARK: - Pure OAuth helpers (testable, no network / no UI)

/// Pure builders for the Google OAuth 2.0 Authorization-Code-with-PKCE flow.
/// Everything here is a value transform so it can be unit-tested directly.
/// PKCE verifier/challenge generation reuses the module-wide `PKCE` enum
/// (`Atlas/Services/AuthService.swift`) — `PKCE.challenge` is base64url(SHA256).
enum GoogleOAuth {

    /// Builds the authorization URL the system browser opens.
    static func authorizationURL(clientID: String,
                                 redirectURI: String,
                                 scopes: [String],
                                 codeChallenge: String,
                                 state: String) -> URL {
        var components = URLComponents(url: GoogleOAuthConfig.authorizationEndpoint,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    /// `application/x-www-form-urlencoded` body for the authorization-code exchange.
    static func tokenExchangeBody(code: String,
                                  codeVerifier: String,
                                  clientID: String,
                                  clientSecret: String,
                                  redirectURI: String) -> Data {
        formURLEncoded([
            "code": code,
            "code_verifier": codeVerifier,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ])
    }

    /// `application/x-www-form-urlencoded` body for refreshing an access token.
    static func refreshBody(refreshToken: String,
                            clientID: String,
                            clientSecret: String) -> Data {
        formURLEncoded([
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
        ])
    }

    /// Decode a Google token endpoint response into `GoogleTokens`. A refresh
    /// response omits `refresh_token`; in that case we keep `existingRefresh`.
    static func decodeTokens(from data: Data,
                             existingRefresh: String? = nil,
                             now: Date = Date()) throws -> GoogleTokens {
        let raw = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: raw.access_token,
            refreshToken: raw.refresh_token ?? existingRefresh,
            expiresAt: now.addingTimeInterval(TimeInterval(raw.expires_in ?? 3600)),
            scope: raw.scope
        )
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
        let scope: String?
        let token_type: String?
    }

    /// Encodes form parameters. `URLComponents` renders spaces as `%20` and leaves
    /// `+` literal, so we additionally escape `+` to `%2B` to avoid the server
    /// decoding it as a space.
    static func formURLEncoded(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let encoded = (components.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }
}

// MARK: - Keychain store

/// Minimal generic-password Keychain wrapper for the Google token blob.
enum GoogleKeychain {
    static let service = "com.atlas.Atlas.google"
    static let account = "oauth-tokens"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ tokens: GoogleTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        SecItemDelete(baseQuery() as CFDictionary)
        var add = baseQuery()
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> GoogleTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

// MARK: - Auth service

/// Drives the Google OAuth flow and vends a valid access token to callers
/// (`GoogleCalendarService`). Tokens are persisted in the Keychain and refreshed
/// transparently. The live browser round-trip is gated by `connect()`; until the
/// user authorizes, `isConnected` stays false and every caller no-ops.
@MainActor
final class GoogleAuthService: ObservableObject {

    @Published private(set) var isConnected: Bool
    @Published var isWorking = false
    @Published var errorMessage: String?

    private var tokens: GoogleTokens? {
        didSet { isConnected = (tokens != nil) }
    }
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let loaded = GoogleKeychain.load()
        self.tokens = loaded
        self.isConnected = (loaded != nil)
    }

    // MARK: Connect / disconnect

    /// Opens the system browser to Google's consent screen and captures the
    /// authorization code via a one-shot loopback listener, then exchanges it for
    /// tokens. The consent click itself can only be performed by the human.
    func connect() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard GoogleOAuthConfig.isConfigured else {
            errorMessage = GoogleAuthError.notConfigured.errorDescription
            return
        }

        do {
            let verifier = PKCE.verifier()
            let challenge = PKCE.challenge(verifier)
            let state = PKCE.verifier()

            let listener = LoopbackRedirectListener()
            let port = try await listener.start()
            let redirectURI = "http://127.0.0.1:\(port)"

            let authURL = GoogleOAuth.authorizationURL(
                clientID: GoogleOAuthConfig.clientID,
                redirectURI: redirectURI,
                scopes: GoogleOAuthConfig.scopes,
                codeChallenge: challenge,
                state: state
            )
            NSWorkspace.shared.open(authURL)

            let code = try await listener.waitForCode(expectedState: state)
            let body = GoogleOAuth.tokenExchangeBody(
                code: code,
                codeVerifier: verifier,
                clientID: GoogleOAuthConfig.clientID,
                clientSecret: GoogleOAuthConfig.clientSecret,
                redirectURI: redirectURI
            )
            let fresh = try await exchange(body: body, existingRefresh: nil)
            tokens = fresh
            GoogleKeychain.save(fresh)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        tokens = nil
        GoogleKeychain.delete()
        errorMessage = nil
    }

    // MARK: Server-sync handoff

    /// The Keychain refresh token, for handing off to the server-side sync. Nil when
    /// not connected or when Google issued no refresh token.
    var currentRefreshToken: String? { tokens?.refreshToken }

    /// True when the granted scopes include `drive.file` — required for Drive import
    /// and Docs sync. Pre-`drive.file` sessions (calendar-only) return false; the
    /// user must reconnect (which forces `prompt=consent` → re-grants all scopes).
    var hasDriveScope: Bool { (tokens?.scope ?? "").contains("drive.file") }

    /// Hands the Keychain refresh token to the `google-connect` edge function so the
    /// Supabase cron can own Google↔DB sync while every Atlas client is closed. `jwt`
    /// is the caller's Supabase user access token (verified server-side by `auth.getUser`).
    /// Throws on any non-2xx so the caller can stay in local mode + show a calm error.
    func enableServerSync(jwt: String) async throws {
        guard let refresh = tokens?.refreshToken else { throw GoogleAuthError.notConnected }
        try await callConnect(method: "POST", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: ["refreshToken": refresh]))
    }

    /// Disconnects the server-side sync (`google-connect` DELETE) → returns to local mode.
    func disableServerSync(jwt: String) async throws {
        try await callConnect(method: "DELETE", jwt: jwt, body: nil)
    }

    private func callConnect(method: String, jwt: String, body: Data?) async throws {
        let url = SupabaseConfig.functionsBase.appendingPathComponent("google-connect")
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
            throw GoogleAuthError.serverSyncFailed(detail)
        }
    }

    // MARK: Token access

    /// Returns a valid access token, refreshing transparently when expired.
    /// Throws `GoogleAuthError.notConnected` when there's no session yet.
    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw GoogleAuthError.notConnected }
        if !current.isExpired() { return current.accessToken }
        guard let refresh = current.refreshToken else { throw GoogleAuthError.notConnected }

        let body = GoogleOAuth.refreshBody(
            refreshToken: refresh,
            clientID: GoogleOAuthConfig.clientID,
            clientSecret: GoogleOAuthConfig.clientSecret
        )
        let fresh = try await exchange(body: body, existingRefresh: refresh)
        tokens = fresh
        GoogleKeychain.save(fresh)
        return fresh.accessToken
    }

    // MARK: Network

    private func exchange(body: Data, existingRefresh: String?) async throws -> GoogleTokens {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GoogleAuthError.tokenExchangeFailed(detail)
        }
        return try GoogleOAuth.decodeTokens(from: data, existingRefresh: existingRefresh)
    }
}

// MARK: - Loopback redirect listener

/// A one-shot local HTTP listener that captures the `?code=…&state=…` redirect
/// from Google's Desktop-app loopback flow. Binds an ephemeral port on the
/// loopback interface; `start()` returns the bound port so the caller can build
/// `http://127.0.0.1:<port>` as the `redirect_uri`.
///
/// `ASWebAuthenticationSession` only intercepts custom URL schemes, not an HTTP
/// loopback, so the desktop flow uses the system browser + this listener instead.
final class LoopbackRedirectListener {

    private var listener: NWListener?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private let queue = DispatchQueue(label: "com.atlas.google.loopback")

    /// Starts the listener and resolves with the bound loopback port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            self.portContinuation = continuation
            do {
                let params = NWParameters.tcp
                params.requiredInterfaceType = .loopback
                let listener = try NWListener(using: params, on: .any)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            self?.resumePort(.success(port))
                        }
                    case .failed(let error):
                        self?.resumePort(.failure(error))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
            } catch {
                self.portContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Resolves with the authorization code once the browser hits the loopback.
    func waitForCode(expectedState: String) async throws -> String {
        self.expectedState = expectedState
        return try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation
        }
    }

    // MARK: Internals

    private func resumePort(_ result: Result<UInt16, Error>) {
        guard let continuation = portContinuation else { return }
        portContinuation = nil
        continuation.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            if let data, let request = String(data: data, encoding: .utf8) {
                self.process(request: request, on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func process(request: String, on connection: NWConnection) {
        // Request line: "GET /?code=…&state=… HTTP/1.1"
        let firstLine = request.components(separatedBy: "\r\n").first ?? request
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(connection, ok: false)
            finishCode(.failure(GoogleAuthError.authorizationFailed("Malformed redirect.")))
            return
        }

        let target = String(parts[1])
        var components = URLComponents()
        if let questionMark = target.firstIndex(of: "?") {
            components.percentEncodedQuery = String(target[target.index(after: questionMark)...])
        }
        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let returnedState = items.first { $0.name == "state" }?.value

        if let error = items.first(where: { $0.name == "error" })?.value {
            respond(connection, ok: false)
            finishCode(.failure(GoogleAuthError.authorizationFailed(error)))
        } else if let code, returnedState == expectedState {
            respond(connection, ok: true)
            finishCode(.success(code))
        } else {
            respond(connection, ok: false)
            finishCode(.failure(GoogleAuthError.stateMismatch))
        }
    }

    private func respond(_ connection: NWConnection, ok: Bool) {
        let title = ok ? "Atlas connected" : "Atlas sign-in failed"
        let message = ok
            ? "You can close this tab and return to Atlas."
            : "Something went wrong. Return to Atlas and try again."
        let mark = ok ? "✓" : "✕"
        let markColor = ok ? "#b04f2f" : "#a03535"
        // Editorial-light paper style — mirrors the hosted Drive picker page.
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">\
        <title>\(title)</title><style>
        body { font-family: -apple-system, system-ui; background: #f4efe6; color: #2b2622;
               max-width: 560px; margin: 0 auto; padding: 96px 20px 0; text-align: center; }
        .mark { font-size: 34px; color: \(markColor); border: 1.5px solid \(markColor);
                border-radius: 50%; width: 64px; height: 64px; line-height: 64px;
                display: inline-block; margin-bottom: 24px; }
        h2 { font-weight: 600; margin: 0 0 10px; }
        p { color: #6b6258; font-size: 14px; margin: 0; }
        .rule { border-top: 1px solid #d9d1c2; width: 72px; margin: 28px auto 0; }
        </style></head>
        <body><div class="mark">\(mark)</div><h2>\(title)</h2><p>\(message)</p><div class="rule"></div></body></html>
        """
        let bodyData = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Content-Length: \(bodyData.count)\r\n" +
            "Connection: close\r\n\r\n"
        let payload = Data(header.utf8) + bodyData
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finishCode(_ result: Result<String, Error>) {
        guard let continuation = codeContinuation else { return }
        codeContinuation = nil
        continuation.resume(with: result)
        listener?.cancel()
        listener = nil
    }
}
