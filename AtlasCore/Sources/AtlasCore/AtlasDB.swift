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
///
/// Beyond the four named tokens the stored value may be a literal `"#RRGGBB"`
/// hex string (the custom-color picker). The columns are plain text end-to-end,
/// so a hex value round-trips unharmed; `color(for:)`/`token(for:)` resolve it.
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

    /// Best-effort mapping from a `Color` to a stored token. Named theme colors
    /// serialize to their token; anything else serializes to its `"#RRGGBB"` hex
    /// so custom colors persist. Falls back to "accent" only if hex extraction
    /// fails (impossible for the sRGB colors this app produces).
    public static func token(for color: Color) -> String {
        if color == AtlasTheme.Colors.school   { return "school" }
        if color == AtlasTheme.Colors.personal { return "personal" }
        if color == AtlasTheme.Colors.side     { return "side" }
        if color == AtlasTheme.Colors.accent   { return "accent" }
        return color.atlasHexString ?? "accent"
    }

    /// Returns the `Color` for a stored token string. A leading `#` (or any
    /// non-token value that scans as hex) resolves to that literal color; the
    /// four named tokens map to their theme color; everything else → accent.
    public static func color(for token: String) -> Color {
        if let named = ColorToken(rawValue: token) { return named.color }
        if token.hasPrefix("#") { return Color(hex: token) }
        return AtlasTheme.Colors.accent
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

    enum CodingKeys: String, CodingKey, CaseIterable {
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
// UserSettingsRow — synced per-user preferences (0025), a singleton row keyed by
// user_id. `notification_prefs` is jsonb server-side but travels as an opaque
// compact JSON *string* client-side (`notificationPrefsJSON`); PostgREST returns
// jsonb as a nested object, so that one field is bridged through `JSONValue`
// (decode: object → compact string; encode: string → raw object, not a quoted
// string). All other columns round-trip straight.
// ─────────────────────────────────────────────────────────────────────────────

/// A fully-general JSON value used only to bridge the `notification_prefs` jsonb
/// column to/from the compact string Atlas carries. Kept private to AtlasDB.
private enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {                             self = .null }
        else if let b = try? c.decode(Bool.self) {     self = .bool(b) }
        else if let n = try? c.decode(Double.self) {   self = .number(n) }
        else if let s = try? c.decode(String.self) {   self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value in notification_prefs"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Compact, key-sorted encoder so the derived `notificationPrefsJSON` string is
/// byte-stable (deterministic across launches and testable for equality).
private let compactJSONEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = .sortedKeys
    return e
}()

public struct UserSettingsRow: Codable, Equatable {
    public var userId: UUID
    public var defaultSpaceName: String?
    public var appleCalendarDefaultSpace: String?
    public var textScale: Double?
    public var sidebarMode: String?
    public var tasksGrouping: String?
    public var perTabDocsSync: Bool?
    /// Opaque compact JSON blob (same shape `NotificationPrefs` encodes); stored
    /// in the jsonb `notification_prefs` column. nil ⇒ column absent/NULL.
    public var notificationPrefsJSON: String?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId                    = "user_id"
        case defaultSpaceName          = "default_space_name"
        case appleCalendarDefaultSpace = "apple_calendar_default_space"
        case textScale                 = "text_scale"
        case sidebarMode               = "sidebar_mode"
        case tasksGrouping             = "tasks_grouping"
        case perTabDocsSync            = "per_tab_docs_sync"
        case notificationPrefs         = "notification_prefs"
        case updatedAt                 = "updated_at"
    }

    public init(userId: UUID,
                defaultSpaceName: String? = nil,
                appleCalendarDefaultSpace: String? = nil,
                textScale: Double? = nil,
                sidebarMode: String? = nil,
                tasksGrouping: String? = nil,
                perTabDocsSync: Bool? = nil,
                notificationPrefsJSON: String? = nil,
                updatedAt: Date? = nil) {
        self.userId                    = userId
        self.defaultSpaceName          = defaultSpaceName
        self.appleCalendarDefaultSpace = appleCalendarDefaultSpace
        self.textScale                 = textScale
        self.sidebarMode               = sidebarMode
        self.tasksGrouping             = tasksGrouping
        self.perTabDocsSync            = perTabDocsSync
        self.notificationPrefsJSON     = notificationPrefsJSON
        self.updatedAt                 = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId                    = try c.decode(UUID.self, forKey: .userId)
        defaultSpaceName          = try c.decodeIfPresent(String.self, forKey: .defaultSpaceName)
        appleCalendarDefaultSpace = try c.decodeIfPresent(String.self, forKey: .appleCalendarDefaultSpace)
        textScale                 = try c.decodeIfPresent(Double.self, forKey: .textScale)
        sidebarMode               = try c.decodeIfPresent(String.self, forKey: .sidebarMode)
        tasksGrouping             = try c.decodeIfPresent(String.self, forKey: .tasksGrouping)
        perTabDocsSync            = try c.decodeIfPresent(Bool.self,   forKey: .perTabDocsSync)
        updatedAt                 = try c.decodeIfPresent(Date.self,   forKey: .updatedAt)
        // jsonb object → compact string (nil when the column is absent or NULL).
        if let value = try c.decodeIfPresent(JSONValue.self, forKey: .notificationPrefs) {
            let data = try compactJSONEncoder.encode(value)
            notificationPrefsJSON = String(data: data, encoding: .utf8)
        } else {
            notificationPrefsJSON = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(defaultSpaceName,          forKey: .defaultSpaceName)
        try c.encodeIfPresent(appleCalendarDefaultSpace, forKey: .appleCalendarDefaultSpace)
        try c.encodeIfPresent(textScale,                 forKey: .textScale)
        try c.encodeIfPresent(sidebarMode,               forKey: .sidebarMode)
        try c.encodeIfPresent(tasksGrouping,             forKey: .tasksGrouping)
        try c.encodeIfPresent(perTabDocsSync,            forKey: .perTabDocsSync)
        try c.encodeIfPresent(updatedAt,                 forKey: .updatedAt)
        // compact string → raw JSON object (parse the blob back into a fragment
        // so it lands in the jsonb column as an object, not a quoted string).
        if let json = notificationPrefsJSON, let data = json.data(using: .utf8) {
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            try c.encode(value, forKey: .notificationPrefs)
        }
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
    public var spaceId: UUID?
    /// This project's own color token (0031); nil ⇒ inherit the space color.
    public var colorToken: String?
    /// The Canvas course this class is explicitly linked to (0032); nil ⇒ unlinked.
    public var canvasCourse: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
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
        case spaceId      = "space_id"
        case colorToken   = "color_token"
        case canvasCourse = "canvas_course"
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
        self.spaceId      = p.spaceID
        self.colorToken   = p.colorToken
        self.canvasCourse = p.canvasCourse
    }

    public func toDomain() -> Project {
        // Nested display arrays (assignments, notes, pinned, backlinks) are NOT persisted;
        // toDomain() returns them as []. Task 2 re-nests projects into spaces via spaceName.
        var project = Project(id: id, name: name, code: code, isClass: isClass,
                spaceName: spaceName,
                spaceColor: AtlasTheme.Colors.accent, // Task 2 re-derives from spaceName
                meetingInfo: meetingInfo, instructor: instructor,
                canvasSynced: canvasSynced, overview: overview,
                colorToken: colorToken, canvasCourse: canvasCourse)
        project.spaceID = spaceId
        return project
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
    public var completedAt: Date?
    public var scheduledAt: Date?
    public var notes: String?
    public var noteId: UUID?
    public var durationMin: Int?
    public var workBlockGoogleEventId: String?
    /// Apple Calendar mirror id for this task's work-block (migration 0026). Round-tripped
    /// so a client edit never nulls the linkage. Best-effort — Mac is the only EventKit device.
    public var appleEventId: String?
    public var spaceId: UUID?
    public var assigneeId: UUID?
    public var createdBy: UUID?
    /// Canvas assignment id (migration 0012). Round-tripped so a client edit of a
    /// Canvas task never nulls the origin column.
    public var canvasUid: String?
    /// Canvas course label (migration 0032) — the SUMMARY bracket this assignment came
    /// from. Round-tripped so a client edit never nulls it; decode drives the class picker.
    public var canvasCourse: String?
    /// The `calendar_feeds` row this task was ingested from (multi-ICS feeds). Optional so
    /// decoding survives rows/DBs that predate the migration. Round-tripped so a client
    /// edit of a feed task never nulls the origin column.
    public var feedId: UUID?
    /// The feed's type — "canvas" or "ics". Optional (migration window). Round-tripped so
    /// a client edit never nulls it; decode drives the domain's source label.
    public var feedType: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case userId      = "user_id"
        case projectId   = "project_id"
        case spaceName   = "space_name"
        case title
        case dueDate     = "due_date"
        case status
        case done
        case completedAt = "completed_at"
        case scheduledAt = "scheduled_at"
        case notes
        case noteId      = "note_id"
        case durationMin = "duration_min"
        case workBlockGoogleEventId = "work_block_google_event_id"
        case appleEventId = "apple_event_id"
        case spaceId     = "space_id"
        case assigneeId  = "assignee_id"
        case createdBy   = "created_by"
        case canvasUid   = "canvas_uid"
        case canvasCourse = "canvas_course"
        case feedId      = "feed_id"
        case feedType    = "feed_type"
    }

    public init(domain t: TaskItem) {
        self.id          = t.id
        self.projectId   = nil // no projectId on TaskItem yet; map to nil
        self.spaceName   = t.spaceName
        self.title       = t.title
        self.dueDate     = t.dueDate
        self.status      = TaskRow.encode(status: t.status)
        self.done        = t.done
        self.completedAt = t.completedAt
        self.scheduledAt = t.scheduledAt
        self.notes       = t.notes
        self.noteId      = t.noteID
        self.durationMin = t.durationMin
        self.workBlockGoogleEventId = t.workBlockGoogleEventId
        self.appleEventId = t.appleEventId
        self.spaceId     = t.spaceID
        self.assigneeId  = t.assigneeID
        self.createdBy   = t.createdByID
        self.canvasUid   = t.canvasUID
        self.canvasCourse = t.canvasCourse
        self.feedId      = t.feedID
        self.feedType    = t.feedType
    }

    public func toDomain() -> TaskItem {
        var task = TaskItem(id: id,
                 title: title,
                 dueLabel: TaskItem.dueLabel(for: dueDate),
                 status: TaskRow.decode(status: status),
                 done: done,
                 completedAt: completedAt,
                 scheduledAt: scheduledAt,
                 dueDate: dueDate,
                 durationMin: durationMin,
                 noteID: noteId,
                 workBlockGoogleEventId: workBlockGoogleEventId,
                 appleEventId: appleEventId,
                 spaceName: spaceName,
                 notes: notes ?? "")
        task.spaceID = spaceId
        task.assigneeID = assigneeId
        task.createdByID = createdBy
        task.canvasUID = canvasUid
        task.canvasCourse = canvasCourse
        task.feedID = feedId
        task.feedType = feedType
        return task
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
    /// Apple Calendar mirror id (migration 0026). Round-tripped so a client upsert never
    /// nulls the Apple linkage; does NOT affect source derivation (Apple-mirrored events
    /// stay `.atlas`). Best-effort continuity — the Mac is the only EventKit device.
    public var appleEventId: String?
    public var noteId: UUID?
    public var spaceId: UUID?
    /// Canvas event id (migration 0012). Drives `.canvas` source + read-only at load.
    /// Decode-only: Canvas events are read-only, so the client never upserts one back —
    /// `init(domain:)` has no Canvas value to carry and sets nil (never nulls a live row).
    public var canvasUid: String?
    /// Canvas course label (migration 0032) — the SUMMARY bracket this event came from.
    /// Decode-only, like `canvasUid`: Canvas events are read-only so the client never
    /// upserts one back (`init(domain:)` sets nil). Drives the class picker + remap.
    public var canvasCourse: String?
    /// Which Google account (connection) this event routes OUT to (migration 0028).
    /// Stamped from the event's space at write time; nil ⇒ the space is linked to no
    /// account, so the event stays in Atlas. The server's per-connection push reads it.
    public var googleConnectionId: UUID?
    /// The `calendar_feeds` row this event was ingested from (multi-ICS feeds). Non-nil
    /// for any feed-sourced row (Canvas OR generic ICS) and drives read-only. Optional so
    /// decoding survives rows/DBs that predate the migration (null until backfill).
    public var feedId: UUID?
    /// The feed's type — "canvas" or "ics" (multi-ICS feeds). Drives source derivation:
    /// takes precedence over `canvasUid`/`googleEventId`. Optional for the same
    /// migration-window reason; null falls back to the legacy `canvasUid` rule.
    public var feedType: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
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
        case appleEventId = "apple_event_id"
        case noteId    = "note_id"
        case spaceId   = "space_id"
        case canvasUid = "canvas_uid"
        case canvasCourse = "canvas_course"
        case googleConnectionId = "google_connection_id"
        case feedId    = "feed_id"
        case feedType  = "feed_type"
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
        self.appleEventId = e.appleEventId
        self.noteId    = e.noteID
        self.spaceId   = e.spaceID
        // CalendarEvent carries no Canvas id (Canvas events are read-only and never
        // upserted by the client), so nothing to round-trip from the domain here.
        self.canvasUid = nil
        self.canvasCourse = nil
        self.googleConnectionId = e.googleConnectionId
        // Feed columns are decode-only (feed events are read-only, never upserted back).
        self.feedId = nil
        self.feedType = nil
    }

    /// - Parameter feedNames: `calendar_feeds.id → display_name`, used to label a generic
    ///   ICS feed event (`.icsFeed(name:)`). Empty by default so callers that don't ingest
    ///   feed events (and tests) can decode without wiring the lookup; an unresolved id
    ///   falls back to "Calendar" rather than mislabeling the source.
    public func toDomain(feedNames: [UUID: String] = [:]) -> CalendarEvent {
        // Source is derived at ingest, never guessed. `feed_type` (multi-ICS feeds) is the
        // authority when present: "canvas" → .canvas, "ics" → the named feed (rule 5: a
        // Schoology feed labels as itself, never "Canvas"). Feed rows also carry a google
        // id (google_origin), so feed_type MUST win over google. When feed_type is null
        // (rows predating the migration), fall back to the legacy canvas_uid rule.
        let derivedSource: EventSource
        switch feedType {
        case "canvas":
            derivedSource = .canvas
        case "ics":
            let name = feedId.flatMap { feedNames[$0] } ?? "Calendar"
            derivedSource = .icsFeed(name: name)
        default:
            derivedSource =
                canvasUid != nil ? .canvas :
                (googleEventId != nil ? .google : .atlas)
        }
        // Every feed-sourced row is server-owned → read-only. `feed_id` covers all feeds;
        // `canvas_uid` preserves the pre-migration invariant for un-backfilled Canvas rows.
        let readOnly = feedId != nil || canvasUid != nil
        // CalendarEvent has `var id: UUID = UUID()` — memberwise init exposes `id`
        // as an overridable parameter, so the DB UUID IS preserved here.
        var event = CalendarEvent(id: id,
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
                      // Canvas rows are server-owned: sync stomps title/start/end each
                      // tick, so they're read-only in Atlas. (An Atlas-origin event
                      // mirrored TO Google also carries a googleEventId, so it loads as
                      // .google — accepted trade-off; only affects Mac reap eligibility
                      // for that edge, the fail-safe direction.)
                      isReadOnly: readOnly,
                      source: derivedSource,
                      googleEventId: googleEventId,
                      appleEventId: appleEventId)
        event.spaceID = spaceId
        event.canvasCourse = canvasCourse
        event.googleConnectionId = googleConnectionId
        return event
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
    /// Optional so decoding survives a DB that predates migration 0018;
    /// nil reads as the column default, "plain".
    public var bodyFormat: String?
    public var updatedAt: Date
    public var isExternal: Bool
    public var googleDocId: String?
    public var spaceId: UUID?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case userId      = "user_id"
        case spaceName   = "space_name"
        case projectId   = "project_id"
        case title
        case body
        case bodyFormat  = "body_format"
        case updatedAt   = "updated_at"
        case isExternal  = "is_external"
        case googleDocId = "google_doc_id"
        case spaceId     = "space_id"
    }

    public init(domain n: Note) {
        self.id          = n.id
        self.spaceName   = n.spaceName
        self.projectId   = n.projectID
        self.title       = n.title
        self.body        = n.body
        self.bodyFormat  = n.bodyFormat.rawValue
        self.updatedAt   = n.updatedAt
        self.isExternal  = n.isExternal
        self.googleDocId = n.googleDocId
        self.spaceId     = n.spaceID
    }

    public func toDomain() -> Note {
        var note = Note(id: id, title: title, body: body,
             bodyFormat: bodyFormat.flatMap(Note.BodyFormat.init(rawValue:)) ?? .plain,
             spaceName: spaceName, projectID: projectId,
             updatedAt: updatedAt, isExternal: isExternal,
             googleDocId: googleDocId)
        note.spaceID = spaceId
        return note
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
/// shared `.iso8601` decoder can't parse — same reason `GoogleConnection` keeps
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
    /// `GoogleConnection.lastSyncedDate` so server-written (microsecond) times decode.
    public static func date(from s: String?) -> Date? {
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
// DocNoteTabRow — one tab of a multi-tab Google Doc note
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `doc_note_tabs` (migration `0020`). One row per Docs tab, keyed by
/// the stable Docs `tabId`. Clients only ever read tabs; all writes flow through
/// service-role edge functions. `updated_at` is server-owned and unused here, so
/// it's omitted from the row rather than decoded leniently like `ReferenceRow`.
public struct DocNoteTabRow: Codable {
    public var id: UUID
    public var referenceId: UUID
    public var noteId: UUID
    public var tabId: String
    public var parentTabId: String?
    public var title: String
    public var ord: Int
    public var bodyMd: String
    public var writable: Bool
    public var readonlyReason: String?
    public var droppedStyling: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case referenceId    = "reference_id"
        case noteId         = "note_id"
        case tabId          = "tab_id"
        case parentTabId    = "parent_tab_id"
        case title
        case ord
        case bodyMd         = "body_md"
        case writable
        case readonlyReason = "readonly_reason"
        case droppedStyling = "dropped_styling"
    }

    public func toDomain() -> DocNoteTab {
        DocNoteTab(id: id, referenceID: referenceId, tabId: tabId, parentTabId: parentTabId,
                   title: title, ord: ord, bodyMD: bodyMd, writable: writable,
                   readonlyReason: readonlyReason, droppedStyling: droppedStyling ?? false)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DocNoteImageRow — one re-hosted inline image of a Doc note
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `doc_note_images` (migration `0023`). One row per inline image the
/// pull pipeline re-hosted into the private `doc-images` bucket. Clients only read
/// these; all writes flow through service-role edge functions. `user_id` /
/// `created_at` are owned by the server and unused here, so they're omitted from
/// the row rather than decoded (extra JSON keys are ignored), matching `DocNoteTabRow`.
public struct DocNoteImageRow: Codable {
    public var id: UUID
    public var noteId: UUID
    public var tabId: String
    public var objectId: String
    public var storagePath: String
    public var widthPt: Double?
    public var heightPt: Double?
    public var cropLocked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case noteId       = "note_id"
        case tabId        = "tab_id"
        case objectId     = "object_id"
        case storagePath  = "storage_path"
        case widthPt      = "width_pt"
        case heightPt     = "height_pt"
        case cropLocked   = "crop_locked"
    }

    public func toDomain() -> DocNoteImage {
        DocNoteImage(id: id, noteID: noteId, tabId: tabId, objectId: objectId,
                     storagePath: storagePath, widthPt: widthPt, heightPt: heightPt,
                     cropLocked: cropLocked)
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

    enum CodingKeys: String, CodingKey, CaseIterable {
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
// GoogleConnection — one row of the multi-account `google_connections` table (0028)
// ─────────────────────────────────────────────────────────────────────────────

/// One connected Google account (migration 0028): a user-named login routed to a
/// destination space. A user can have N of these. The client reads only owner-granted
/// columns (`vault_secret_id` is hidden by RLS), so `loadGoogleConnections()` selects
/// an explicit list.
///
/// `lastSyncedAt` stays a String because the server writes it with microsecond
/// precision the plain `.iso8601` decoder rejects; `lastSyncedDate` parses it
/// leniently for the UI.
public struct GoogleConnection: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var googleEmail: String
    public var calendarId: String?
    public var spaceId: UUID?             // routing link; nil ⇒ read-in only
    public var status: String            // active | error | revoked
    public var lastError: String?
    public var lastSyncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case googleEmail  = "google_email"
        case calendarId   = "calendar_id"
        case spaceId      = "space_id"
        case status
        case lastError    = "last_error"
        case lastSyncedAt = "last_synced_at"
    }

    /// `lastSyncedAt` parsed leniently (with or without fractional seconds).
    public var lastSyncedDate: Date? { ReferenceRow.date(from: lastSyncedAt) }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoogleConnectionCalendar — one calendar of a connection (per-calendar sync, 0036)
// ─────────────────────────────────────────────────────────────────────────────

/// One row of `google_connection_calendars` (migration 0036): a calendar belonging
/// to a Google connection, and whether the user has it syncing. The client reads only
/// owner-granted columns (`sync_token` is service-role only), so the load selects an
/// explicit list. Toggling `selected` (via the google-connect edge function) is what
/// opts a calendar in/out of sync.
public struct GoogleConnectionCalendar: Codable, Identifiable, Equatable {
    public var connectionId: UUID
    public var calendarId: String
    public var summary: String
    public var isPrimary: Bool
    public var selected: Bool

    /// Stable identity for SwiftUI lists (a calendar id is unique within a connection).
    public var id: String { "\(connectionId.uuidString):\(calendarId)" }

    enum CodingKeys: String, CodingKey {
        case connectionId = "connection_id"
        case calendarId   = "calendar_id"
        case summary
        case isPrimary    = "is_primary"
        case selected
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
/// `lastSyncedAt` is a String because the server writes it with microsecond precision
/// the plain `.iso8601` decoder can't parse; `lastSyncedDate` parses it leniently for
/// the UI.
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
    /// shows the paste form again.
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
// CalendarFeedRow — one subscribed calendar feed (multi-ICS feeds)
// ─────────────────────────────────────────────────────────────────────────────

/// A row from `calendar_feeds` — the user's subscribed calendar feeds (Canvas OR a
/// generic ICS feed). Generalizes `canvas_connections` to N feeds. The client reads
/// only the owner-granted, non-secret columns (the feed-URL Vault pointer is NOT
/// granted, so a `select=*` would 403); `loadCalendarFeeds()` selects them explicitly.
///
/// `lastSyncedAt` is a String because the server writes it with microsecond precision
/// the plain `.iso8601` decoder can't parse; `lastSyncedDate` parses it leniently.
public struct CalendarFeedRow: Codable, Identifiable {
    public var id: UUID
    public var feedType: String          // "canvas" | "ics"
    public var displayName: String       // the feed's label (never "Canvas" for an ICS feed)
    public var spaceName: String?        // Atlas space unmatched feed items land in
    public var status: String            // active | error | revoked
    public var lastSyncedAt: String?
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case feedType     = "feed_type"
        case displayName  = "display_name"
        case spaceName    = "space_name"
        case status
        case lastSyncedAt = "last_synced_at"
        case lastError    = "last_error"
    }

    /// The server owns this feed's sync whenever it exists and hasn't been revoked;
    /// `error` still counts as server-owned (the server keeps retrying). Mirrors
    /// `CanvasConnectionRow.isServerOwned`.
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
// ProfileRow — public identity (collab phase 1). Row is created server-side by
// the signup trigger; the client reads it and may update display_name.
// ─────────────────────────────────────────────────────────────────────────────

public struct ProfileRow: Codable {
    public var userId: UUID
    public var displayName: String
    public var email: String
    public var avatarColor: String

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case displayName = "display_name"
        case email
        case avatarColor = "avatar_color"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProjectMemberRow / InviteRow — collab phase 2 (shared projects)
// ─────────────────────────────────────────────────────────────────────────────

public struct ProjectMemberRow: Codable {
    public var projectId: UUID
    public var userId: UUID
    public var role: String
    public var addedAt: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId    = "user_id"
        case role
        case addedAt   = "added_at"
    }
}

public struct SpaceMemberRow: Codable {
    public var spaceId: UUID
    public var userId: UUID
    public var role: String
    public var addedAt: String

    enum CodingKeys: String, CodingKey {
        case spaceId  = "space_id"
        case userId   = "user_id"
        case role
        case addedAt  = "added_at"
    }
}

public enum InviteKind: String, Codable {
    case space, project
}

public enum InviteStatus: String, Codable {
    case pending, accepted, declined
}

public struct InviteRow: Codable {
    public var id: UUID
    public var kind: InviteKind
    public var targetId: UUID
    public var inviterId: UUID
    public var inviteeEmail: String
    public var status: InviteStatus
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case targetId     = "target_id"
        case inviterId    = "inviter_id"
        case inviteeEmail = "invitee_email"
        case status
        case createdAt    = "created_at"
    }
}

extension InviteRow {
    /// Pure rule: an accepted PROJECT invite yields a member-role row for the
    /// accepting user; anything else (declined, still pending, or a space-kind
    /// invite — space sharing is Phase 4) yields no membership.
    public static func membershipIfAccepted(_ invite: InviteRow, acceptingUserId: UUID) -> ProjectMemberRow? {
        guard invite.status == .accepted, invite.kind == .project else { return nil }
        return ProjectMemberRow(projectId: invite.targetId, userId: acceptingUserId,
                                role: "member", addedAt: "")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AvailabilityBlockRow / SharingPrefRow — collab phase 3 (availability)
// ─────────────────────────────────────────────────────────────────────────────

public struct AvailabilityBlockRow: Codable {
    public var id: UUID
    public var userId: UUID
    public var startAt: Date
    public var endAt: Date
    public var source: String
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case startAt   = "start_at"
        case endAt     = "end_at"
        case source
        case updatedAt = "updated_at"
    }
}

public struct SharingPrefRow: Codable {
    public var userId: UUID
    public var kind: String
    public var targetId: UUID
    public var detailLevel: String

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case kind
        case targetId    = "target_id"
        case detailLevel = "detail_level"
    }
}

// MARK: - AtlasDB PostgREST Client

/// Thin async PostgREST client. All requests mirror the `SupabaseAuth.request(...)` pattern:
/// `apikey: SupabaseConfig.anonKey`, `Authorization: Bearer <accessToken>`, base URL
/// `SupabaseConfig.restBase`. RLS on the server scopes every query to `auth.uid()`.
///
/// If `session()` returns nil, every method throws `AtlasDBError.notAuthenticated`.
/// Callers guard offline mode externally; this client fails cleanly rather than crashing.
///
/// The provider is async so callers can validate/refresh the token per request
/// (the JWT TTL is 1 hour) — pass a refresh-if-needed provider, not a raw read.
public final class AtlasDB {

    private let sessionProvider: () async -> SupabaseSession?

    public init(session: @escaping () async -> SupabaseSession?) {
        self.sessionProvider = session
    }

    // MARK: - Internal helpers

    private func requireSession() async throws -> SupabaseSession {
        guard let s = await sessionProvider() else {
            throw AtlasDBError.notAuthenticated
        }
        return s
    }

    /// GET `<restBase>/<table>?select=*&order=<column>` and decode the JSON array.
    /// Pass `order` to ensure stable, deterministic row ordering across launches.
    private func getAll<T: Decodable>(_ table: String, order: String? = nil) async throws -> [T] {
        let sess = try await requireSession()
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
        let sess = try await requireSession()
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

    /// POST (upsert) or DELETE — most callers expect no response body
    /// (`return=minimal`) and ignore the returned data; `setTaskDone` opts into
    /// `return=representation` to detect a zero-row PATCH.
    @discardableResult
    private func send(method: String,
                      table: String,
                      query: [URLQueryItem] = [],
                      extraHeaders: [String: String] = [:],
                      body: Data? = nil,
                      sess: SupabaseSession) async throws -> Data {
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
        return data
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
        // Independent tables, so overlap the two round-trips.
        async let refRowsAsync:    [ReferenceRow]           = getAll("project_references",  order: "created_at.desc")
        async let attachRowsAsync: [ReferenceAttachmentRow] = getAll("reference_attachments", order: "created_at.desc")
        let refRows:    [ReferenceRow]           = (try? await refRowsAsync)    ?? []
        let attachRows: [ReferenceAttachmentRow] = (try? await attachRowsAsync) ?? []

        // Feed names label generic-ICS events (`.icsFeed(name:)`). Best-effort: if the
        // multi-ICS-feeds migration isn't deployed yet, `calendar_feeds` 404s — degrade to
        // an empty map (unresolved ICS events fall back to "Calendar") rather than failing
        // the whole load. A `[feedId: display_name]` lookup keeps `toDomain` decoupled from
        // the feeds fetch, and never mislabels a feed as another (rule 5).
        let feedRows: [CalendarFeedRow] = (try? await loadCalendarFeeds()) ?? []
        let feedNames = Dictionary(feedRows.map { ($0.id, $0.displayName) },
                                   uniquingKeysWith: { first, _ in first })

        return AtlasSnapshot(
            spaces:   sr.map { $0.toDomain() },
            projects: pr.map { $0.toDomain() },
            tasks:    tr.map { $0.toDomain() },
            events:   er.map { $0.toDomain(feedNames: feedNames) },
            notes:    nr.map { $0.toDomain() },
            goals:    gr.map { $0.toDomain() },
            references:           refRows.map    { $0.toDomain() },
            referenceAttachments: attachRows.map { $0.toDomain() }
        )
    }

    /// Re-pulls just the notes table. The references reload path uses this so an
    /// imported Doc's linked note (created server-side by `drive-import` and filled
    /// by the sync cron) surfaces without an app relaunch.
    public func loadNotes() async throws -> [Note] {
        let rows: [NoteRow] = try await getAll("notes", order: "id")
        return rows.map { $0.toDomain() }
    }

    /// The tabs of a multi-tab Google Doc note, ordered by `ord`. Filters the
    /// `doc_note_tabs` table (RLS-scoped) down to one NOTE client-side, mirroring
    /// `loadProjectMembers`. Keyed by `note_id` (0023) so a Doc imported into several
    /// projects shares one tab set. Single-tab Docs have no rows here.
    public func fetchDocNoteTabs(noteID: UUID) async throws -> [DocNoteTab] {
        let rows: [DocNoteTabRow] = try await getAll("doc_note_tabs", order: "ord")
        return rows.filter { $0.noteId == noteID }.map { $0.toDomain() }
    }

    /// The re-hosted inline images of a Doc note. Filters the `doc_note_images`
    /// table (RLS-scoped) down to one note client-side, mirroring `fetchDocNoteTabs`.
    /// Notes with no inline images have no rows here.
    public func fetchDocNoteImages(noteID: UUID) async throws -> [DocNoteImage] {
        let rows: [DocNoteImageRow] = try await getAll("doc_note_images")
        return rows.filter { $0.noteId == noteID }.map { $0.toDomain() }
    }

    /// Downloads one object's bytes from the private `doc-images` Storage bucket via
    /// the authenticated-object endpoint. Uses the SAME auth as every PostgREST call —
    /// `apikey: anonKey` + the user's `Bearer` JWT — so the owner-read policy on
    /// `storage.objects` (path prefix = user id) scopes the read to the caller's own
    /// images. `path` is the object key: `<user_id>/<note_id>/<object_id>.<ext>`.
    public func downloadDocImage(path: String) async throws -> Data {
        let sess = try await requireSession()
        let url = SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/authenticated/doc-images")
            .appendingPathComponent(path)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey,       forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(sess.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return data
    }

    /// Reads ALL of the caller's `google_connections` rows (multi-account, 0028).
    /// Selects only the owner-granted columns; RLS scopes the query to the signed-in
    /// user. Sorted by id for a list order that's stable across launches.
    public func loadGoogleConnections() async throws -> [GoogleConnection] {
        let rows: [GoogleConnection] = try await getColumns(
            "google_connections",
            columns: "id,name,google_email,calendar_id,space_id,status,last_error,last_synced_at")
        return rows.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Reads the caller's `google_connection_calendars` rows (per-calendar selection,
    /// 0036), scoped by RLS to connections the user owns. Filters to one connection
    /// client-side (mirrors `fetchDocNoteTabs`), primary first then by name, so the
    /// calendar picker renders in a stable order.
    public func loadGoogleConnectionCalendars(connectionId: UUID) async throws -> [GoogleConnectionCalendar] {
        let rows: [GoogleConnectionCalendar] = try await getColumns(
            "google_connection_calendars",
            columns: "connection_id,calendar_id,summary,is_primary,selected")
        return rows
            .filter { $0.connectionId == connectionId }
            .sorted {
                if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
                return $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
            }
    }

    /// The dedicated Google login powering Drive/Docs background work (import /
    /// re-sync / write-back), independent of calendar connections — at most ONE per
    /// user (`google_docs_connections.user_id` PK, owner-readable columns). Mirrors
    /// `loadGoogleConnections()`; nil ⇒ no explicit Docs login (the server then falls
    /// back to the oldest calendar connection).
    public struct GoogleDocsConnection: Codable, Equatable {
        public var googleEmail: String
        public var status: String            // active | error
        public var lastError: String?

        enum CodingKeys: String, CodingKey {
            case googleEmail = "google_email"
            case status
            case lastError   = "last_error"
        }
    }

    public func loadGoogleDocsConnection() async throws -> GoogleDocsConnection? {
        let rows: [GoogleDocsConnection] = try await getColumns(
            "google_docs_connections",
            columns: "google_email,status,last_error")
        return rows.first
    }

    /// Reads the caller's `canvas_connections` row (server-owned Canvas sync state),
    /// or nil when the user has no Canvas connection. Selects only the owner-granted
    /// columns; RLS scopes the query to the signed-in user.
    public func loadCanvasConnection() async throws -> CanvasConnectionRow? {
        let rows: [CanvasConnectionRow] = try await getColumns(
            "canvas_connections",
            columns: "status,last_synced_at,last_error,space_name")
        return rows.first
    }

    /// Reads ALL of the caller's `calendar_feeds` rows (multi-ICS feeds — Canvas + generic
    /// ICS). Selects only the owner-granted, non-secret columns; RLS scopes the query to
    /// the signed-in user. Sorted by id for a list order that's stable across launches.
    /// Mirrors `loadGoogleConnections` / `loadCanvasConnection`.
    public func loadCalendarFeeds() async throws -> [CalendarFeedRow] {
        let rows: [CalendarFeedRow] = try await getColumns(
            "calendar_feeds",
            columns: "id,feed_type,display_name,space_name,status,last_synced_at,last_error")
        return rows.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// The caller's profile row, or nil if migration 0015 isn't deployed yet
    /// (callers treat nil as "profiles unavailable" and degrade silently).
    public func loadProfile() async throws -> ProfileRow? {
        let rows: [ProfileRow] = (try? await getAll("profiles", order: "user_id")) ?? []
        return rows.first
    }

    /// The caller's synced settings row (0025), or nil when none has been written
    /// yet. RLS scopes the singleton to the signed-in user, so `first` is the row.
    public func loadUserSettings() async throws -> UserSettingsRow? {
        let rows: [UserSettingsRow] = try await getAll("user_settings")
        return rows.first
    }

    /// Upserts the caller's synced settings row on the `user_id` primary key.
    /// The row's `userId` must be the signed-in user (RLS `with check` enforces it).
    public func upsertUserSettings(_ s: UserSettingsRow) async throws {
        let sess = try await requireSession()
        let body = try isoEncoder.encode(s)
        try await send(method: "POST", table: "user_settings",
                       query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                       extraHeaders: upsertHeaders,
                       body: body, sess: sess)
    }

    // MARK: Bug reports + presence pings (0037)

    /// File a bug report as the signed-in user. `platform` is "macos" / "ios";
    /// `appVersion` is CFBundleShortVersionString. RLS requires `user_id =
    /// auth.uid()`, so we stamp the current user id on the row. The owner reads
    /// these back only via the service-role admin-stats function.
    public func insertBugReport(message: String, appVersion: String, platform: String,
                                title: String? = nil, contactEmail: String? = nil,
                                log: String? = nil) async throws {
        let sess = try await requireSession()
        let userId = try await currentUserId()
        struct Body: Encodable {
            let user_id: UUID
            let message: String
            let app_version: String
            let platform: String
            let title: String?
            let contact_email: String?
            let log: String?
        }
        let body = try JSONEncoder().encode(
            Body(user_id: userId, message: message, app_version: appVersion, platform: platform,
                 title: title, contact_email: contactEmail, log: log))
        try await send(method: "POST", table: "bug_reports",
                       extraHeaders: ["Prefer": "return=minimal"],
                       body: body, sess: sess)
    }

    /// Fire-and-forget launch presence: upsert this device's `app_pings` row so
    /// the owner dashboard can count Mac vs mobile actives. Best-effort — callers
    /// ignore failures (offline, pre-migration DB, etc.).
    public func recordAppPing(platform: String, appVersion: String) async throws {
        let sess = try await requireSession()
        let userId = try await currentUserId()
        struct Body: Encodable {
            let user_id: UUID
            let platform: String
            let app_version: String
            let last_seen_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let body = try JSONEncoder().encode(
            Body(user_id: userId, platform: platform, app_version: appVersion, last_seen_at: now))
        try await send(method: "POST", table: "app_pings",
                       query: [URLQueryItem(name: "on_conflict", value: "user_id,platform")],
                       extraHeaders: upsertHeaders,
                       body: body, sess: sess)
    }

    // MARK: Shared projects (collab phase 2) — members / invites

    /// The signed-in user's id, parsed from the session's `user.id` string.
    /// `AtlasDB` is the only place in this codebase that holds a session
    /// reference (`sessionProvider`), so this is the one accessor `AppState`
    /// and other callers should use rather than threading the session
    /// through separately.
    public func currentUserId() async throws -> UUID {
        let sess = try await requireSession()
        guard let id = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "session user.id is not a valid UUID")
        }
        return id
    }

    /// The signed-in user's raw JWT access token, needed by realtime
    /// subscriptions (which authorize postgres_changes against this token's
    /// claims, not just the anon apikey header used for REST calls).
    public func currentAccessToken() async throws -> String {
        try await requireSession().accessToken
    }

    public func loadProjectMembers(projectId: UUID) async throws -> [ProjectMemberRow] {
        let all: [ProjectMemberRow] = (try? await getAll("project_members", order: "added_at")) ?? []
        return all.filter { $0.projectId == projectId }
    }

    /// Every project-member row the caller may see (RLS-scoped), grouped by
    /// project id. One round-trip that replaces the per-project N+1 loop of
    /// `loadProjectMembers(projectId:)` — the old path fetched the whole
    /// `project_members` table once per project and filtered client-side.
    /// Rows within each group keep `added_at` order (the fetch is ordered and
    /// `Dictionary(grouping:)` preserves element order). Best-effort: a missing
    /// table (pre-migration) yields an empty map rather than throwing.
    public func loadAllProjectMembers() async throws -> [UUID: [ProjectMemberRow]] {
        let all: [ProjectMemberRow] = (try? await getAll("project_members", order: "added_at")) ?? []
        return Dictionary(grouping: all, by: { $0.projectId })
    }

    /// Fetches specific projects by id — used for "Shared with me" rows,
    /// which belong to someone else's space and so aren't in `AppState.spaces`.
    public func loadProjectsByIds(_ ids: [UUID]) async throws -> [Project] {
        let all: [ProjectRow] = try await getAll("projects")
        return all.filter { ids.contains($0.id) }.map { $0.toDomain() }
    }

    /// Invites addressed to the caller's own email with `status = pending`.
    /// RLS already scopes rows to the caller's email; the `.pending` filter is
    /// applied client-side too, in case a future caller wants all their invites.
    public func loadPendingInvites() async throws -> [InviteRow] {
        let all: [InviteRow] = (try? await getAll("invites", order: "created_at.desc")) ?? []
        return all.filter { $0.status == .pending }
    }

    @discardableResult
    public func createProjectInvite(projectId: UUID, inviteeEmail: String) async throws -> InviteRow {
        let sess = try await requireSession()
        let invite = InviteRow(id: UUID(), kind: .project, targetId: projectId,
                               inviterId: try await currentUserId(), inviteeEmail: inviteeEmail,
                               status: .pending, createdAt: "")
        let body = try isoEncoder.encode(invite)
        try await send(method: "POST", table: "invites", body: body, sess: sess)
        return invite
    }

    public func loadSpaceMembers(spaceId: UUID) async throws -> [SpaceMemberRow] {
        let all: [SpaceMemberRow] = (try? await getAll("space_members", order: "added_at")) ?? []
        return all.filter { $0.spaceId == spaceId }
    }

    /// Every space-member row the caller may see (RLS-scoped), grouped by
    /// space id. One round-trip that replaces the per-space N+1 loop of
    /// `loadSpaceMembers(spaceId:)` — the old path fetched the whole
    /// `space_members` table once per space and filtered client-side.
    /// Rows within each group keep `added_at` order (the fetch is ordered and
    /// `Dictionary(grouping:)` preserves element order). Best-effort: a missing
    /// table (pre-migration) yields an empty map rather than throwing.
    public func loadAllSpaceMembers() async throws -> [UUID: [SpaceMemberRow]] {
        let all: [SpaceMemberRow] = (try? await getAll("space_members", order: "added_at")) ?? []
        return Dictionary(grouping: all, by: { $0.spaceId })
    }

    @discardableResult
    public func createSpaceInvite(spaceId: UUID, inviteeEmail: String) async throws -> InviteRow {
        let sess = try await requireSession()
        let invite = InviteRow(id: UUID(), kind: .space, targetId: spaceId,
                               inviterId: try await currentUserId(), inviteeEmail: inviteeEmail,
                               status: .pending, createdAt: "")
        let body = try isoEncoder.encode(invite)
        try await send(method: "POST", table: "invites", body: body, sess: sess)
        return invite
    }

    /// Accepts or declines a pending invite. Accepting goes through the
    /// `accept_invite` Postgres function (security definer) rather than the
    /// client inserting `project_members` directly — the invitee isn't yet a
    /// member, so a direct insert would fail `project_members`' owner-only
    /// insert policy. PostgREST exposes RPC functions at `<restBase>/rpc/<fn>`,
    /// and `send`'s `table` parameter is appended directly onto `restBase`, so
    /// `table: "rpc/accept_invite"` reaches the right endpoint.
    public func respondToInvite(id: UUID, accept: Bool) async throws {
        let sess = try await requireSession()
        if accept {
            let body = try JSONSerialization.data(withJSONObject: ["invite_id": id.uuidString])
            try await send(method: "POST", table: "rpc/accept_invite", body: body, sess: sess)
        } else {
            let body = try JSONSerialization.data(withJSONObject: ["status": "declined"])
            try await send(method: "PATCH", table: "invites",
                           query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                           body: body, sess: sess)
        }
    }

    /// Updates the caller's `display_name`. This client has no partial-PATCH
    /// helper, only whole-row upserts (see `upsertGoal` etc.), so this fetches
    /// the current row, mutates it, and upserts the full row back — same
    /// `send`/`isoEncoder`/`upsertHeaders` plumbing, but scoped by `user_id`
    /// (the `profiles` primary key) instead of `id`.
    public func updateDisplayName(_ name: String) async throws {
        let sess = try await requireSession()
        guard var row = try await loadProfile() else {
            throw AtlasDBError.requestFailed(0, "No profile row for signed-in user")
        }
        row.displayName = name
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "profiles",
                       query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                       extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    // MARK: Availability + sharing prefs (collab phase 3)

    /// Best-effort: degrades to `[]` if the availability migration isn't deployed
    /// yet, or if the caller passes no member ids to look up.
    public func loadAvailability(forProjectMemberIds userIds: [UUID], from: Date, to: Date) async throws -> [AvailabilityBlockRow] {
        guard !userIds.isEmpty else { return [] }
        let all: [AvailabilityBlockRow] = (try? await getAll("availability_blocks", order: "start_at")) ?? []
        let idSet = Set(userIds)
        return all.filter { idSet.contains($0.userId) && $0.startAt < to && $0.endAt > from }
    }

    /// Delete-then-insert the caller's own published window — simple and
    /// self-healing, matching the plan's stated strategy over per-event diffing.
    public func publishAvailability(_ blocks: [AvailabilityBlockRow], windowStart: Date, windowEnd: Date) async throws {
        let sess = try await requireSession()
        // Delete the caller's existing rows whose start_at falls in the window.
        try await send(method: "DELETE", table: "availability_blocks",
                       query: [
                           URLQueryItem(name: "start_at", value: "gte.\(isoString(windowStart))"),
                           URLQueryItem(name: "start_at", value: "lt.\(isoString(windowEnd))"),
                       ],
                       sess: sess)
        guard !blocks.isEmpty else { return }
        let body = try isoEncoder.encode(blocks)
        try await send(method: "POST", table: "availability_blocks", body: body, sess: sess)
    }

    public func loadSharingPref(kind: String, targetId: UUID) async throws -> SharingPrefRow? {
        let all: [SharingPrefRow] = (try? await getAll("sharing_prefs")) ?? []
        return all.first { $0.kind == kind && $0.targetId == targetId }
    }

    public func setSharingPref(kind: String, targetId: UUID, detailLevel: String) async throws {
        let sess = try await requireSession()
        let pref = SharingPrefRow(userId: try await currentUserId(), kind: kind, targetId: targetId, detailLevel: detailLevel)
        let body = try isoEncoder.encode(pref)
        try await send(method: "POST", table: "sharing_prefs",
                       query: [URLQueryItem(name: "on_conflict", value: "user_id,kind,target_id")],
                       body: body, sess: sess)
    }

    /// Formats a `Date` as an ISO-8601 string for use as a PostgREST query-param
    /// filter value (e.g. `start_at=gte.<iso-string>`). Mirrors `ReferenceRow`'s
    /// `isoString(from:)` formatter convention.
    private func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    // MARK: Spaces / Projects

    public func upsertSpace(_ s: Space, sort: Int = 0) async throws {
        let sess = try await requireSession()
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
        let sess = try await requireSession()
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
        let sess = try await requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = TaskRow(domain: t)
        row.userId = userId
        if row.createdBy == nil { row.createdBy = userId }
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "tasks",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteTask(id: UUID) async throws {
        let sess = try await requireSession()
        try await send(method: "DELETE", table: "tasks",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    /// Flips a task's done state via a scoped PATCH — done/completed_at only, so a
    /// check-off never stomps a collaborator's concurrent edit to the row's other
    /// columns (the same reasoning as `claimTask` below). Explicit JSON so
    /// `completed_at` is written as NULL on un-check rather than omitted.
    ///
    /// Returns whether a row matched: a PATCH on a row that never landed (an
    /// earlier offline upsert was swallowed) "succeeds" against zero rows —
    /// callers fall back to a full upsert so the completion isn't silently lost.
    @discardableResult
    public func setTaskDone(id: UUID, done: Bool, completedAt: Date?) async throws -> Bool {
        let sess = try await requireSession()
        let payload: [String: Any] = [
            "done": done,
            "completed_at": completedAt.map { Self.isoFormatter.string(from: $0) } ?? NSNull()
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(method: "PATCH", table: "tasks",
                                  query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                                  extraHeaders: ["Prefer": "return=representation"],
                                  body: body, sess: sess)
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        return !(rows?.isEmpty ?? true)
    }

    /// Shared by the hand-built JSON writers (thread-safe per Apple docs).
    private static let isoFormatter = ISO8601DateFormatter()

    /// Claims a shared task for the caller WITHOUT touching `user_id`/`project_id` —
    /// unlike `upsertTask` (which stamps the caller as owner and has no project_id
    /// support yet), claiming must only ever change who the task is assigned to.
    /// Routing claims through `upsertTask` would silently reassign task ownership
    /// and wipe its project linkage — this scoped PATCH avoids both.
    public func claimTask(id: UUID, assigneeId: UUID) async throws {
        let sess = try await requireSession()
        let body = try JSONSerialization.data(withJSONObject: ["assignee_id": assigneeId.uuidString])
        try await send(method: "PATCH", table: "tasks",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       body: body, sess: sess)
    }

    /// Retroactively files every already-imported Canvas item of `course` under a
    /// class: a scoped PATCH of `project_id` + `space_name` on both tables, filtered
    /// to `canvas_course = course` (RLS scopes it to the caller's rows). Runs ONLY at
    /// the user's explicit link action in the class picker — the sync runner never
    /// auto-moves items (its updates stay user-data-safe), so a user's own re-filing
    /// is only ever overridden by this deliberate link. Feed-owned `canvas_course`
    /// itself is untouched, so a later re-sync still recognizes the course.
    public func remapCanvasCourse(_ course: String, toProject projectId: UUID, spaceName: String) async throws {
        let sess = try await requireSession()
        let payload: [String: Any] = ["project_id": projectId.uuidString, "space_name": spaceName]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let filter = [URLQueryItem(name: "canvas_course", value: "eq.\(course)")]
        try await send(method: "PATCH", table: "tasks",  query: filter, body: body, sess: sess)
        try await send(method: "PATCH", table: "events", query: filter, body: body, sess: sess)
    }

    // MARK: Events

    public func upsertEvent(_ e: CalendarEvent) async throws {
        let sess = try await requireSession()
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
        let sess = try await requireSession()
        try await send(method: "DELETE", table: "events",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    // MARK: Notes / Goals

    public func upsertNote(_ n: Note) async throws {
        let sess = try await requireSession()
        guard let userId = UUID(uuidString: sess.user.id) else {
            throw AtlasDBError.requestFailed(0, "Malformed user UUID: \(sess.user.id)")
        }
        var row = NoteRow(domain: n)
        row.userId = userId
        let body = try isoEncoder.encode(row)
        try await send(method: "POST", table: "notes",
                       query: upsertQuery, extraHeaders: upsertHeaders, body: body, sess: sess)
    }

    public func deleteNote(id: UUID) async throws {
        let sess = try await requireSession()
        try await send(method: "DELETE", table: "notes",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    public func upsertGoal(_ g: Goal) async throws {
        let sess = try await requireSession()
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
        let sess = try await requireSession()
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
        let sess = try await requireSession()
        try await send(method: "DELETE", table: "project_references",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
                       extraHeaders: ["Prefer": "return=minimal"],
                       sess: sess)
    }

    public func upsertReferenceAttachment(_ a: ReferenceAttachment) async throws {
        let sess = try await requireSession()
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
        let sess = try await requireSession()
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
