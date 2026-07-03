import SwiftUI
import AtlasCore

// MARK: - Reference CRUD on AppState (Docs → Notes import)
//
// `references` and `referenceAttachments` are real `@Published` stored properties
// on AppState; this extension only adds behavior (mirrors `AppState+Notes.swift`).
// Every mutation fires a write-through `Task` to Supabase via `db` — a no-op when
// offline (`db` is nil). The reference pool is per-project; tasks and events attach
// references from their project's pool through a many-to-many join.

extension AppState {

    // MARK: Pool CRUD

    /// Creates a reference, inserts it at the top of the pool, and returns it.
    /// Generic entry point behind the typed `addLink` / import helpers.
    @discardableResult
    func addReference(
        projectID: UUID,
        kind: ReferenceKind,
        title: String,
        url: String? = nil,
        driveFileId: String? = nil,
        mimeType: String? = nil,
        noteID: UUID? = nil,
        syncState: ReferenceSyncState = .pending
    ) -> Reference {
        let ref = Reference(
            projectID: projectID,
            kind: kind,
            title: title,
            url: url,
            driveFileId: driveFileId,
            mimeType: mimeType,
            syncState: syncState,
            noteID: noteID
        )
        references.insert(ref, at: 0)
        Task { try? await self.db?.upsertReference(ref) }
        return ref
    }

    /// Convenience: adds an external-URL (`.link`) reference. A link has nothing to
    /// sync, so it lands `.synced`.
    @discardableResult
    func addLink(title: String, url: String, projectID: UUID) -> Reference {
        addReference(projectID: projectID, kind: .link, title: title, url: url, syncState: .synced)
    }

    /// Syncs a reference's in-memory baseline after a successful write-back. The
    /// edge function already re-stored `modified_time` / `sync_state` on the DB row
    /// (it owns those fields), so this is an in-memory patch ONLY — no upsert — to keep
    /// the local copy from false-tripping the staleness guard on a rapid re-save.
    func markReferenceSynced(_ id: UUID, modifiedTime: Date) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].modifiedTime = modifiedTime
        references[index].syncState = .synced
        references[index].lastSyncedAt = Date()
    }

    /// Replaces an existing reference (matched by id); inserts it if no match.
    /// Used by the sync cron path and detail edits (title, sync state, modifiedTime).
    func updateReference(_ reference: Reference) {
        if let index = references.firstIndex(where: { $0.id == reference.id }) {
            references[index] = reference
        } else {
            references.insert(reference, at: 0)
        }
        Task { try? await self.db?.upsertReference(reference) }
    }

    /// Removes a reference and every local attachment pointing at it. The DB cascades
    /// the `reference_attachments` rows, so only the reference delete is sent.
    func removeReference(_ id: UUID) {
        references.removeAll { $0.id == id }
        referenceAttachments.removeAll { $0.referenceID == id }
        Task { try? await self.db?.deleteReference(id: id) }
    }

    /// The reference pool for a project, newest first (load + insert order preserve it).
    func references(in projectID: UUID) -> [Reference] {
        references.filter { $0.projectID == projectID }
    }

    /// Re-pulls the reference pool + attachments from Supabase so a browser-side Drive
    /// import surfaces without an app relaunch (the picker registers rows server-side;
    /// nothing pushes them to the client). Best-effort — a nil `db` or a failed load
    /// leaves the current state untouched. Optimistic local rows whose write-through
    /// hasn't landed yet are preserved (unioned by id), so an in-flight add/link is
    /// never dropped by a concurrent reload.
    @MainActor
    func reloadReferences() async {
        guard let db else { return }
        guard let loaded = try? await db.loadReferences() else { return }

        let serverRefIDs = Set(loaded.references.map(\.id))
        let localOnlyRefs = references.filter { !serverRefIDs.contains($0.id) }
        references = loaded.references + localOnlyRefs

        let serverAttachIDs = Set(loaded.attachments.map(\.id))
        let localOnlyAttach = referenceAttachments.filter { !serverAttachIDs.contains($0.id) }
        referenceAttachments = loaded.attachments + localOnlyAttach
    }

    // MARK: Attach / detach — tasks

    /// Attaches a pooled reference to a task (idempotent — no-op if already attached).
    @discardableResult
    func attachReference(_ referenceID: UUID, toTask taskID: UUID) -> ReferenceAttachment? {
        guard !referenceAttachments.contains(where: { $0.referenceID == referenceID && $0.taskID == taskID })
        else { return nil }
        let attachment = ReferenceAttachment(referenceID: referenceID, taskID: taskID)
        referenceAttachments.append(attachment)
        Task { try? await self.db?.upsertReferenceAttachment(attachment) }
        return attachment
    }

    /// Detaches a reference from a task.
    func detachReference(_ referenceID: UUID, fromTask taskID: UUID) {
        let removed = referenceAttachments.filter { $0.referenceID == referenceID && $0.taskID == taskID }
        referenceAttachments.removeAll { $0.referenceID == referenceID && $0.taskID == taskID }
        for attachment in removed {
            Task { try? await self.db?.deleteReferenceAttachment(id: attachment.id) }
        }
    }

    /// References attached to a task, resolved to full `Reference` objects.
    func references(forTask taskID: UUID) -> [Reference] {
        let ids = Set(referenceAttachments.filter { $0.taskID == taskID }.map(\.referenceID))
        return references.filter { ids.contains($0.id) }
    }

    // MARK: Attach / detach — events

    /// Attaches a pooled reference to an event (idempotent — no-op if already attached).
    @discardableResult
    func attachReference(_ referenceID: UUID, toEvent eventID: UUID) -> ReferenceAttachment? {
        guard !referenceAttachments.contains(where: { $0.referenceID == referenceID && $0.eventID == eventID })
        else { return nil }
        let attachment = ReferenceAttachment(referenceID: referenceID, eventID: eventID)
        referenceAttachments.append(attachment)
        Task { try? await self.db?.upsertReferenceAttachment(attachment) }
        return attachment
    }

    /// Detaches a reference from an event.
    func detachReference(_ referenceID: UUID, fromEvent eventID: UUID) {
        let removed = referenceAttachments.filter { $0.referenceID == referenceID && $0.eventID == eventID }
        referenceAttachments.removeAll { $0.referenceID == referenceID && $0.eventID == eventID }
        for attachment in removed {
            Task { try? await self.db?.deleteReferenceAttachment(id: attachment.id) }
        }
    }

    /// References attached to an event, resolved to full `Reference` objects.
    func references(forEvent eventID: UUID) -> [Reference] {
        let ids = Set(referenceAttachments.filter { $0.eventID == eventID }.map(\.referenceID))
        return references.filter { ids.contains($0.id) }
    }
}
