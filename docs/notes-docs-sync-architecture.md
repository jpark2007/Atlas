# Notes ↔ Google Docs — architecture (how it's wired & what's deferred)

> ⚠️ **OPEN DECISION — read this first, then ask the user.**
> This doc describes the *target* model, but the **Drive scope** that makes it possible is an
> **unresolved decision** (pending partner review, 2026-06-29). The "folder per project, see the
> Docs inside" model below works cleanly on `drive.file` only for Atlas-created notes; auto-seeing
> pre-existing/Google-side files needs a **restricted scope + audit**. Before wiring the live Google
> layer, read **[notes-drive-architecture-decision.md](./notes-drive-architecture-decision.md)** and
> **ask the user which path (A `drive.file` / B `drive.readonly` / C per-org Workspace) to build.**

The model Atlas is building toward: **a Google Drive folder per class/project; each
note is a Google Doc inside that folder; write in Docs (e.g. during class) or in
Atlas and both stay in sync.** This doc captures the structure so the live Google
layer can be dropped in cleanly. Status as of 2026-06-28.

## Native foundation — DONE (build-verified, no Google needed)

- **`Note.projectID: UUID?`** (`Atlas/Models/Models.swift`) — a note belongs to a
  project. Persisted: the `notes.project_id` column already existed; `NoteRow`
  now maps it (was hardcoded `nil`).
- **`AppState.addNote(…, projectID:)`** + **`AppState.notes(in:)`**
  (`Atlas/Data/AppState+Notes.swift`) — create project-linked notes; fetch a
  project's notes newest-first.
- **Project detail "NOTES" section** (`Atlas/Views/Project/ProjectDetailView.swift`)
  — lists the project's notes, "New" opens the editor pre-linked to the project.
  A note with a `googleDocId` renders a "Doc ↗" affordance.
- **Editor**: `NoteEditorView` over the constrained `RichDoc`; `GoogleDocsMapper`
  (RichDoc ↔ Docs JSON) and `NoteSync.reconcile` (last-write-wins) are already
  built and unit-tested.

## The mapping (target)

```
Space  ─┐
        ├─ Project ──▶ Drive folder  "Atlas / <Space> / <Project>"
        │                 ├─ Doc  ◀──▶  Note (Note.googleDocId)
        │                 ├─ Doc  ◀──▶  Note
Note.projectID ───────────┘   (each note's backing Doc lives in its project folder)
```

- `Note.googleDocId` links a note to its Doc (exists).
- A new field per Project for the **Drive folder id** is the main missing piece of
  persistence (see Deferred). Until then the folder is resolved by name on demand.

## Deferred to the live-Google session (needs OAuth consent — human-only)

1. **`GoogleDriveService` folder ops** — find-or-create the per-project folder
   (`drive.files.create` with `mimeType application/vnd.google-apps.folder`,
   `parents` = an "Atlas" root folder), and `createDoc(title:inFolder:)`.
   `GoogleDocsService.createBackingDoc` currently makes a *loose* Doc; give it a
   `parents:[folderId]`.
2. **Persist the folder id** — add `projects.google_drive_folder_id` (migration) so
   we don't re-resolve by name each launch.
3. **Adopt existing** — UI to paste a Doc URL/id and attach it to a note
   (`drive.file` scope only sees app-created files; adopting arbitrary user Docs
   may need a broader scope or a Drive picker).
4. **Two-way sync loop** — poll Drive for `modifiedTime` (or Drive Activity API),
   call `NoteSync.reconcile(local:remote:)`, surface `.conflict` in UI. Persist
   `Note.docSyncedAt` (migration) to drive ordering.
5. **`⌘N` quick-note** (future idea) — create a note in the current project's
   linked Drive folder in one keystroke.

## Why deferred

None of the Drive/Docs network paths can be verified without live OAuth consent,
which only the account owner can grant. Building them blind risks rework once
tested live, so the native structure lands first and the live layer plugs into it.
