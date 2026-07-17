import Foundation
import AuthenticationServices
import CryptoKit
import Security
import AtlasCore

@MainActor
final class AuthService: ObservableObject {

    enum State: Equatable {
        case loading          // restoring a saved session at launch
        case signedOut
        case signedIn(SupabaseUser)
        case offline          // "continue without account" — mock data only
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var session: SupabaseSession?
    @Published var errorMessage: String?
    @Published var isWorking = false
    /// Set after sign-up when the project requires email confirmation.
    @Published var infoMessage: String?

    private let api = SupabaseAuth()
    /// Legacy UserDefaults key — read once for one-time migration into the Keychain.
    private let sessionKey = "atlas.supabase.session"
    private let keychainService = KeychainStore.Service.supabase
    private let keychainAccount = "session"
    private var refreshTask: Task<SupabaseSession?, Never>?
    private var pkceVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?
    private let presenter = AuthPresentationAnchor()

    var displayName: String {
        if case .signedIn(let user) = state { return user.displayName }
        return "Jordan"
    }

    init() { restore() }

    // MARK: - Session lifecycle

    func restore() {
        guard let data = loadSessionData(),
              let saved = try? JSONDecoder().decode(SupabaseSession.self, from: data) else {
            state = .signedOut
            return
        }
        session = saved
        state = .signedIn(saved.user)
        // Refresh in the background to keep the token fresh.
        Task { await refreshIfPossible() }
    }

    /// Session bytes from the Keychain, migrating a pre-Keychain UserDefaults value
    /// on first read after update (adopt into Keychain, delete from UserDefaults) so
    /// existing users aren't signed out.
    private func loadSessionData() -> Data? {
        if let data = KeychainStore.load(service: keychainService, account: keychainAccount) {
            return data
        }
        guard let legacy = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        KeychainStore.save(legacy, service: keychainService, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: sessionKey)
        return legacy
    }

    private func refreshIfPossible() async {
        _ = await validSession()
    }

    /// A session whose access token is valid right now — refreshed first when the
    /// stored one is expired or within a minute of it (mirrors mobile's
    /// `SessionStore.refreshIfNeeded`). Supabase callers (edge functions, AtlasDB)
    /// must use this instead of reading `session` directly: the JWT TTL is 1 hour
    /// and nothing else refreshes it mid-session. Returns nil when signed out or
    /// the refresh token itself is rejected — ask the user to sign in again.
    ///
    /// Concurrent callers share one in-flight refresh: GoTrue rotates refresh
    /// tokens, so parallel refreshes with the same token can revoke the session.
    func validSession() async -> SupabaseSession? {
        guard let current = session else { return nil }
        guard let expiresAt = current.expiresAt,
              Date().timeIntervalSince1970 >= expiresAt - 60 else {   // 60 s skew
            return current
        }
        if let inFlight = refreshTask { return await inFlight.value }
        let task = Task { () -> SupabaseSession? in
            guard let fresh = try? await api.refresh(refreshToken: current.refreshToken) else { return nil }
            persist(fresh)
            return fresh
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    func validAccessToken() async -> String? {
        await validSession()?.accessToken
    }

    private func persist(_ session: SupabaseSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            KeychainStore.save(data, service: keychainService, account: keychainAccount)
        }
        state = .signedIn(session.user)
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async {
        await run {
            let s = try await api.signIn(email: email, password: password)
            persist(s)
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            if let s = try await api.signUp(email: email, password: password) {
                persist(s)
            } else {
                infoMessage = "Check \(email) to confirm your account, then sign in. (Or disable email confirmation in Supabase → Authentication → Providers.)"
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Whether the running binary was actually signed with the Sign In with Apple
    /// entitlement. Debug/dev builds carry it (button shows); Developer ID
    /// direct-download builds sign against Atlas-DeveloperID.entitlements which omits
    /// it (button hides — email/password sign-in remains). Reading the live
    /// code-signing entitlement means the same source works in both builds, no config.
    static let appleSignInAvailable: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.applesignin" as CFString, nil) != nil
    }()

    func signInWithApple() async {
        await run {
            let nonce = PKCE.verifier()
            let credential = try await AppleSignInCoordinator(presenter: presenter)
                .signIn(hashedNonce: PKCE.sha256(nonce))
            let s = try await api.signInWithIdToken(provider: "apple", idToken: credential, nonce: nonce)
            persist(s)
        }
    }

    /// Web-based Sign in with Apple for Developer ID (direct-download) builds, which
    /// legally can't carry the native `applesignin` entitlement (`appleSignInAvailable`
    /// == false). Runs Supabase-hosted Apple OAuth (PKCE) in the same
    /// ASWebAuthenticationSession browser flow as Google, ending in the identical
    /// Keychain-persisted session as native SIWA — one session storage path.
    func signInWithAppleWeb() async {
        await run {
            let verifier = PKCE.verifier()
            pkceVerifier = verifier
            let url = api.pkceAuthorizeURL(provider: "apple", codeChallenge: PKCE.challenge(verifier))
            let callback = try await startWebAuth(url: url)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw SupabaseAuthError(message: "Apple sign-in returned no authorization code.")
            }
            let s = try await api.exchangePKCE(authCode: code, verifier: verifier)
            persist(s)
        }
    }

    // MARK: - Google OAuth (PKCE via web auth session)

    func signInWithGoogle() async {
        await run {
            let verifier = PKCE.verifier()
            pkceVerifier = verifier
            let url = api.pkceAuthorizeURL(provider: "google", codeChallenge: PKCE.challenge(verifier))
            let callback = try await startWebAuth(url: url)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw SupabaseAuthError(message: "Google sign-in returned no authorization code.")
            }
            let s = try await api.exchangePKCE(authCode: code, verifier: verifier)
            persist(s)
        }
    }

    private func startWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: SupabaseConfig.redirectScheme
            ) { callbackURL, error in
                if let callbackURL { continuation.resume(returning: callbackURL) }
                else { continuation.resume(throwing: error ?? SupabaseAuthError(message: "Sign-in cancelled.")) }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }
    }

    // MARK: - Offline / sign out

    func continueOffline() { state = .offline }

    func signOut() {
        if let token = session?.accessToken { Task { await api.signOut(accessToken: token) } }
        clearStoredSession()
        session = nil
        state = .signedOut
    }

    /// Wipes the persisted session from the Keychain (and any lingering legacy
    /// UserDefaults copy). Shared by sign-out and delete-account.
    private func clearStoredSession() {
        KeychainStore.delete(service: keychainService, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - Delete account

    /// Permanently deletes the signed-in user via the `delete-account` edge
    /// function (service-role `auth.admin.deleteUser`, which cascade-wipes every
    /// user-scoped row). On success the local session is cleared and we drop back
    /// to the sign-in gate. Returns `nil` on success, or a message to show inline.
    /// Uses `validAccessToken()` so a >1h-old JWT is refreshed before the call.
    func deleteAccount() async -> String? {
        guard let token = await validAccessToken() else {
            return "Your session expired — sign in again, then delete your account."
        }
        let url = SupabaseConfig.functionsBase.appendingPathComponent("delete-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "Couldn't delete your account. Please try again in a moment."
            }
        } catch {
            return "Couldn't delete your account. Check your connection and try again."
        }
        // The auth user no longer exists — clear the local session (no server
        // logout to call) and return to the gate.
        clearStoredSession()
        session = nil
        state = .signedOut
        return nil
    }

    // MARK: - Helper

    private func run(_ work: () async throws -> Void) async {
        isWorking = true; errorMessage = nil; infoMessage = nil
        defer { isWorking = false }
        do { try await work() }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

// MARK: - PKCE / nonce utilities

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Hex SHA256 of a string — used as the Apple nonce.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Presentation anchor (shared by Apple + web auth)

final class AuthPresentationAnchor: NSObject, ASAuthorizationControllerPresentationContextProviding,
                                    ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor()
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor()
    }
    private func anchor() -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

// MARK: - Apple Sign In coordinator

final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    private let presenter: AuthPresentationAnchor
    private var continuation: CheckedContinuation<String, Error>?

    init(presenter: AuthPresentationAnchor) { self.presenter = presenter }

    /// Runs the Apple flow and returns the identity token (JWT) on success.
    func signIn(hashedNonce: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = presenter
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: SupabaseAuthError(message: "Apple returned no identity token."))
            return
        }
        continuation?.resume(returning: token)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        continuation?.resume(throwing: SupabaseAuthError(
            message: "Apple sign-in failed: \(error.localizedDescription) [\(ns.domain) code \(ns.code)]"))
    }
}
