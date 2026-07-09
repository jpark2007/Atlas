# Docs → Notes import — design (2026-07-03)

Import Google Drive files into Atlas as project-scoped **references**, with Google Docs
becoming two-way-editable notes. Decisions settled with Drew 2026-07-03 (Jonah agreed to
the feature); built on `feat/notes-import`, on top of the editorial-light reskin.

## Decisions (locked)

- **Scope: `drive.file`** — non-sensitive, no CASA, no 100-user cap, publishable now.
  Files gain access ONLY via the app's own Google Picker (URL-paste cannot grant access).
  Upgrade path to `drive.readonly` folder-watch stays open for the Gmail/CASA era.
- **Model: linked, re-syncable.** Note remembers its Drive fileId; server re-pulls on cron.
- **Runner: Supabase pg_cron + edge function** — same rails as calendar/Canvas (~15 min tick).
- **Two-way for Google Docs.** Read: Doc → Markdown (Drive `files.export`, `text/markdown`)
  → RichDoc. Write: RichDoc → Markdown → Drive `files.update` with conversion back to Doc.
  **Fidelity contract:** an Atlas save rewrites the Doc from Markdown — comments/suggestions/
  formatting beyond RichDoc's vocabulary do not survive. Docs revision history is the net.
  **Staleness guard:** before write-back, compare stored `modifiedTime` to Drive's current;
  on mismatch never blind-overwrite — surface "changed in Google: refresh or overwrite".
- **Everything importable.** Docs → editable notes. Everything else (PDF, images, Sheets,
  Slides, …) → **view-only file references**: QuickLook preview in-app, "Open in Drive" out.
  Bytes stay in Drive — Atlas stores fileId + metadata and caches previews locally.
- **Link references:** external URLs (YouTube, articles) attach the same way — title + URL,
  one reference pool per project with three flavors: doc-note / file / link.
- **Project-scoped:** import happens from inside a project; references tag to that project.
  Tasks and events can attach any reference from their project's pool — at creation and on
  detail pages.
- **Placeholder purge:** remove MockData-era fake notes/links/attachments. (What replaces
  them for new users = the onboarding-templates question — explicitly OUT of scope here,
  being designed separately.)

## UI placement

- **ProjectDetailView:** a References section — editorial rows (hairline-separated), one row
  per reference with type glyph (doc/file/link), source badge for linked Docs, sync-state.
  Actions: "Import from Drive" (picker flow) and "Add link".
- **NoteEditorView:** editing a linked Doc-note shows a subtle linked badge + last-synced;
  save triggers write-back with the staleness guard; "Open in Google Docs" escape hatch.
- **Task/event detail (+ creation sheets):** "Add reference" → picker over the project pool.
- **NotesListView:** linked notes show the Doc badge; otherwise identical to native notes.

## Server flow

1. **Scope add:** `drive.file` appended to the existing Google OAuth request; user re-consents
   once (testing-mode consent already covers non-sensitive scope additions).
2. **Picker:** server-hosted picker page (pattern proven in
   `docs/experiments/picker-folder-cascade-test.html`), launched from the Mac app like the
   existing connect flows; picked fileIds POST to an edge function that registers references.
3. **Pull cron:** per linked Doc, compare `modifiedTime`; changed → export Markdown → update
   note content + `modifiedTime` in DB. Non-Doc references refresh metadata only.
4. **Write-back:** edge function takes note Markdown + expected `modifiedTime`; performs the
   guard check; converts Markdown → Doc via Drive update-with-conversion.
5. **Migrations additive only** — no destructive SQL against the production DB; anything
   non-additive becomes a reported manual step, not an executed one.

## Out of scope

Onboarding templates (separate design pass), mobile notes UI (glance app stays glance),
`drive.readonly` folder-watch (Gmail/CASA era), Sheets/Slides content rendering (preview only).

## Manual steps reserved for Drew

Google re-consent with the new scope; E2E with his real Drive; visual pass on all new UI.
