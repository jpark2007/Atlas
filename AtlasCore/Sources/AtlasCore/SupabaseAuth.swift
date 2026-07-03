import Foundation

// MARK: - Models

public struct SupabaseUser: Codable, Equatable {
    public let id: String
    public let email: String?
    public let userMetadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, email
        case userMetadata = "user_metadata"
    }

    public var displayName: String {
        if let name = userMetadata?["full_name"]?.value as? String, !name.isEmpty { return name }
        if let name = userMetadata?["name"]?.value as? String, !name.isEmpty { return name }
        if let email, let handle = email.split(separator: "@").first { return String(handle) }
        return "there"
    }
}

public struct SupabaseSession: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: TimeInterval?
    public let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

/// Error surfaced from the GoTrue REST API (`{ "error_description": ... }` or `{ "msg": ... }`).
public struct SupabaseAuthError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(message: String) { self.message = message }
}

// MARK: - REST client

/// Thin async wrapper over Supabase's GoTrue auth REST API. Deliberately
/// dependency-free (URLSession) so the build never waits on package resolution.
/// Swap for the official supabase-swift SDK when we add realtime/Postgres.
public struct SupabaseAuth {
    public var session: URLSession = .shared

    public init(session: URLSession = .shared) { self.session = session }

    private func request(_ path: String, method: String = "POST", bearer: String? = nil,
                         query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        var components = URLComponents(url: SupabaseConfig.authBase.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError(message: "No response from server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError(message: Self.errorMessage(from: data, status: http.statusCode))
        }
        return data
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error"] {
                if let s = json[key] as? String { return s }
            }
        }
        return "Request failed (HTTP \(status))."
    }

    private func decodeSession(_ data: Data) throws -> SupabaseSession {
        let decoder = JSONDecoder()
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    // MARK: Email / password

    /// Sign up. Note: if the project requires email confirmation (Supabase
    /// default), this returns a user but NOT a usable session until confirmed.
    public func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let data = try await request("signup", body: ["email": email, "password": password])
        // When confirmation is required, there's no access_token in the payload.
        return try? decodeSession(data)
    }

    public func signIn(email: String, password: String) async throws -> SupabaseSession {
        let data = try await request("token", query: [.init(name: "grant_type", value: "password")],
                                     body: ["email": email, "password": password])
        return try decodeSession(data)
    }

    /// Send a password-reset email (GoTrue `recover`). Fire-and-forget: any 2xx
    /// means Supabase accepted the request; it never reveals whether the address
    /// exists, so success just means "if that's an account, a link is on its way."
    public func resetPassword(email: String) async throws {
        _ = try await request("recover", body: ["email": email])
    }

    public func refresh(refreshToken: String) async throws -> SupabaseSession {
        let data = try await request("token", query: [.init(name: "grant_type", value: "refresh_token")],
                                     body: ["refresh_token": refreshToken])
        return try decodeSession(data)
    }

    /// Native Sign in with Apple / Google: exchange a provider id_token for a
    /// Supabase session. Requires the provider enabled in the Supabase dashboard.
    public func signInWithIdToken(provider: String, idToken: String, nonce: String?) async throws -> SupabaseSession {
        var body: [String: Any] = ["provider": provider, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let data = try await request("token", query: [.init(name: "grant_type", value: "id_token")], body: body)
        return try decodeSession(data)
    }

    public func signOut(accessToken: String) async {
        _ = try? await request("logout", bearer: accessToken)
    }

    /// PKCE authorize URL for a browser OAuth provider (Google) via
    /// ASWebAuthenticationSession. `codeChallenge` = base64url(SHA256(verifier)).
    public func pkceAuthorizeURL(provider: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: SupabaseConfig.authBase.appendingPathComponent("authorize"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "provider", value: provider),
            .init(name: "redirect_to", value: SupabaseConfig.redirectURL),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        return components.url!
    }

    /// Exchange the `?code=` returned to our redirect for a session (PKCE).
    public func exchangePKCE(authCode: String, verifier: String) async throws -> SupabaseSession {
        let data = try await request("token", query: [.init(name: "grant_type", value: "pkce")],
                                     body: ["auth_code": authCode, "code_verifier": verifier])
        return try decodeSession(data)
    }
}

// MARK: - AnyCodable (minimal, for user_metadata)

public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else { value = "" }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        default: try c.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        "\(lhs.value)" == "\(rhs.value)"
    }
}
