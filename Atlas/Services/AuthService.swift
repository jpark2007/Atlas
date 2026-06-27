import Foundation
import AuthenticationServices
import CryptoKit

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
    private let sessionKey = "atlas.supabase.session"
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
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let saved = try? JSONDecoder().decode(SupabaseSession.self, from: data) else {
            state = .signedOut
            return
        }
        session = saved
        state = .signedIn(saved.user)
        // Refresh in the background to keep the token fresh.
        Task { await refreshIfPossible() }
    }

    private func refreshIfPossible() async {
        guard let refreshToken = session?.refreshToken else { return }
        if let fresh = try? await api.refresh(refreshToken: refreshToken) {
            persist(fresh)
        }
    }

    private func persist(_ session: SupabaseSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
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

    func signInWithApple() async {
        await run {
            let nonce = PKCE.verifier()
            let credential = try await AppleSignInCoordinator(presenter: presenter)
                .signIn(hashedNonce: PKCE.sha256(nonce))
            let s = try await api.signInWithIdToken(provider: "apple", idToken: credential, nonce: nonce)
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
        UserDefaults.standard.removeObject(forKey: sessionKey)
        session = nil
        state = .signedOut
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
        continuation?.resume(throwing: SupabaseAuthError(message: "Apple sign-in failed: \(error.localizedDescription)"))
    }
}
