import Foundation

/// Canvas LMS integration (per-user access token). Internal scaffold: stores the
/// token + school host locally and can validate it against the Canvas API.
///
/// SECURITY NOTE: for production the token belongs server-side (a Supabase Edge
/// Function calling Canvas on the user's behalf), NOT in the client. This local
/// store is for internal testing of the connect flow only.
@MainActor
public final class CanvasService: ObservableObject {

    public enum Status: Equatable {
        case disconnected
        case connecting
        case connected(name: String)
        case failed(String)
    }

    @Published public private(set) var status: Status = .disconnected
    @Published public var host: String = UserDefaults.standard.string(forKey: hostKey) ?? ""

    private static let hostKey = "atlas.canvas.host"
    private static let tokenKey = "atlas.canvas.token"

    public var isConnected: Bool { if case .connected = status { return true }; return false }

    public init() {
        if UserDefaults.standard.string(forKey: Self.tokenKey) != nil, !host.isEmpty {
            Task { await validate(token: UserDefaults.standard.string(forKey: Self.tokenKey) ?? "") }
        }
    }

    /// Validate a token against `https://<host>/api/v1/users/self` and persist on success.
    public func connect(host rawHost: String, token: String) async {
        let cleanedHost = rawHost
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        host = cleanedHost
        UserDefaults.standard.set(cleanedHost, forKey: Self.hostKey)
        await validate(token: token, persist: true)
    }

    public func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        status = .disconnected
    }

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
            if persist { UserDefaults.standard.set(token, forKey: Self.tokenKey) }
            status = .connected(name: name)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
