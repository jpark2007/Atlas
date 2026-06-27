import XCTest
import CryptoKit
@testable import Atlas

/// WS-5 — pure OAuth logic for the Google Desktop-app PKCE flow.
/// The live browser/consent round-trip is testing-blocked (needs the human), so
/// only the value transforms are exercised here.
final class GoogleAuthServiceTests: XCTestCase {

    // MARK: - PKCE (S256)

    /// `PKCE.challenge` must equal base64url(SHA256(verifier)) recomputed here —
    /// never a hardcoded string.
    func testPKCEChallengeIsS256OfVerifier() {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(verifier)

        let expected = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(challenge, expected)
    }

    /// RFC 7636 requires a verifier of 43…128 chars from the unreserved set, and
    /// the challenge must be URL-safe base64 (no `+`, `/`, or `=` padding).
    func testPKCEVerifierAndChallengeAreURLSafeAndSized() {
        let verifier = PKCE.verifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)

        for token in [verifier, PKCE.challenge(verifier)] {
            XCTAssertFalse(token.contains("+"))
            XCTAssertFalse(token.contains("/"))
            XCTAssertFalse(token.contains("="))
        }
    }

    func testPKCEVerifiersAreUnique() {
        XCTAssertNotEqual(PKCE.verifier(), PKCE.verifier())
    }

    // MARK: - Authorization URL builder

    func testAuthorizationURLContainsRequiredParameters() throws {
        let url = GoogleOAuth.authorizationURL(
            clientID: "client-123.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:51234",
            scopes: GoogleOAuthConfig.scopes,
            codeChallenge: "challenge-xyz",
            state: "state-abc"
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "accounts.google.com")
        XCTAssertEqual(components.path, "/o/oauth2/v2/auth")

        let items = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(items["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:51234")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["code_challenge"], "challenge-xyz")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["access_type"], "offline")
        XCTAssertEqual(items["prompt"], "consent")
        XCTAssertEqual(items["state"], "state-abc")
    }

    func testAuthorizationURLRequestsCalendarEventsScope() throws {
        let url = GoogleOAuth.authorizationURL(
            clientID: "id",
            redirectURI: "http://127.0.0.1:9",
            scopes: GoogleOAuthConfig.scopes,
            codeChallenge: "c",
            state: "s"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let scope = try XCTUnwrap((components.queryItems ?? []).first { $0.name == "scope" }?.value)
        XCTAssertTrue(scope.contains("https://www.googleapis.com/auth/calendar.events"),
                      "scope was \(scope)")
    }

    func testScopesConfiguredForCalendarEvents() {
        XCTAssertEqual(GoogleOAuthConfig.scopes, ["https://www.googleapis.com/auth/calendar.events"])
    }

    // MARK: - Token request bodies (decode back — never string-compare)

    func testTokenExchangeBodyRoundTrips() throws {
        let data = GoogleOAuth.tokenExchangeBody(
            code: "auth-code",
            codeVerifier: "verifier-1",
            clientID: "cid",
            clientSecret: "secret",
            redirectURI: "http://127.0.0.1:1234"
        )
        let parsed = formFields(data)
        XCTAssertEqual(parsed["grant_type"], "authorization_code")
        XCTAssertEqual(parsed["code"], "auth-code")
        XCTAssertEqual(parsed["code_verifier"], "verifier-1")
        XCTAssertEqual(parsed["client_id"], "cid")
        XCTAssertEqual(parsed["client_secret"], "secret")
        XCTAssertEqual(parsed["redirect_uri"], "http://127.0.0.1:1234")
    }

    func testRefreshBodyRoundTrips() {
        let data = GoogleOAuth.refreshBody(refreshToken: "r-token", clientID: "cid", clientSecret: "sec")
        let parsed = formFields(data)
        XCTAssertEqual(parsed["grant_type"], "refresh_token")
        XCTAssertEqual(parsed["refresh_token"], "r-token")
        XCTAssertEqual(parsed["client_id"], "cid")
        XCTAssertEqual(parsed["client_secret"], "sec")
    }

    // MARK: - Token decoding

    func testDecodeTokensComputesExpiryFromNow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {"access_token":"at","expires_in":3600,"refresh_token":"rt","scope":"s","token_type":"Bearer"}
        """.data(using: .utf8)!

        let tokens = try GoogleOAuth.decodeTokens(from: json, existingRefresh: nil, now: now)

        XCTAssertEqual(tokens.accessToken, "at")
        XCTAssertEqual(tokens.refreshToken, "rt")
        XCTAssertEqual(tokens.scope, "s")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(3600))
    }

    /// A refresh response omits `refresh_token`; the previous one must be kept.
    func testDecodeTokensKeepsExistingRefreshWhenAbsent() throws {
        let json = """
        {"access_token":"at2","expires_in":3599,"token_type":"Bearer"}
        """.data(using: .utf8)!

        let tokens = try GoogleOAuth.decodeTokens(from: json, existingRefresh: "old-refresh")
        XCTAssertEqual(tokens.accessToken, "at2")
        XCTAssertEqual(tokens.refreshToken, "old-refresh")
    }

    // MARK: - Expiry logic

    func testTokensExpireSixtySecondsEarly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = GoogleTokens(accessToken: "a", refreshToken: "r",
                                  expiresAt: now.addingTimeInterval(120), scope: nil)
        XCTAssertFalse(tokens.isExpired(now: now))                       // 120s left
        XCTAssertTrue(tokens.isExpired(now: now.addingTimeInterval(61))) // <60s left
    }

    // MARK: - Helpers

    /// Parse an application/x-www-form-urlencoded body back into a dictionary.
    private func formFields(_ data: Data) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(data: data, encoding: .utf8)
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value
        }
        return result
    }
}
