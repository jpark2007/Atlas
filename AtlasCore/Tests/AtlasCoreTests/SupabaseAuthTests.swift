import XCTest
@testable import AtlasCore

/// A dead refresh token must be distinguishable from a transient failure, and
/// signing out must only end this device's session.
final class SupabaseAuthTests: XCTestCase {

    override func tearDown() {
        StubProtocol.handler = nil
        super.tearDown()
    }

    private func auth(status: Int, body: String) -> SupabaseAuth {
        StubProtocol.handler = { request in
            StubProtocol.lastRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return SupabaseAuth(session: URLSession(configuration: config))
    }

    func testRejectedRefreshTokenIsFlagged() async {
        let api = auth(status: 400, body: #"{"code":400,"error_code":"refresh_token_already_used","msg":"Invalid Refresh Token: Already Used"}"#)
        do {
            _ = try await api.refresh(refreshToken: "dead")
            XCTFail("expected a throw")
        } catch let error as SupabaseAuthError {
            XCTAssertEqual(error.status, 400)
            XCTAssertTrue(error.isRefreshTokenRejected)
            XCTAssertEqual(error.message, "Invalid Refresh Token: Already Used")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testServerErrorIsNotARejection() async {
        let api = auth(status: 503, body: "")
        do {
            _ = try await api.refresh(refreshToken: "fine")
            XCTFail("expected a throw")
        } catch let error as SupabaseAuthError {
            XCTAssertEqual(error.status, 503)
            XCTAssertFalse(error.isRefreshTokenRejected)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRateLimitIsNotARejection() {
        XCTAssertFalse(SupabaseAuthError(message: "slow down", status: 429).isRefreshTokenRejected)
        XCTAssertFalse(SupabaseAuthError(message: "no status").isRefreshTokenRejected)
    }

    func testSignOutOnlyEndsThisDevicesSession() async {
        let api = auth(status: 204, body: "")
        await api.signOut(accessToken: "jwt")
        let query = StubProtocol.lastRequest?.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
        XCTAssertEqual(StubProtocol.lastRequest?.url?.lastPathComponent, "logout")
        XCTAssertEqual(query?.first(where: { $0.name == "scope" })?.value, "local")
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
