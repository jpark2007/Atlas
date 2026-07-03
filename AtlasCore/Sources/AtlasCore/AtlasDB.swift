import Foundation
import SwiftUI

// MARK: - Errors

public enum AtlasDBError: LocalizedError {
    case notAuthenticated
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Sign in before accessing the database."
        case .requestFailed(let code, let msg):
            return "Database request failed (HTTP \(code)): \(msg)"
        }
    }
}

// MARK: - Color token helper (defined here, NOT in Models.swift)

/// Maps between a short string token and its `AtlasTheme.Colors` counterpart.
/// Only `spaces.color_token` is ever persisted. All other domain types receive
/// `AtlasTheme.Colors.accent` as a placeholder on `toDomain()`; Task 2
/// re-derives real colors from `spaceName` via `AppState.calendarSpaceColor(named:)`.
public enum ColorToken: String {
    case school, personal, side, accent

    public var color: Color {
        switch self {
        case .school:   return AtlasTheme.Colors.school
        case .personal: return AtlasTheme.Colors.personal
        case .side:     return AtlasTheme.Colors.side
        case .accent:   return AtlasTheme.Colors.accent
        }
    }

    /// Best-effort mapping: compare against known theme colors; defaults to "accent".
    public static func token(for color: Color) -> String {
        if color == AtlasTheme.Colors.school   { return "school" }
        if color == AtlasTheme.Colors.personal { return "personal" }
        if color == AtlasTheme.Colors.side     { return "side" }
        return "accent"
    }

    /// Returns the `Color` for a stored token string; defaults to accent.
    public static func color(for token: String) -> Color {
        ColorToken(rawValue: token)?.color ?? AtlasTheme.Colors.accent
    }
}

// MARK: - Shared ISO 8601 codecs

private let isoEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let isoDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - Snapshot

/// Flat snapshot of all persisted tables returned by `AtlasDB.loadAll()`.
/// `spaces` come back with `projects: []`; `projects` is a flat array carrying `spaceName`.
/// Re-nesting projects into spaces is Task 2's job — not done here.
///
/// All domain types now use `var id = UUID()` so their memberwise inits accept `id:`
/// as an overridable parameter. Each `toDomain()` call passes the row's UUID through,
/// so DB identity is fully preserved on load. `CalendarEvent` was already correct.
public struct AtlasSnapshot {
    public var spaces: [Space]
    public var projects: [Project]
    public var tasks: [TaskItem]
    public var events: [CalendarEvent]
    public var notes: [Note]
    public var goals: [Goal]
    /// Docs → Notes import: the per-project reference pool + its task/event joins.
    /// Defaulted so existing callers (seed, tests, mobile) are unchanged; only
    /// `loadAll()` populates them, and best-effort so a not-yet-migrated DB → [].
    public var references: [Reference]
    public var referenceAttachments: [ReferenceAttachment]

    public init(spaces: [Space], projects: [Project], tasks: [TaskItem], events: [CalendarEvent], notes: [Note], goals: [Goal], references: [Reference] = [], referenceAttachments: [ReferenceAttachment] = []) {
        self.spaces = spaces
        self.projects = projects
        self.tasks = tasks
        self.events = events
        self.notes = notes
        self.goals = goals
        self.references = references
        self.referenceAttachments = referenceAttachments
    }
}

// MARK: - DTO Row structs

// ─────────────────────────────────────────────────────────────────────────────
// SpaceRow
// ─────────────────────────────────────────────────────────────────────────────

public struct SpaceRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var name: String
    public var colorToken: String
    public var sort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId     = "user_id"
        case name
        case colorToken = "color_token"
        case sort
    }

    public init(domain s: Space, sort: Int = 0) {
        self.id         = s.id
        self.name       = s.name
        self.colorToken = ColorToken.token(for: s.color)
        self.sort       = sort
    }

    public func toDomain() -> Space {
        Space(id: id, name: name, color: ColorToken.color(for: colorToken), projects: [])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProjectRow
// ─────────────────────────────────────────────────────────────────────────────

public struct ProjectRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var spaceName: String
    public var name: String
    public var code: String?
    public var isClass: Bool
    public var meetingInfo: String?
    public var instructor: String?
    public var canvasSynced: Bool
    public var overview: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId       = "user_id"
        case spaceName    = "space_name"
        case name
        case code
        case isClass      = "is_class"
        case meetingInfo  = "meeting_info"
        case instructor
        case canvasSynced = "canvas_synced"
        case overview
    }

    public init(domain p: Project) {
        self.id           = p.id
        self.spaceName    = p.spaceName
        self.name         = p.name
        self.code         = p.code
        self.isClass      = p.isClass
        self.meetingInfo  = p.meetingInfo
        self.instructor   = p.instructor
        self.canvasSynced = p.canvasSynced
        self.overview     = p.overview
    }

    public func toDomain() -> Project {
        // Nested display arrays (assignments, notes, pinned, backlinks) are NOT persisted;
        // toDomain() returns them as []. Task 2 re-nests projects into spaces via spaceName.
        Project(id: id, name: name, code: code, isClass: isClass,
                spaceName: spaceName,
                spaceColor: AtlasTheme.Colors.accent, // Task 2 re-derives from spaceName
                meetingInfo: meetingInfo, instructor: instructor,
                canvasSynced: canvasSynced, overview: overview)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// TaskRow
// ─────────────────────────────────────────────────────────────────────────────

public struct TaskRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var projectId: UUID?
    public var spaceName: String
    public var title: String
    public var dueDate: Date?
    public var status: String        // persisted as text — see encode/decode helpers below
    public var done: Bool
    public var scheduledAt: Date?
    public var notes: String?
    public var noteId: UUID?
    public var durationMin: Int?
    public var workBlockGoogleEventId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case projectId   = "project_id"
        case spaceName   = "space_name"
        case title
        case dueDate     = "due_date"
        case status
        case done
        case scheduledAt = "scheduled_at"
        case notes
        case noteId      = "note_id"
        case durationMin = "duration_min"
        case workBlockGoogleEventId = "work_block_google_event_id"
    }

    public init(domain t: TaskItem) {
        self.id          = t.id
        self.projectId   = nil // no projectId on TaskItem yet; map to nil
        self.spaceName   = t.spaceName
        self.title       = t.title
        self.dueDate     = t.dueDate
        self.status      = TaskRow.encode(status: t.status)
        self.done        = t.done
        self.scheduledAt = t.scheduledAt
        self.notes       = t.notes
        self.noteId      = t.noteID
        self.durationMin = t.durationMin
        self.workBlockGoogleEventId = t.workBlockGoogleEventId
    }

    public func toDomain() -> TaskItem {
        TaskItem(id: id,
                 title: title,
                 dueLabel: TaskItem.dueLabel(for: dueDate),
                 status: TaskRow.decode(status: status),
                 done: done,
                 scheduledAt: scheduledAt,
                 dueDate: dueDate,
                 durationMin: durationMin,
                 noteID: noteId,
                 workBlockGoogleEventId: workBlockGoogleEventId,
                 spaceName: spaceName,
                 notes: notes ?? "")
    }

    // MARK: TaskStatus ↔ status text (explicit switch — enum has NO raw values)

    public static func encode(status: TaskStatus) -> String {
        switch status {
        case .open:      return "open"
        case .dueSoon:   return "due_soon"
        case .upcoming:  return "upcoming"
        case .submitted: return "submitted"
        }
    }

    public static func decode(status: String) -> TaskStatus {
        switch status {
        case "open":      return .open
        case "due_soon":  return .dueSoon
        case "upcoming":  return .upcoming
        case "submitted": return .submitted
        default:          return .open
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// EventRow
// ─────────────────────────────────────────────────────────────────────────────

public struct EventRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var spaceName: String
    public var title: String
    public var subtitle: String
    public var startAt: Date
    public var endAt: Date
    // TODO Task 5: map notes/isAllDay/projectID once added to CalendarEvent
    public var notes: String?
    public var isAllDay: Bool
    public var projectId: UUID?
    public var googleEventId: String?
    public var noteId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case spaceName = "space_name"
        case title
        case subtitle
        case startAt   = "start_at"
        case endAt     = "end_at"
        case notes
        case isAllDay  = "is_all_day"
        case projectId = "project_id"
        case googleEventId = "google_event_id"
        case noteId    = "note_id"
    }

    public init(domain e: CalendarEvent) {
        self.id        = e.id
        self.spaceName = e.spaceName
        self.title     = e.title
        self.subtitle  = e.subtitle
        self.startAt   = e.start
        self.endAt     = e.end
        self.notes     = e.notes
        self.isAllDay  = e.isAllDay
        self.projectId = e.projectID
        self.googleEventId = e.googleEventId
        self.noteId    = e.noteID
    }

    public func toDomain() -> CalendarEvent {
        // CalendarEvent has `var id: UUID = UUID()` — memberwise init exposes `id`
        // as an overridable parameter, so the DB UUID IS preserved here.
        CalendarEvent(id: id,
                      title: title,
                      subtitle: subtitle,
                      start: startAt,
                      end: endAt,
                      color: AtlasTheme.Colors.accent, // Task 2 re-derives from spaceName
                      spaceName: spaceName,
                      notes: notes,
                      isAllDay: isAllDay,
                      projectID: projectId,
                      noteID: noteId,
                      // A row carrying a Google id came from Google — derive, never default.
                      // Caveat: an Atlas-origin event mirrored TO Google also carries a
                      // googleEventId, so it loads as .google (accepted trade-off; only
                      // affects Mac reap eligibility for that edge, the fail-safe direction).
                      source: googleEventId != nil ? .google : .atlas,
                      googleEventId: googleEventId)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// NoteRow
// ─────────────────────────────────────────────────────────────────────────────

public struct NoteRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var spaceName: String?
    public var projectId: UUID?
    public var title: String
    public var body: String
    public var updatedAt: Date
    public var isExternal: Bool
    public var googleDocId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case spaceName   = "space_name"
        case projectId   = "project_id"
        case title
        case body
        case updatedAt   = "updated_at"
        case isExternal  = "is_external"
        case googleDocId = "google_doc_id"
    }

    public init(domain n: Note) {
        self.id          = n.id
        self.spaceName   = n.spaceName
        self.projectId   = n.projectID
        self.title       = n.title
        self.body        = n.body
        self.updatedAt   = n.updatedAt
        self.isExternal  = n.isExternal
        self.googleDocId = n.googleDocId
    }

    public func toDomain() -> Note {
        Note(id: id, title: title, body: body,
             spaceName: spaceName, projectID: projectId,
             updatedAt: updatedAt, isExternal: isExternal,
             googleDocId: googleDocId)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReferenceRow — the per-project reference pool (Docs → Notes import)
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `project_references` (migration `0013`). Table is `project_references`,
/// not `references`, because REFERENCES is a reserved SQL keyword.
///
/// `modifiedTime` / `lastSyncedAt` are decoded as `String` (not `Date`) because the
/// sync cron writes them from Drive / `now()` with fractional-second precision the
/// shared `.iso8601` decoder can't parse — same reason `GoogleConnectionRow` keeps
/// `lastSyncedAt` as a String. `toDomain()` parses them leniently.
public struct ReferenceRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var projectId: UUID
    public var kind: String
    public var title: String
    public var url: String?
    public var driveFileId: String?
    public var mimeType: String?
    public var modifiedTime: String?
    public var lastSyncedAt: String?
    public var syncState: String
    public var noteId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId       = "user_id"
        case projectId    = "project_id"
        case kind
        case title
        case url
        case driveFileId  = "drive_file_id"
        case mimeType     = "mime_type"
        case modifiedTime = "modified_time"
        case lastSyncedAt = "last_synced_at"
        case syncState    = "sync_state"
        case noteId       = "note_id"
    }

    public init(domain r: Reference) {
        self.id           = r.id
        self.projectId    = r.projectID
        self.kind         = r.kind.rawValue
        self.title        = r.title
        self.url          = r.url
        self.driveFileId  = r.driveFileId
        self.mimeType     = r.mimeType
        self.modifiedTime = ReferenceRow.isoString(from: r.modifiedTime)
        self.lastSyncedAt = ReferenceRow.isoString(from: r.lastSyncedAt)
        self.syncState    = r.syncState.rawValue
        self.noteId       = r.noteID
    }

    public func toDomain() -> Reference {
        Reference(id: id,
                  projectID: projectId,
                  kind: ReferenceKind(rawValue: kind) ?? .file,
                  title: title,
                  url: url,
                  driveFileId: driveFileId,
                  mimeType: mimeType,
                  modifiedTime: ReferenceRow.date(from: modifiedTime),
                  lastSyncedAt: ReferenceRow.date(from: lastSyncedAt),
                  syncState: ReferenceSyncState(rawValue: syncState) ?? .pending,
                  noteID: noteId)
    }

    /// Parses an ISO-8601 timestamp with or without fractional seconds — mirrors
    /// `GoogleConnectionRow.lastSyncedDate` so server-written (microsecond) times decode.
    static func date(from s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Formats a `Date` as an ISO-8601 string (fractional seconds) for write-back.
    static func isoString(from d: Date?) -> String? {
        guard let d else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReferenceAttachmentRow — reference ⇄ task / event join
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `reference_attachments` (migration `0013`). Exactly one of
/// `taskId` / `eventId` is set (enforced by a DB check).
public struct ReferenceAttachmentRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var referenceId: UUID
    public var taskId: UUID?
    public var eventId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case referenceId = "reference_id"
        case taskId      = "task_id"
        case eventId     = "event_id"
    }

    public init(domain a: ReferenceAttachment) {
        self.id          = a.id
        self.referenceId = a.referenceID
        self.taskId      = a.taskID
        self.eventId     = a.eventID
    }

    public func toDomain() -> ReferenceAttachment {
        ReferenceAttachment(id: id, referenceID: referenceId, taskID: taskId, eventID: eventId)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoalRow
// ─────────────────────────────────────────────────────────────────────────────

public struct GoalRow: Codable {
    public var id: UUID
    public var userId: UUID?
    public var title: String
    public var progress: Double
    public var label: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId   = "user_id"
        case title
        case progress
        case label
    }

    public init(domain g: Goal) {
        self.id       = g.id
        self.title    = g.title
        self.progress = g.progress
        self.label    = g.label
    }

    public func toDomain() -> Goal {
        Goal(id: id, title: title, progress: progress, label: label)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoogleConnectionRow — server-owned Google sync state (read-only for the client)
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `google_connections` (migration `0006`). Present only when the user
/// has enabled cloud sync. The client may read only the owner-granted columns —
/// `vault_secret_id` is intentionally NOT granted, so a `select=*` would 403;
/// `loadGoogleConnection()` selects explicit columns instead.
///
/// `lastSyncedAt` is decoded as a String because the server writes it with `now()`
/// (microsecond precision) which the app's plain `.iso8601` decoder can't parse;
/// `lastSyncedDate` parses it leniently for the UI.
public struct GoogleConnectionRow: Codable {
    public var status: String            // active | error | revoked
    public var lastSyncedAt: String?
    public var lastError: String?
    public var calendarId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case lastSyncedAt = "last_synced_at"
        case lastError    = "last_error"
        case calendarId   = "calendar_id"
    }

    /// The server owns Google↔DB sync whenever a connection exists and hasn't been
    /// revoked. `error` still counts as server-owned: the server holds the credential
    /// and keeps retrying, so the Mac must stay stood down (single-owner invariant).
    /// Only `revoked` (deliberate disconnect or `invalid_grant`) hands Google back to
    /// the Mac's local sync.
    public var isServerOwned: Bool { status != "revoked" }

    /// `lastSyncedAt` parsed leniently (with or without fractional seconds).
    public var lastSyncedDate: Date? {
        guard let s = lastSyncedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CanvasConnectionRow — server-owned Canvas ICS sync state (read-only for the client)
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `canvas_connections` (migration `0012`). Present only when the user
/// has connected a Canvas feed. The client may read only the owner-granted columns —
/// `vault_secret_id` (the feed-URL pointer) is intentionally NOT granted, so a
/// `select=*` would 403; `loadCanvasConnection()` selects explicit columns instead.
///
/// Mirrors `GoogleConnectionRow`. `lastSyncedAt` is a String because the server writes
/// it with microsecond precision the plain `.iso8601` decoder can't parse;
/// `lastSyncedDate` parses it leniently for the UI.
public struct CanvasConnectionRow: Codable {
    public var status: String            // active | error | revoked
    public var lastSyncedAt: String?
    public var lastError: String?
    public var spaceName: String?        // Atlas space unmatched Canvas items land in

    enum CodingKeys: String, CodingKey {
        case status
        case lastSyncedAt = "last_synced_at"
        case lastError    = "last_error"
        case spaceName    = "space_name"
    }

    /// The server owns Canvas→DB sync whenever a connection exists and hasn't been
    /// revoked. `error` still counts as server-owned (the server keeps retrying); only
    /// `revoked` (a reset feed URL needing a re-paste) hands nothing back — the client
    /// shows the paste form again. Mirrors `GoogleConnectionRow.isServerOwned`.
    public var isServerOwned: Bool { status != "revoked" }

    /// `lastSyncedAt` parsed leniently (with or without fractional seconds).
    public var lastSyncedDate: Date? {
        guard let s = lastSyncedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - AtlasDB PostgREST Client

/// Thin async PostgREST client. All requests mirror the `SupabaseAuth.request(...)` pattern:
/// `apikey: SupabaseConfig.anonKey`, `Authorization: Bearer <accessToken>`, base URL
/// `SupabaseConfig.restBase`. RLS on the server scopes every query to `auth.uid()`.
///
/// If `session()` returns nil, every method throws `AtlasDBError.notAuthenticated`.
/// Callers guard offline mode externally; this client fails cleanly rather than crashing.
public final class AtlasDB {

    private let sessionProvider: () -> SupabaseSession?

    public init(session: @escaping () -> SupabaseSession?) {
        self.sessionProvider = session
    }

    // MARK: - Internal helpers

    private func requireSession() throws -> SupabaseSession {
        guard let s = sessionProvider() else {
            throw AtlasDBError.notAuthenticated
        }
        return s
    }

    /// GET `<restBase>/<table>?select=*&order=<column>` and decode the JSON array.
    /// Pass `order` to ensure stable, deterministic row ordering across launches.
    private func getAll<T: Decodable>(_ table: String, order: String? = nil) async throws -> [T] {
        let sess = try requireSession()
        var comps = URLComponents(
            url: SupabaseConfig.restBase.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "select", value: "*")]
        if let order = order {
            queryItems.append(URLQueryItem(name: "order", value: order))
        }
        comps.queryItems = queryItems

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey,               forHTTPHeaderField: "apikey")
        req.setValue("application/json",                   forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(sess.accessToken)",         forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try isoDecoder.decode([T].self, from: data)
    }

    /// GET `<restBase>/<table>?select=<columns>` and decode the JSON array. Used
    /// where a `select=*` would be rejected because RLS column-grants hide some
    /// columns (e.g. `google_connections.vault_secret_id`).
    private func getColumns<T: Decodable>(_ table: String, columns: String) async throws -> [T] {
        let sess = try requireSession()
        var comps = URLComponents(
            url: SupabaseConfig.restBase.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "select", value: columns)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey,       forHTTPHeaderField: "apikey")
        req.setValue("application/json",           forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(sess.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try isoDecoder.decode([T].self, from: data)
    }

    /// POST (upsert) or DELETE — no response body expected (`return=minimal`).
    private func send(method: String,
                      table: String,
                      query: [URLQueryItem] = [],
                      extraHeaders: [String: String] = [:],
                      body: Data? = nil,
                      sess: SupabaseSession) async throws {
        var comps = URLComponents(
            url: SupabaseConfig.restBase.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey,       forHTTPHeaderField: "apikey")
        req.setValue("application/json",           forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sess.accessToken)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AtlasDBError.requestFailed(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AtlasDBError.requestFailed(http.statusCode, msg)
        }
    }

    private let upsertQuery   = [URLQueryItem(name: "on_conflict", value: "id")]
    private let upsertHeaders = ["Prefer": "resolution=merge-duplicates,return=minimal"]

    // MARK: - Public API

    /// Load all tables for the signed-in user. RLS scopes rows automatically.
    /// Returns a flat `AtlasSnapshot`; spaces have `projects: []` — re-nesting is Task 2's job.
    public func loadAll() async throws -> AtlasSnapshot {
        // Stable ordering per table so sidebar/list order is deterministic across launches.
        async let spaceRows:   [SpaceRow]   = getAll("spaces",   order: "sort")
        async let projectRows: [ProjectRow] = getAll("projects", order: "id")
        async let taskRows:    [TaskRow]    = getAll("tasks",    order: "id")
        async let eventRows:   [EventRow]   = getAll("events",   order: "start_at")
        async let noteRows:    [NoteRow]    = getAll("notes",    order: "id")
        async let goalRows:    [GoalRow]    = getAll("goals",    order: "id")

        let (sr, pr, tr, er, nr, gr) = try await (spaceRows, projectRows, taskRows, eventRows, noteRows, goalRows)

        // References + attachments are best-effort: if the notes-import migration
        // (0013) isn't deployed yet, these tables 404 — degrade to [] rather than
        // failing the whole load (which would blank everything back to MockData).
        let refRows: [ReferenceRow] =
            (try? await getAll("project_references", order: "created_at.desc")) ?? []
        let attachRows: [ReferenceAttachmentRow] =
            (try? await getAll("reference_attachments", order: "created_at.desc")) ?? []

        return AtlasSnapshot(
            spaces:   sr.map { $0.toDomain() },
            projects: pr.map { $0.toDomain() },
            tasks:    tr.map { $0.toDomain() },
            events:   er.map { $0.toDomain() },
            notes:    nr.map { $0.toDomain() },
            goals:    gr.map { $0.toDomain() },
            references:           refRows.map    { $0.toDomain() },
            referenceAttachments: attachRows.map { $0.toDomain() }
        )
    }

    /// Reads the caller's `google_connections` row (server-owned Google sync state),
    /// or nil when the user has no cloud connection. Selects only the owner-granted
    /// columns; RLS scopes the query to the signed-in user.
    public func loadGoogleConnection() async throws -> GoogleConnectionRow? {
        let rows: [GoogleConnectionRow] = try await getColumns(
            "google_connections",
            columns: "status,last_synced_at,last_error,calendar_id")
        return rows.first
    }

    /// Reads the caller's `canvas_connections` row (server-owned Canvas sync state),
    /// or nil when the user has no Canvas connection. Selects only the owner-granted
    /// columns; RLS scopes the query to the signed-in user. Mirrors `loadGoogleConnection()`.
    public func loadCanvasConnection() async throws -> CanvasConnectionRow? {
        let rows: [CanvasConnectionRow] = try await getColumns(
            "canvas_connections",
            columns: "status,last_synced_at,last_error,space_name")
        return rows.first
    }

    /// Seed all tables from a snapshot (first-run). Upserts each row so it is safe
    /// to call if some rows already exist.
    public func seedInitial(_ snapshot: AtlasSnapshot) async throws {
        for (index, space) in snapshot.spaces.enumerated() { try await upsertSpace(space, sort: index) }
        for project in snapshot.projects { try await upsertProject(project) }
        for task    in snapshot.tasks    { try await upsertTask(task) }
        for event   in snapshot.events   { try await upsertEvent(event) }
        for note    in snapshot.notes    { try await upsertNote(note) }
        for goal    in snapshot.goals    { try await upsertGoal(goal) }
    }

    // MARK: Spaces / Projects

    public func upsertSpace(_ s: Space, sort: Int = 0) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = SpaceRow(domain: s, sort: sort)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "spaces",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func upsertProject(_ p: Project) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = ProjectRow(domain: p)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "projects",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    // MARK: Tasks

    public func upsertTask(_ t: TaskItem) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = TaskRow(domain: t)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "tasks",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteTask(id: UUID) async throws {
        let sess = try requireSession()
        try await send(method: "DELETE", table: "tasks",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    // MARK: Events

    public func upsertEvent(_ e: CalendarEvent) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = EventRow(domain: e)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "events",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteEvent(id: UUID) async throws {
        let sess = try requireSession()
        try await send(method: "DELETE", table: "events",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    // MARK: Notes / Goals

    public func upsertNote(_ n: Note) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = NoteRow(domain: n)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "notes",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func upsertGoal(_ g: Goal) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = GoalRow(domain: g)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "goals",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    // MARK: References (Docs → Notes import)

    public func upsertReference(_ r: Reference) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = ReferenceRow(domain: r)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "project_references",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteReference(id: UUID) async throws {
        let sess = try requireSession()
        try await send(method: "DELETE", table: "project_references",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    public func upsertReferenceAttachment(_ a: ReferenceAttachment) async throws {
        let sess = try requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = ReferenceAttachmentRow(domain: a)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "reference_attachments",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteReferenceAttachment(id: UUID) async throws {
        let sess = try requireSession()
        try await send(method: "DELETE", table: "reference_attachments",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    /// Reloads just the reference pool + its attachments — lets the client refresh
    /// after a browser-side Drive import without a full `loadAll()` / relaunch.
    /// Best-effort: if the notes-import migration (0013) isn't deployed the tables
    /// 404 and this returns empty rather than throwing.
    public func loadReferences() async throws -> (references: [Reference], attachments: [ReferenceAttachment]) {
        let refRows: [ReferenceRow] =
            (try? await getAll("project_references", order: "created_at.desc")) ?? []
        let attachRows: [ReferenceAttachmentRow] =
            (try? await getAll("reference_attachments", order: "created_at.desc")) ?? []
        return (refRows.map { $0.toDomain() }, attachRows.map { $0.toDomain() })
    }
}
