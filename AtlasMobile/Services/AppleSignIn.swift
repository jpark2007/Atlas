import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import AtlasCore

/// iOS mirror of the Mac `AppleSignInCoordinator` (Atlas/Services/AuthService.swift):
/// runs the native ASAuthorization flow and returns the Apple identity token, which
/// `MobileStore.signInWithApple()` exchanges for a Supabase session. Presents from
/// the foreground scene's key window (the iOS `ASPresentationAnchor`).
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    /// Runs the Apple flow and returns the identity token (JWT) on success.
    /// Throws `CancellationError` when the user dismisses the Apple sheet.
    func signIn(hashedNonce: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
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
        if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
            continuation?.resume(throwing: CancellationError())   // user dismissed the sheet
            return
        }
        continuation?.resume(throwing: SupabaseAuthError(
            message: "Apple sign-in failed: \(error.localizedDescription) [\(ns.domain) code \(ns.code)]"))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
    }
}

/// Nonce utilities for the Apple id_token exchange — mirrors the Mac `PKCE` helper
/// (that one lives in the Atlas app target, not AtlasCore, so it isn't shareable).
enum AppleNonce {
    /// Cryptographically-random raw nonce; sent to Supabase alongside the id_token.
    static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Hex SHA256 of the raw nonce — what goes on the ASAuthorization request.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
