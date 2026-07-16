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
    ///   • `openid`/`email` — surface WHICH Google account granted access, so a
    ///     multi-account connection can be labelled with its login (id_token).
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/documents",
        "https://www.googleapis.com/auth/drive.file",
        "openid",
        "email",
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
            // `select_account` so a SECOND (or different) Google login is pickable —
            // without it Google silently reuses the browser's active session, making
            // multi-account impossible. `consent` still forces a refresh_token issue.
            .init(name: "prompt", value: "select_account consent"),
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
        let id_token: String?
    }

    /// The granted account's email, decoded from an OpenID Connect `id_token`
    /// (`header.payload.signature`). We only READ the unverified payload for a
    /// display label — the token itself came straight from Google's token endpoint
    /// over TLS, so no signature check is needed here. Returns nil if absent/malformed.
    static func email(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
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

/// Minimal generic-password Keychain wrapper for Google token blobs.
///
/// Two coexisting slots under one `service`:
///   • the legacy singleton `account = "oauth-tokens"` — the Drive/Docs "primary"
///     login that powers Notes ↔ Google Docs (its live access token is minted here).
///   • per-connection slots `account = <connectionId>` — one credential per connected
///     calendar account (multi-account, 0028). Keying by id (not a machine-global
///     single slot) is what stops a credential leaking across Atlas account switches.
/// `deleteAll()` clears every slot under the service, so a Google sign-out is total.
enum GoogleKeychain {
    static let service = "com.atlas.Atlas.google"
    static let account = "oauth-tokens"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ tokens: GoogleTokens, account: String = account) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var add = baseQuery(account: account)
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String = account) -> GoogleTokens? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    static func delete(account: String = account) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    /// Per-connection convenience wrappers — key the slot by the connection's id.
    @discardableResult
    static func save(_ tokens: GoogleTokens, for connectionId: UUID) -> Bool {
        save(tokens, account: connectionId.uuidString)
    }
    static func delete(for connectionId: UUID) {
        delete(account: connectionId.uuidString)
    }

    /// Removes EVERY Google credential under the service — the singleton slot and all
    /// per-connection slots — so a sign-out leaves nothing behind (no cross-account leak).
    static func deleteAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
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

    /// The tokens + granted account email captured by a completed OAuth round-trip —
    /// what the caller needs to create (or reconnect) a `google_connections` row.
    struct GrantedAccount {
        let refreshToken: String
        let email: String
    }

    /// Opens the system browser to Google's account chooser + consent screen and captures
    /// the authorization code via the one-shot loopback listener, then exchanges it for
    /// tokens. The consent click itself can only be performed by the human. Also refreshes
    /// the singleton (Drive/Docs) slot so Notes ↔ Google Docs follows the latest login.
    ///
    /// Returns the granted refresh token + account email (for creating/reconnecting a
    /// connection), or nil when the user cancelled, Google issued no refresh token, or the
    /// id_token carried no email (`errorMessage` is set with a calm description on failure).
    @discardableResult
    func connect() async -> GrantedAccount? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard GoogleOAuthConfig.isConfigured else {
            errorMessage = GoogleAuthError.notConfigured.errorDescription
            return nil
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
            let (fresh, email) = try await exchange(body: body, existingRefresh: nil)
            // Refresh the singleton slot so Drive/Docs use the latest login.
            tokens = fresh
            GoogleKeychain.save(fresh)
            guard let refresh = fresh.refreshToken, let email else {
                errorMessage = "Google didn't return the account details — try connecting again."
                return nil
            }
            return GrantedAccount(refreshToken: refresh, email: email)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Signs out of Google entirely — clears the singleton slot AND every per-connection
    /// credential (no cross-account leak). The `google_connections` rows themselves are
    /// removed via `deleteConnection` (server vault), not here.
    func disconnect() {
        tokens = nil
        GoogleKeychain.deleteAll()
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

    // MARK: - Multi-account connections (google-connect edge function)

    /// Creates (or reconnects) a connection: POST `{refreshToken, name, spaceId?, googleEmail}`.
    /// A re-POST for an existing (user, email, calendar) is treated server-side as a
    /// reconnect — vault secret replaced, status reset to active. Throws on any non-2xx so
    /// the caller can surface the message (e.g. a 409 duplicate).
    func createConnection(refreshToken: String, name: String, spaceId: UUID?, googleEmail: String, jwt: String) async throws {
        var payload: [String: Any] = [
            "refreshToken": refreshToken,
            "name": name,
            "googleEmail": googleEmail,
        ]
        if let spaceId { payload["spaceId"] = spaceId.uuidString }
        try await callConnect(method: "POST", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: payload))
    }

    /// Renames / re-maps a connection: PATCH `{connectionId, name?, spaceId?}`. An occupied
    /// destination space is rejected server-side (409) — the caller surfaces the message and
    /// reverts the picker.
    func updateConnection(connectionId: UUID, name: String? = nil, spaceId: UUID?? = nil, jwt: String) async throws {
        var payload: [String: Any] = ["connectionId": connectionId.uuidString]
        if let name { payload["name"] = name }
        // Outer optional nil ⇒ don't touch the mapping; inner nil ⇒ explicitly unlink (null).
        if let spaceId { payload["spaceId"] = spaceId.map { $0.uuidString } ?? NSNull() }
        try await callConnect(method: "PATCH", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: payload))
    }

    /// Removes a connection + its vault secret: DELETE `{connectionId}`. Other connections
    /// are untouched. Also drops the local per-connection keychain credential.
    func deleteConnection(connectionId: UUID, jwt: String) async throws {
        try await callConnect(method: "DELETE", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: ["connectionId": connectionId.uuidString]))
        GoogleKeychain.delete(for: connectionId)
    }

    // MARK: - Notes & Docs connection (dedicated Drive/Docs login, singleton)

    /// Signs the dedicated Drive/Docs login in: POST `{docs: true, refreshToken, googleEmail}`
    /// to `google-connect`. There is at most ONE such login per user — a re-POST replaces it.
    /// Independent of the calendar connections; powers Notes ↔ Google Docs background work.
    func connectDocs(refreshToken: String, googleEmail: String, jwt: String) async throws {
        let payload: [String: Any] = [
            "docs": true,
            "refreshToken": refreshToken,
            "googleEmail": googleEmail,
        ]
        try await callConnect(method: "POST", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: payload))
    }

    /// Removes the dedicated Drive/Docs login: DELETE `{docs: true}`. Calendar connections
    /// are untouched (the server then falls back to the oldest calendar login for Docs).
    func disconnectDocs(jwt: String) async throws {
        try await callConnect(method: "DELETE", jwt: jwt,
                              body: try JSONSerialization.data(withJSONObject: ["docs": true]))
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
        let (fresh, _) = try await exchange(body: body, existingRefresh: refresh)
        tokens = fresh
        GoogleKeychain.save(fresh)
        return fresh.accessToken
    }

    // MARK: Network

    /// Exchanges an authorization-code (or refresh) body for tokens, plus the account
    /// email decoded from the response's OpenID `id_token` when present (nil on refresh,
    /// which carries no id_token).
    private func exchange(body: Data, existingRefresh: String?) async throws -> (GoogleTokens, String?) {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GoogleAuthError.tokenExchangeFailed(detail)
        }
        let tokens = try GoogleOAuth.decodeTokens(from: data, existingRefresh: existingRefresh)
        struct IDTokenEnvelope: Decodable { let id_token: String? }
        let idToken = (try? JSONDecoder().decode(IDTokenEnvelope.self, from: data))?.id_token
        return (tokens, GoogleOAuth.email(fromIDToken: idToken))
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
        // Literal copy of the one-pick Drive import landing (DriveOnePickFlow.respond)
        // — kicker / serif headline / hairline / staggered rise — reworded for connect.
        let html = """
        <!DOCTYPE html>
        <html lang="en"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light"><title>\(title)</title>
        <style>
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 background: #fbfaf7; color: #1a191d; text-align: center;
                 font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
          main { padding: 32px; }
          main > * { opacity: 0; animation: rise 0.55s cubic-bezier(0.22, 0.61, 0.36, 1) forwards; }
          .kicker { margin: 0; font-size: 11px; font-weight: 600;
                    letter-spacing: 0.08em; text-transform: uppercase; color: #b04f2f; }
          h1 { margin: 14px 0 0; font-family: Georgia, "Times New Roman", serif;
               font-weight: 500; font-size: clamp(34px, 6vw, 46px); letter-spacing: -0.021em;
               animation-delay: 0.08s; }
          hr { width: 40px; margin: 22px auto; border: 0;
               border-top: 1px solid rgba(0, 0, 0, 0.14); animation-delay: 0.16s; }
          p { margin: 0; color: #6c6a72; font-size: 15px; line-height: 1.5;
              animation-delay: 0.24s; }
          @keyframes rise { from { opacity: 0; transform: translateY(10px); }
                            to { opacity: 1; transform: none; } }
          @media (prefers-reduced-motion: reduce) { main > * { animation: none; opacity: 1; } }
        </style></head>
        <body><main>
          <p class="kicker">Atlas</p>
          <h1>\(title)</h1>
          <hr>
          <p>\(message)</p>
        </main></body></html>
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
