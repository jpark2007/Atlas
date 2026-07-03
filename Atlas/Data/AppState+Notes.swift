import SwiftUI
import AtlasCore

// MARK: - Note CRUD on AppState
//
// `notes` and `presentSearch` are real `@Published` stored properties on
// AppState (Stage 0). This extension only adds behavior — no stored properties.

extension AppState {
    /// Creates a note, inserts it at the top of the list, and returns it.
    @discardableResult
    func addNote(
        title: String = "Untitled note",
        body: String = "",
        spaceName: String? = nil,
        projectID: UUID? = nil,
        isExternal: Bool = false
    ) -> Note {
        let note = Note(
            title: title,
            body: body,
            spaceName: spaceName,
            projectID: projectID,
            updatedAt: Date(),
            isExternal: isExternal
        )
        notes.insert(note, at: 0)
        Task { try? await self.db?.upsertNote(note) }
        return note
    }

    /// Notes attached to a given project, newest first. Backs the per-project
    /// Notes section in `ProjectDetailView` (WS-10 native linking).
    func notes(in projectID: UUID) -> [Note] {
        notes.filter { $0.projectID == projectID }
             .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Replaces an existing note (matched by id), refreshing `updatedAt`.
    /// Inserts it if no match exists.
    func updateNote(_ note: Note) {
        var updated = note
        updated.updatedAt = Date()
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = updated
        } else {
            notes.insert(updated, at: 0)
        }
        Task { try? await self.db?.upsertNote(updated) }
    }
}
