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

// MARK: - Doc tabs (multi-tab Google Doc notes)

/// One tab of a multi-tab Google Doc note. Mirrors `doc_note_tabs`.
/// `writable == false` ⇒ the tab contains content Atlas can't safely rewrite
/// (table, image, exotic formatting — `readonlyReason`); the editor shows it
/// read-only and the server refuses writes to it regardless.
public struct DocNoteTab: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let referenceID: UUID
    public let tabId: String
    public let parentTabId: String?
    public let title: String
    public let ord: Int
    public let bodyMD: String
    public let writable: Bool
    public let readonlyReason: String?
    /// Advisory: a cosmetic inline style (text color, highlight, strikethrough,
    /// small caps, super/subscript) was stripped from this tab on import. The tab
    /// stays writable; the styling survives in Google unless the tab is edited
    /// and saved in Atlas. Drives a non-blocking info banner in the editor.
    public let droppedStyling: Bool

    public init(id: UUID, referenceID: UUID, tabId: String, parentTabId: String?,
                title: String, ord: Int, bodyMD: String, writable: Bool, readonlyReason: String?,
                droppedStyling: Bool = false) {
        self.id = id
        self.referenceID = referenceID
        self.tabId = tabId
        self.parentTabId = parentTabId
        self.title = title
        self.ord = ord
        self.bodyMD = bodyMD
        self.writable = writable
        self.readonlyReason = readonlyReason
        self.droppedStyling = droppedStyling
    }

    /// "Parent ▸ Child" for nested tabs, matching the Docs sidebar.
    public func displayTitle(in tabs: [DocNoteTab]) -> String {
        guard let parentTabId, let parent = tabs.first(where: { $0.tabId == parentTabId }) else {
            return title
        }
        return "\(parent.title) ▸ \(title)"
    }
}

// MARK: - Doc images (re-hosted inline Google Doc images)

/// One re-hosted inline image of a Doc note. Mirrors `doc_note_images` (migration
/// `0023`). The pull pipeline downloads the Doc's image bytes into the private
/// `doc-images` Storage bucket while the Docs `contentUri` is still fresh, records
/// this row, and rewrites the tab's Markdown with a `![image:<objectId>]` placeholder
/// line. The editor renders it from `storagePath`; write-back re-inserts it at the
/// preserved size. `cropLocked == true` ⇒ the image carries a crop/rotation/adjustment
/// the dialect can't round-trip, so its tab stays read-only.
public struct DocNoteImage: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let noteID: UUID
    public let tabId: String
    public let objectId: String
    public let storagePath: String
    public let widthPt: Double?
    public let heightPt: Double?
    public let cropLocked: Bool

    public init(id: UUID, noteID: UUID, tabId: String, objectId: String,
                storagePath: String, widthPt: Double?, heightPt: Double?, cropLocked: Bool) {
        self.id = id
        self.noteID = noteID
        self.tabId = tabId
        self.objectId = objectId
        self.storagePath = storagePath
        self.widthPt = widthPt
        self.heightPt = heightPt
        self.cropLocked = cropLocked
    }
}
