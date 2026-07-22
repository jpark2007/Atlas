import Foundation

// MARK: - Response model

/// Decoded payload from the `capture` Edge Function.
/// ISO date strings are left as `String` — the call site parses them when
/// constructing domain objects so we never force a date strategy on this decoder.
public struct CaptureResult: Codable {
    public let kind: String          // "task" | "event" | "note"
    public let title: String
    public let spaceName: String
    public let projectName: String?
    public let dueISO: String?
    public let startISO: String?
    public let endISO: String?
    public let durationMin: Int?
    public let isAllDay: Bool?
    public let notes: String?
}

// MARK: - Context payload

/// A single project inside a context space — name plus the routing hints the
/// model uses to place an ambiguous capture: an optional short code and an
/// optional SHORT description (the project's overview, truncated). The richer
/// the description, the more confidently the AI routes.
public struct CaptureContextProject: Codable, Equatable {
    public let name: String
    public let code: String?
    public let overview: String?
}

/// One of the user's real Spaces + its projects (with descriptions), sent to the
/// edge function so the model routes each captured item into an actual bucket
/// (instead of the generic School/Work/Personal default list).
public struct CaptureContextSpace: Codable, Equatable {
    public let name: String
    public let projects: [CaptureContextProject]
}

/// Request body for the `capture` function. `spaces` is omitted entirely when
/// the caller has no context to share, keeping old/default routing intact.
/// `timezone` (IANA identifier) lets the model resolve times in the user's
/// local day; omitted when nil so old deploys keep working.
/// `Codable` (not just `Encodable`) so tests can round-trip the produced body.
public struct CaptureRequest: Codable {
    public let text: String
    public let spaces: [CaptureContextSpace]?
    public let timezone: String?
}

// MARK: - Error

public enum AtlasAIError: LocalizedError {
    case notAuthenticated
    case httpError(Int, String)
    case decodingError(Error)

    public var errorDescription: String? {
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
public final class AtlasAI {

    private let sessionProvider: () -> SupabaseSession?
    private let urlSession: URLSession

    public init(session: @escaping () -> SupabaseSession?,
         urlSession: URLSession = .shared) {
        self.sessionProvider = session
        self.urlSession = urlSession
    }

    /// POST `SupabaseConfig.functionsBase/capture` with `{ text, spaces? }`.
    /// Returns an ARRAY of results (a multi-item paragraph splits into several).
    /// Throws `AtlasAIError.notAuthenticated` if `session()` is nil.
    /// Throws `AtlasAIError.httpError` on non-2xx.
    /// Throws `AtlasAIError.decodingError` if the JSON can't be decoded.
    public func parse(_ text: String,
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
        request.httpBody = try AtlasAI.requestBody(text: text, spaces: spaces,
                                                   timezone: TimeZone.current.identifier)

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
    /// Each project carries its name, optional code, and a SHORT description
    /// (overview truncated via `shortOverview`) so routing has real context.
    public static func context(from spaces: [Space]) -> [CaptureContextSpace] {
        spaces.map { space in
            CaptureContextSpace(
                name: space.name,
                projects: space.projects.map { p in
                    let trimmedCode = p.code?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return CaptureContextProject(
                        name: p.name,
                        code: (trimmedCode?.isEmpty == false) ? trimmedCode : nil,
                        overview: shortOverview(p.overview)
                    )
                }
            )
        }
    }

    /// Trim and truncate an overview to ~`limit` chars for the routing payload.
    /// Returns `nil` for blank input so the key is omitted entirely. When longer
    /// than `limit`, keeps the first `limit` characters and appends an ellipsis.
    public static func shortOverview(_ text: String, limit: Int = 160) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }

    /// Encode the POST body. `spaces` is dropped when empty and `timezone` when
    /// nil, so callers without context produce `{ "text": ... }` exactly as before.
    public static func requestBody(text: String,
                                   spaces: [CaptureContextSpace],
                                   timezone: String? = nil) throws -> Data {
        let payload = CaptureRequest(text: text,
                                     spaces: spaces.isEmpty ? nil : spaces,
                                     timezone: timezone)
        return try JSONEncoder().encode(payload)
    }

    /// Decode the function response. Tolerant of three shapes so a stale deploy
    /// (single object) still works:
    ///   1. `[ {...}, {...} ]`           → as-is
    ///   2. `{ ...one capture object }`  → wrapped as `[ {...} ]`
    public static func decodeResults(from data: Data) throws -> [CaptureResult] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([CaptureResult].self, from: data) {
            return array
        }
        // Fall back to a single object (old deploys returned one).
        let single = try decoder.decode(CaptureResult.self, from: data)
        return [single]
    }
}
