import Foundation
import Network
import AtlasCore

// MARK: - Config

/// Configuration for Google's desktop-picker ("onepick") Drive import flow.
///
/// Unlike the classic `google.picker` iframe (which needs third-party cookies and
/// so fails in Safari/WKWebView), onepick has Google host the file chooser
/// top-level — it works in every browser. Google mandates a **public HTTPS**
/// `redirect_uri` for it, so a tiny static page at `redirectURI` bounces the
/// result to the app's `http://127.0.0.1:<port>` loopback listener. That page is
/// deployed alongside the landing site (see `landing/drive-callback/index.html`)
/// and its URL is also registered as an Authorized redirect URI on the GCP OAuth
/// client. Fed from `Config/Secrets.xcconfig` → Info.plist, same wiring as
/// `GoogleOAuthConfig`.
enum DriveOnePickConfig {
    /// The onepick flow requests `drive.file` ALONE — the picked files are the
    /// only grant, so consent reads as a native file chooser (non-sensitive, no CASA).
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    /// The WEB OAuth client (same GCP project as the desktop client, so drive.file
    /// grants land on the same app). Used here because only Web clients accept a
    /// public-HTTPS Authorized redirect URI in the GCP console — Desktop clients
    /// are loopback-only. Public identifier by design; the auth code is never
    /// exchanged, so no client secret is involved.
    static let webClientID =
        "450945006140-oqmqe97ui7llvtb5dfknoi1ei6vse1uu.apps.googleusercontent.com"

    static var redirectURI: String {
        (Bundle.main.object(forInfoDictionaryKey: "DriveOnePickRedirectURI") as? String) ?? ""
    }

    /// True once the public-HTTPS bounce URL is wired (Secrets.xcconfig). Gates import.
    static var isConfigured: Bool { !redirectURI.isEmpty }
}

// MARK: - Auth URL

enum DriveOnePick {

    /// Builds the onepick authorization URL. `trigger_onepick=true` turns the
    /// consent screen INTO the Drive file picker; on return Google appends
    /// `picked_file_ids` (comma-separated) alongside `code` + `state`. `drive.file`
    /// is the only scope. `prompt=consent` + `access_type=offline` keep parity with
    /// the OAuth connect flow (fresh grant), though this flow only reads the ids.
    static func authorizationURL(clientID: String, redirectURI: String, state: String) -> URL {
        var components = URLComponents(url: GoogleOAuthConfig.authorizationEndpoint,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: DriveOnePickConfig.driveFileScope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "trigger_onepick", value: "true"),
            .init(name: "allow_multiple", value: "true"),
            .init(name: "state", value: state),
        ]
        return components.url!
    }
}

// MARK: - Errors

enum DriveOnePickError: LocalizedError {
    case cancelled
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Drive import cancelled."
        case .timedOut:  return "Drive import timed out — try again."
        }
    }
}

// MARK: - Picked file model

/// A file chosen in the onepick picker, enriched with Drive metadata for the
/// drive-import contract. `Encodable` → the POST body. Missing metadata encodes as
/// `null`; the server keeps only files with a string `mimeType` (a bare-id fallback
/// is dropped best-effort).
struct PickedFile: Encodable {
    let id: String
    let name: String?
    let mimeType: String?
    let modifiedTime: String?
}

/// Enriches picked file ids with Drive metadata (name/mimeType/modifiedTime) so
/// the server can classify each — a Google Doc → backing note, everything else →
/// a view-only file reference. Uses the app's own `drive.file` token (project-scoped,
/// so it can read onepick-picked files). A file the token can't read falls back to a
/// bare id. Same REST pattern as `ReferencePreviewLoader`/`GoogleDocsService`.
func enrichPickedFiles(ids: [String], token: String,
                       urlSession: URLSession = .shared) async -> [PickedFile] {
    var files: [PickedFile] = []
    for id in ids {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(id)")!
        components.queryItems = [
            .init(name: "fields", value: "id,name,mimeType,modifiedTime"),
            .init(name: "supportsAllDrives", value: "true"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let (data, response) = try? await urlSession.data(for: request),
           (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0),
           let meta = try? JSONDecoder().decode(DriveFileMeta.self, from: data) {
            files.append(PickedFile(id: meta.id, name: meta.name,
                                    mimeType: meta.mimeType, modifiedTime: meta.modifiedTime))
        } else {
            files.append(PickedFile(id: id, name: nil, mimeType: nil, modifiedTime: nil))
        }
    }
    return files
}

private struct DriveFileMeta: Decodable {
    let id: String
    let name: String?
    let mimeType: String?
    let modifiedTime: String?
}

/// POSTs the enriched picked files to the `drive-import` edge function — the
/// unchanged `{projectId, files[]}` contract. `jwt` is the caller's Supabase user
/// access token (verified server-side by `auth.getUser`). Throws on any non-2xx.
func registerDriveImports(projectID: UUID, files: [PickedFile], jwt: String,
                          urlSession: URLSession = .shared) async throws {
    let url = SupabaseConfig.functionsBase.appendingPathComponent("drive-import")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(DriveImportBody(projectId: projectID.uuidString, files: files))

    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let detail = String(data: data, encoding: .utf8) ?? "(no body)"
        throw GoogleAuthError.serverSyncFailed(detail)
    }
}

private struct DriveImportBody: Encodable {
    let projectId: String
    let files: [PickedFile]
}

// MARK: - Picker redirect listener

/// A one-shot local HTTP listener that captures the onepick `?picked_file_ids=…&state=…`
/// redirect after the Vercel bounce forwards it to the loopback interface. A focused
/// sibling of `LoopbackRedirectListener` (the proven OAuth listener) kept separate so
/// that battle-tested code stays untouched — the ~40 duplicated lines are intentional
/// (see CLAUDE.md §3). Binds an ephemeral loopback port; `start()` returns it so the
/// caller can build `state = "<port>.<nonce>"` for the bounce page to split apart.
final class PickerRedirectListener {

    private var listener: NWListener?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var idsContinuation: CheckedContinuation<[String], Error>?
    private var expectedState = ""
    private let queue = DispatchQueue(label: "com.atlas.drive.onepick")

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

    /// Resolves with the picked file ids once the browser hits the loopback. Times
    /// out (default 5 min) so an abandoned browser tab never leaks the continuation.
    func waitForPickedFileIDs(expectedState: String, timeout: TimeInterval = 300) async throws -> [String] {
        self.expectedState = expectedState
        return try await withCheckedThrowingContinuation { continuation in
            self.idsContinuation = continuation
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(DriveOnePickError.timedOut))
            }
        }
    }

    /// Cancels a pending wait (user hit Cancel) and tears down the listener.
    func stop() {
        finish(.failure(DriveOnePickError.cancelled))
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
        // Request line: "GET /?picked_file_ids=…&state=… HTTP/1.1"
        let firstLine = request.components(separatedBy: "\r\n").first ?? request
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(connection, ok: false)
            finish(.failure(GoogleAuthError.authorizationFailed("Malformed redirect.")))
            return
        }

        let target = String(parts[1])
        var components = URLComponents()
        if let questionMark = target.firstIndex(of: "?") {
            components.percentEncodedQuery = String(target[target.index(after: questionMark)...])
        }
        let items = components.queryItems ?? []
        let returnedState = items.first { $0.name == "state" }?.value
        let idsValue = items.first { $0.name == "picked_file_ids" }?.value ?? ""

        if let error = items.first(where: { $0.name == "error" })?.value {
            respond(connection, ok: false)
            finish(.failure(GoogleAuthError.authorizationFailed(error)))
        } else if returnedState == expectedState {
            respond(connection, ok: true)
            let ids = idsValue.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            finish(.success(ids))
        } else {
            respond(connection, ok: false)
            finish(.failure(GoogleAuthError.stateMismatch))
        }
    }

    private func respond(_ connection: NWConnection, ok: Bool) {
        let title = ok ? "Files selected" : "Drive import failed"
        let message = ok
            ? "You can close this tab and return to Atlas."
            : "Something went wrong. Return to Atlas and try again."
        let html = """
        <html><head><meta charset="utf-8"><title>\(title)</title></head>\
        <body style="font-family:-apple-system,system-ui;background:#1a1714;color:#f0e9df;\
        text-align:center;padding-top:80px"><h2>\(title)</h2><p>\(message)</p></body></html>
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

    private func finish(_ result: Result<[String], Error>) {
        guard let continuation = idsContinuation else { return }
        idsContinuation = nil
        continuation.resume(with: result)
        listener?.cancel()
        listener = nil
    }
}
