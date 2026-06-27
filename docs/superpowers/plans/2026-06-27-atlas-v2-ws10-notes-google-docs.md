# WS-10 — Notes ↔ Google Docs (constrained editor + two-way sync scaffold)

**Date:** 2026-06-27
**Branch:** `feat/daily-driver-v1`
**Spec:** `docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md` §4 WS-10

## Goal
Constrained native rich-text notes editor whose ONLY styling is Heading /
Sub-heading / Normal block levels + bold/italic/underline inline + bulleted/
numbered lists. Two-way sync with a backing Google Doc (Doc = styling master).
Live Google calls need human consent → SCAFFOLD + unit-test; reuse WS-5's
`GoogleAuthService`.

## Pieces

### 1. `Atlas/Models/RichDoc.swift` — internal document model (TDD)
- `RichDoc { blocks: [Block] }`.
- `BlockKind`: `.heading .subheading .normal .bulleted .numbered` (`.isList`).
- `InlineMarks` OptionSet: `.bold .italic .underline` (manual Codable).
- `Run { text, marks }`, `Block { id, kind, runs }`.
- Ops (unit-tested): `fromPlainText`/`plainText` round-trip; `setKind`;
  `toggleListKind` (set-or-revert-to-normal); range/full `toggleMark` with run
  split + merge (`buildRuns`); `uniformMarks`; `setText`; `normalize`.
- Tests: `AtlasTests/RichDocTests.swift`.

### 2. `Atlas/Services/GoogleDocsService.swift` — mapping + scaffold service
- `GoogleDocsMapper` (pure, tested):
  - `decodeDocument(from: Data) -> RichDoc` — Google `documents.get` JSON →
    RichDoc (namedStyleType HEADING_1/2 → heading/subheading; `bullet`+`lists`
    glyphType → numbered vs bulleted; textRun bold/italic/underline → marks).
  - `encodeDocument(_:) -> Data` — symmetric RichDoc → document JSON.
  - `batchUpdateBody(for:) -> Data` — real write payload (insert + style
    requests), structurally tested.
- `GoogleDocsService` (scaffold, no live calls): `createDoc(title:)` (Drive
  files.create), `fetchDoc(documentId:)` (Docs get → decode), `pushDoc(...)`
  (batchUpdate). All gated by `GoogleAuthService.validAccessToken()`; no-op until
  connected. Mirrors `GoogleCalendarService`.
- `NoteSync.reconcile(local:localModified:remote:remoteModified:)` pure
  last-write reconciler → `.inSync/.useLocal/.useRemote/.conflict`
  (ambiguous → conflict so a side is never silently lost).
- Tests: `AtlasTests/GoogleDocsMapperTests.swift` (both directions, fixtures,
  round-trip, reconcile).

### 3. Backing model + scopes
- `Note`: add `var googleDocId: String? = nil` (+ `var docSyncedAt: Date? = nil`).
- `NoteRow`: add `googleDocId` ↔ `google_doc_id`; wire `init(domain:)`/`toDomain()`.
- Extend `testNoteRowRoundTrip`.
- `GoogleOAuthConfig.scopes`: add `documents` + `drive.file`; update the WS-5
  scope test (`testScopesConfiguredForCalendarEvents`).

### 4. `Atlas/Views/Notes/NoteEditorView.swift` — constrained editor (build-verified)
- Rewrite as a focused view over `RichDoc`, keeping `init(note:onDone:)` so
  existing call sites (CommandPalette, NotesListView) keep compiling.
- Title field + block list; per-focused-block level picker
  (Heading/Sub-heading/Normal/Bulleted/Numbered) + B/I/U toggles; add/delete
  block. Each level uses custom AtlasTheme typography.
- Commit: write `doc.plainText` → `note.body` (keeps ⌘K search/[[mentions]]),
  `state.updateNote`. Doc push wired but not invoked live (needs consent).

## Green-tree discipline
Build + `xcodebuild test` after each step. `xcodegen generate` after new files.
DB note: `google_doc_id` column must be added to the Supabase `notes` table
before live persistence works (needsUser).

## Manual / needsUser
- Same Google consent as WS-5 + add `documents`/`drive.file` under Data Access.
- Add `google_doc_id text` (and optional `doc_synced_at timestamptz`) column to
  the `notes` table.
