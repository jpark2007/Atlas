import Foundation
import AtlasCore

// MARK: - Canvas API shapes

struct CanvasCourse: Decodable {
    let id: Int
    let name: String
    let courseCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseCode = "course_code"
    }
}

struct CanvasAssignment: Decodable {
    let id: Int
    let name: String
    let dueAt: String?
    let courseId: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dueAt    = "due_at"
        case courseId = "course_id"
    }
}

// MARK: - Service

/// Canvas LMS integration (per-user access token). Authenticates the user,
/// then fetches courses and assignments for syncing into AppState.
///
/// SECURITY NOTE: for production the token belongs server-side (a Supabase Edge
/// Function calling Canvas on the user's behalf), NOT in the client. This local
/// store is for internal testing of the connect flow only.
@MainActor
final class CanvasService: ObservableObject {

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(name: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published var host: String = UserDefaults.standard.string(forKey: hostKey) ?? ""

    private static let hostKey  = "atlas.canvas.host"
    /// Legacy UserDefaults key — read once for one-time migration into the Keychain.
    private static let tokenKey = "atlas.canvas.token"
    private static let keychainService = KeychainStore.Service.canvas
    private static let keychainAccount = "token"

    var isConnected: Bool { if case .connected = status { return true }; return false }

    /// Called after a successful connect so the app can trigger a sync.
    var onConnected: (() -> Void)?

    init() {
        if let token = Self.loadToken(), !host.isEmpty {
            Task { await validate(token: token) }
        }
    }

    /// The Canvas token from the Keychain, migrating a pre-Keychain UserDefaults
    /// value on first read after update (adopt into Keychain, delete from
    /// UserDefaults) so an existing connection isn't dropped.
    private static func loadToken() -> String? {
        if let data = KeychainStore.load(service: keychainService, account: keychainAccount),
           let token = String(data: data, encoding: .utf8), !token.isEmpty {
            return token
        }
        guard let legacy = UserDefaults.standard.string(forKey: tokenKey), !legacy.isEmpty else {
            return nil
        }
        KeychainStore.save(Data(legacy.utf8), service: keychainService, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        return legacy
    }

    // MARK: Auth

    func connect(host rawHost: String, token: String) async {
        let cleanedHost = rawHost
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        host = cleanedHost
        UserDefaults.standard.set(cleanedHost, forKey: Self.hostKey)
        await validate(token: token, persist: true)
    }

    func disconnect() {
        KeychainStore.delete(service: Self.keychainService, account: Self.keychainAccount)
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        status = .disconnected
    }

    // MARK: Fetch

    /// All active enrollments for the authenticated user.
    func fetchCourses() async throws -> [CanvasCourse] {
        let token = try storedToken()
        var components = URLComponents(string: "https://\(host)/api/v1/courses")!
        components.queryItems = [
            .init(name: "enrollment_state", value: "active"),
            .init(name: "per_page", value: "100"),
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkOK(response, data)
        return try JSONDecoder().decode([CanvasCourse].self, from: data)
    }

    /// All assignments for a single course, ordered by due date.
    func fetchAssignments(courseId: Int) async throws -> [CanvasAssignment] {
        let token = try storedToken()
        var components = URLComponents(string: "https://\(host)/api/v1/courses/\(courseId)/assignments")!
        components.queryItems = [
            .init(name: "per_page",  value: "100"),
            .init(name: "order_by",  value: "due_at"),
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkOK(response, data)
        return try JSONDecoder().decode([CanvasAssignment].self, from: data)
    }

    // MARK: Private

    private func validate(token: String, persist: Bool = false) async {
        guard !host.isEmpty, !token.isEmpty,
              let url = URL(string: "https://\(host)/api/v1/users/self") else {
            status = .failed("Enter your Canvas host (e.g. school.instructure.com).")
            return
        }
        status = .connecting
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                status = .failed("Invalid token or host.")
                return
            }
            let name = (json["name"] as? String) ?? "Canvas user"
            if persist {
                KeychainStore.save(Data(token.utf8), service: Self.keychainService, account: Self.keychainAccount)
            }
            status = .connected(name: name)
            onConnected?()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func storedToken() throws -> String {
        guard let token = Self.loadToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        return token
    }

    private static func checkOK(_ response: URLResponse, _ data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw URLError(.badServerResponse)
        }
    }
}
