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

    /// POST `SupabaseConfig.functionsBase/capture` with `{ text }`.
    /// Throws `AtlasAIError.notAuthenticated` if `session()` is nil.
    /// Throws `AtlasAIError.httpError` on non-2xx.
    /// Throws `AtlasAIError.decodingError` if the JSON doesn't match `CaptureResult`.
    func parse(_ text: String) async throws -> CaptureResult {
        guard let session = sessionProvider() else {
            throw AtlasAIError.notAuthenticated
        }

        let url = SupabaseConfig.functionsBase.appendingPathComponent("capture")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AtlasAIError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw AtlasAIError.httpError(http.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(CaptureResult.self, from: data)
        } catch {
            throw AtlasAIError.decodingError(error)
        }
    }
}
