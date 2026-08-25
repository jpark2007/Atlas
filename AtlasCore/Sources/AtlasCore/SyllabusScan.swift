import Foundation

// MARK: - Request payload

/// One page handed to the scan: raw image bytes, base64-encoded for the JSON body.
/// The endpoint is IMAGES ONLY — a PDF must be rasterized page-by-page before it
/// gets here (the server rejects `application/pdf` outright).
public struct SyllabusScanImage: Codable, Equatable {
    public let data: String        // base64
    public let mediaType: String   // "image/png", "image/jpeg", …

    /// Wrap already-encoded base64 (e.g. read back from a cache).
    public init(base64: String, mediaType: String) {
        self.data = base64
        self.mediaType = mediaType
    }

    /// Wrap raw image bytes.
    public init(bytes: Data, mediaType: String) {
        self.data = bytes.base64EncodedString()
        self.mediaType = mediaType
    }

    /// Decoded byte count of this page, derived from the base64 length (no decode).
    public var byteCount: Int {
        let clean = data.filter { !$0.isWhitespace }
        guard !clean.isEmpty else { return 0 }
        let padding = clean.hasSuffix("==") ? 2 : (clean.hasSuffix("=") ? 1 : 0)
        return (clean.count * 3) / 4 - padding
    }
}

/// Request body for the `syllabus-scan` function. Term dates are plain
/// `YYYY-MM-DD` day strings (a term boundary is a school day, not an instant) and
/// are omitted when the caller has no term window; the model then only uses dates
/// the document states outright.
public struct SyllabusScanRequest: Codable, Equatable {
    public let images: [SyllabusScanImage]
    public let termStart: String?
    public let termEnd: String?
    public let timezone: String?
}

// MARK: - Response payload

/// One draft assignment / exam the scan found. `dueISO` / `startISO` are absent
/// when the syllabus's reference ("Week 3") couldn't be grounded — the item is
/// still kept so the review list can offer it with a blank date.
public struct SyllabusScanItem: Codable, Equatable {
    public let kind: String       // "task" | "event"
    public let title: String
    public let dueISO: String?
    public let startISO: String?
    public let notes: String?
}

/// One class the scan found, with everything it detected about it. Everything is
/// a DRAFT: nothing is written until the user accepts it in the review list.
public struct SyllabusScanClass: Codable, Equatable {
    public let code: String?
    public let name: String?
    public let meetingPattern: [MeetingBlock]?
    public let classInfo: ClassInfoCard?
    public let items: [SyllabusScanItem]

    enum CodingKeys: String, CodingKey { case code, name, meetingPattern, classInfo, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code           = try c.decodeIfPresent(String.self, forKey: .code)
        name           = try c.decodeIfPresent(String.self, forKey: .name)
        meetingPattern = try c.decodeIfPresent([MeetingBlock].self, forKey: .meetingPattern)
        classInfo      = try c.decodeIfPresent(ClassInfoCard.self, forKey: .classInfo)
        // A class with no work listed omits/empties `items` — never a decode failure.
        items          = try c.decodeIfPresent([SyllabusScanItem].self, forKey: .items) ?? []
    }
}

/// The scan result: classes to review, plus whether the server capped an
/// unreasonably large extraction (drives an "showing the first N" notice).
public struct SyllabusScanResponse: Codable, Equatable {
    public let classes: [SyllabusScanClass]
    public let truncated: Bool

    enum CodingKeys: String, CodingKey { case classes, truncated }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        classes   = try c.decodeIfPresent([SyllabusScanClass].self, forKey: .classes) ?? []
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }
}

// MARK: - Client

/// Thin async wrapper around the `syllabus-scan` Supabase Edge Function, built on
/// the same URLSession pattern as `AtlasAI` (anon `apikey` + bearer session token)
/// and reusing `AtlasAIError` for status mapping.
///
/// The function COMMITS NOTHING — it returns a draft. Committing accepted rows is
/// the caller's job, per the Phase 1 draft → review → commit rule.
public final class SyllabusScan {

    /// Page cap and total decoded-size cap, mirroring the server's 413s so an
    /// oversized scan fails locally instead of uploading 40 MB to be rejected.
    public static let maxImages = 10
    public static let maxTotalBytes = 15 * 1024 * 1024

    private let sessionProvider: () -> SupabaseSession?
    private let urlSession: URLSession

    public init(session: @escaping () -> SupabaseSession?,
                urlSession: URLSession = .shared) {
        self.sessionProvider = session
        self.urlSession = urlSession
    }

    /// POST `SupabaseConfig.functionsBase/syllabus-scan` with the pages and the
    /// term window, returning the draft classes for the review list.
    /// Throws `AtlasAIError.notAuthenticated` when there's no session,
    /// `.imagesTooLarge` when the pages bust the local caps, a typed
    /// `AtlasAIError` on non-2xx, and `.parseFailed` on undecodable JSON.
    /// Connectivity failures throw `URLError` unchanged.
    public func scan(images: [SyllabusScanImage],
                     termStart: Date? = nil,
                     termEnd: Date? = nil,
                     timeZone: TimeZone = .current) async throws -> SyllabusScanResponse {
        guard let session = sessionProvider() else {
            throw AtlasAIError.notAuthenticated
        }
        try SyllabusScan.validate(images)

        let url = SupabaseConfig.functionsBase.appendingPathComponent("syllabus-scan")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try SyllabusScan.requestBody(
            images: images,
            termStart: termStart.map { SyllabusScan.dayString($0, timeZone: timeZone) },
            termEnd: termEnd.map { SyllabusScan.dayString($0, timeZone: timeZone) },
            timezone: timeZone.identifier
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AtlasAIError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AtlasAIError.from(status: http.statusCode,
                                    body: String(data: data, encoding: .utf8) ?? "(empty)")
        }
        do {
            return try SyllabusScan.decode(from: data)
        } catch {
            throw AtlasAIError.parseFailed
        }
    }

    // MARK: - Testable seams (pure functions — no network)

    /// Enforce the page and total-size caps before spending an upload.
    public static func validate(_ images: [SyllabusScanImage]) throws {
        guard !images.isEmpty else { throw AtlasAIError.noImages }
        guard images.count <= maxImages else { throw AtlasAIError.imagesTooLarge }
        guard totalBytes(images) <= maxTotalBytes else { throw AtlasAIError.imagesTooLarge }
    }

    /// Decoded byte total across the pages (what the size cap measures).
    public static func totalBytes(_ images: [SyllabusScanImage]) -> Int {
        images.reduce(0) { $0 + $1.byteCount }
    }

    /// A term boundary as the server's `YYYY-MM-DD` day string, read in the
    /// user's zone so a late-evening `Date` doesn't roll to the next day.
    public static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Encode the POST body. Term fields are dropped when nil so a caller without
    /// a term window sends `{ "images": [...], "timezone": ... }`.
    public static func requestBody(images: [SyllabusScanImage],
                                   termStart: String?,
                                   termEnd: String?,
                                   timezone: String?) throws -> Data {
        try JSONEncoder().encode(SyllabusScanRequest(images: images,
                                                     termStart: termStart,
                                                     termEnd: termEnd,
                                                     timezone: timezone))
    }

    /// Decode the function response. Sparse payloads (`{}`, a class with only a
    /// name, a missing `truncated`) decode to sensible empties rather than throwing.
    public static func decode(from data: Data) throws -> SyllabusScanResponse {
        try JSONDecoder().decode(SyllabusScanResponse.self, from: data)
    }
}
