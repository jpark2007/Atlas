import Foundation

/// A project-scoped **reference** — the unit imported into a project from Google
/// Drive (or pasted as a link). One reference pool per project, with three flavors:
///
///   • `.docNote` — a linked Google Doc that backs an editable Atlas `Note`
///     (two-way: Doc ⇄ Markdown ⇄ `RichDoc` on the sync cron). `noteID` points at
///     the `Note` whose body it drives; `driveFileId` is the Doc.
///   • `.file`    — a view-only Drive file (PDF, image, Sheet, Slide…). Bytes stay
///     in Drive; Atlas keeps `driveFileId` + metadata and previews via QuickLook.
///   • `.link`    — an external URL (YouTube, article): just `title` + `url`.
///
/// The kind is stamped ONCE at import — never inferred later from other fields
/// (mirrors `EventSource`'s attribution rule).
public enum ReferenceKind: String, Codable, CaseIterable {
    case docNote = "doc_note"
    case file
    case link
}

/// Where a reference stands relative to its Drive source. Drives the row's sync
/// badge. The write-back staleness guard compares the stored `modifiedTime` to
/// Drive's current value before overwriting a Doc (see the design doc).
public enum ReferenceSyncState: String, Codable, CaseIterable {
    case pending   // imported, not yet pulled by the cron
    case synced    // content/metadata matches Drive as of `lastSyncedAt`
    case stale     // Drive moved past our copy — needs a refresh before write-back
    case error     // last sync failed (see the connection's `last_error`)
}

/// The source of truth for one imported reference. Persisted in `project_references`.
public struct Reference: Identifiable {
    public var id = UUID()
    /// The project whose pool this reference belongs to. References are ALWAYS
    /// project-scoped — import happens from inside a project.
    public var projectID: UUID
    public var kind: ReferenceKind
    public var title: String
    /// `.link`: the external URL. `nil` for Drive-backed references.
    public var url: String?
    /// `.docNote`/`.file`: the backing Drive file id. `nil` for `.link`.
    public var driveFileId: String?
    /// `.docNote`/`.file`: the Drive mimeType (e.g. `application/vnd.google-apps.document`,
    /// `application/pdf`) — drives the type glyph and the Doc-vs-file routing.
    public var mimeType: String?
    /// Drive's `modifiedTime` as of the last successful pull — the baseline the
    /// write-back staleness guard compares against. `nil` until first synced.
    public var modifiedTime: Date?
    /// When Atlas last reconciled this reference with Drive.
    public var lastSyncedAt: Date?
    public var syncState: ReferenceSyncState
    /// `.docNote`: the Atlas `Note` this Doc backs (its editable body). `nil` for
    /// `.file`/`.link`.
    public var noteID: UUID?

    public init(id: UUID = UUID(),
                projectID: UUID,
                kind: ReferenceKind,
                title: String,
                url: String? = nil,
                driveFileId: String? = nil,
                mimeType: String? = nil,
                modifiedTime: Date? = nil,
                lastSyncedAt: Date? = nil,
                syncState: ReferenceSyncState = .pending,
                noteID: UUID? = nil) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.title = title
        self.url = url
        self.driveFileId = driveFileId
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.lastSyncedAt = lastSyncedAt
        self.syncState = syncState
        self.noteID = noteID
    }
}

/// Attaches a `Reference` from a project's pool to a task or an event. Exactly one
/// of `taskID` / `eventID` is set. A reference can be attached to many items and an
/// item to many references (many-to-many) — modeled as a join row, unlike the
/// single-tag `noteID` on `TaskItem` / `CalendarEvent`.
public struct ReferenceAttachment: Identifiable {
    public var id = UUID()
    public var referenceID: UUID
    /// Set when this attachment targets a task. Mutually exclusive with `eventID`.
    public var taskID: UUID?
    /// Set when this attachment targets an event. Mutually exclusive with `taskID`.
    public var eventID: UUID?

    public init(id: UUID = UUID(), referenceID: UUID, taskID: UUID? = nil, eventID: UUID? = nil) {
        self.id = id
        self.referenceID = referenceID
        self.taskID = taskID
        self.eventID = eventID
    }
}
