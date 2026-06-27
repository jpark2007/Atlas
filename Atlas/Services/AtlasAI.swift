import Foundation

// MARK: - Response model

/// Decoded payload from the `capture` Edge Function.
/// ISO date strings are left as `String` — the call site parses them when
/// constructing domain objects so we never force a date strategy on this decoder.
struct CaptureResult: Codable {
    let kind: String          // "task" | "event" | "note"
    let title: String
    let spaceName: String
    let projectName: String?
    let dueISO: String?
    let startISO: String?
    let durationMin: Int?
    let notes: String?
}

// MARK: - Context payload

/// One of the user's real Spaces + its project names, sent to the edge function
/// so the model routes each captured item into an actual bucket (instead of the
/// generic School/Work/Personal default list).
struct CaptureContextSpace: Codable, Equatable {
    let name: String
    let projects: [String]
}

/// Request body for the `capture` function. `spaces` is omitted entirely when
/// the caller has no context to share, keeping old/default routing intact.
/// `Codable` (not just `Encodable`) so tests can round-trip the produced body.
struct CaptureRequest: Codable {
    let text: String
    let spaces: [CaptureContextSpace]?
}

// MARK: - Error

enum AtlasAIError: LocalizedError {
    case notAuthenticated
    case httpError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No active session — cannot call the capture function."
        case .httpError(let code, let body):
            return "Edge function returned HTTP \(code): \(body)"
        case .decodingError(let underlying):
            return "Could not decode AI response: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Client

/// Thin async wrapper around the `capture` Supabase Edge Function.
/// Mirrors the `SupabaseAuth.request(...)` URLSession pattern:
///   - `apikey` header = anon key
///   - `Authorization: Bearer <accessToken>`
///   - `Content-Type: application/json`
///
/// Decodes the response with a plain `JSONDecoder` (no date strategy —
/// ISO strings stay as strings for the call site to parse).
final class AtlasAI {

    private let sessionProvider: () -> SupabaseSession?
    private let urlSession: URLSession

    init(session: @escaping () -> SupabaseSession?,
         urlSession: URLSession = .shared) {
        self.sessionProvider = session
        self.urlSession = urlSession
    }

    /// POST `SupabaseConfig.functionsBase/capture` with `{ text, spaces? }`.
    /// Returns an ARRAY of results (a multi-item paragraph splits into several).
    /// Throws `AtlasAIError.notAuthenticated` if `session()` is nil.
    /// Throws `AtlasAIError.httpError` on non-2xx.
    /// Throws `AtlasAIError.decodingError` if the JSON can't be decoded.
    func parse(_ text: String,
               spaces: [CaptureContextSpace] = []) async throws -> [CaptureResult] {
        guard let session = sessionProvider() else {
            throw AtlasAIError.notAuthenticated
        }

        let url = SupabaseConfig.functionsBase.appendingPathComponent("capture")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AtlasAI.requestBody(text: text, spaces: spaces)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AtlasAIError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw AtlasAIError.httpError(http.statusCode, body)
        }

        do {
            return try AtlasAI.decodeResults(from: data)
        } catch {
            throw AtlasAIError.decodingError(error)
        }
    }

    // MARK: - Testable seams (pure functions — no network)

    /// Map the user's live `Space` list into the lightweight context payload.
    static func context(from spaces: [Space]) -> [CaptureContextSpace] {
        spaces.map { space in
            CaptureContextSpace(name: space.name,
                                projects: space.projects.map { $0.name })
        }
    }

    /// Encode the POST body. `spaces` is dropped when empty so callers without
    /// context produce `{ "text": ... }` exactly as before.
    static func requestBody(text: String, spaces: [CaptureContextSpace]) throws -> Data {
        let payload = CaptureRequest(text: text,
                                     spaces: spaces.isEmpty ? nil : spaces)
        return try JSONEncoder().encode(payload)
    }

    /// Decode the function response. Tolerant of three shapes so a stale deploy
    /// (single object) still works:
    ///   1. `[ {...}, {...} ]`           → as-is
    ///   2. `{ ...one capture object }`  → wrapped as `[ {...} ]`
    static func decodeResults(from data: Data) throws -> [CaptureResult] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([CaptureResult].self, from: data) {
            return array
        }
        // Fall back to a single object (old deploys returned one).
        let single = try decoder.decode(CaptureResult.self, from: data)
        return [single]
    }
}
