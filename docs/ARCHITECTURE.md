# Atlas — Architecture

Current-state map of how Atlas is actually built, as of 2026-07-08. This describes what
exists in the code today, not the plan — for the original stack/vision doc see
`docs/specs/01-architecture.md`; for what's still open see `docs/specs/2026-07-06-run-report.md`
(decisions D1–D8) and `docs/specs/10-roadmap.md`.

## Targets & structure

XcodeGen (`project.yml`) generates `Atlas.xcodeproj` from four targets:

- **Atlas** — the macOS app (SwiftUI, deployment target macOS 14). Sources under `Atlas/`.
- **AtlasMobile** — the iOS companion (deployment target iOS 17). Sources under `AtlasMobile/`.
- **AtlasMobileWidgets** — a WidgetKit extension embedded in AtlasMobile: home + lock-screen
  widgets and an iOS-18 capture control. Deliberately dependency-free (no AtlasCore) — it
  shares an app group with AtlasMobile through a small JSON contract (`SharedSnapshot.swift`,
  compiled into both targets).
- **AtlasTests** — macOS unit tests, depends on the Atlas target.

Both apps depend on the **AtlasCore** local Swift package (`AtlasCore/`, `Package.swift`) —
shared models and pure logic: domain types (`Models.swift`), the Supabase REST client
(`AtlasDB.swift`), the constrained rich-text note model and its Markdown dialect
(`RichDoc.swift` / `RichDocMarkdown.swift` — see below), calendar reconciliation
(`CalendarSync.swift`), and shared-project realtime subscriptions
(`RealtimeSyncService.swift`). AtlasCore's only external dependency is `supabase-swift`
(the Realtime product).

Secrets (Google OAuth client id/secret, Drive redirect URI; per-dev signing team) live in
the gitignored `Config/Secrets.xcconfig` — see `Config/Secrets.example.xcconfig`.

## Data & backend

Supabase is the backend: Postgres (clients talk to it via PostgREST), Supabase Auth,
Supabase Storage, and Vault for secrets. Schema lives in `supabase/migrations/`
(0001…0023 as of this writing). Core domain tables — spaces, projects, tasks, events,
notes, goals, pinned_resources — land in `0001_init.sql`; later migrations add
Google/Canvas connections, doc-tab storage, shared spaces, and availability.

**Storage.** One private bucket, `doc-images` (created in
`0023_doc_images_and_note_keyed_tabs.sql`), holds re-hosted copies of images pulled from
linked Google Docs, keyed `<user_id>/<note_id>/<object_id>.<ext>`; RLS restricts each user
to their own folder.

**Vault.** Google refresh tokens and Canvas Calendar-Feed URLs are stored in Supabase
Vault and never returned to any client — a client only ever sees a connection's status
("active"/"revoked"). `0007_vault_read_helper.sql` adds the service-role-only read wrapper
the sync crons use to decrypt a secret by its `vault_secret_id`.

**Edge functions** (`supabase/functions/`, Deno):
- `google-connect` — stores/rotates/revokes a user's Google refresh token in Vault.
- `google-sync` — the two-way Google Calendar + Docs-notes cron runner (pipeline (a)/(b) below).
- `canvas-connect` — stores/rotates/revokes a user's Canvas Calendar-Feed URL in Vault.
- `canvas-sync` — the Canvas ICS pull cron runner (pipeline (c) below).
- `drive-import` — serves the Google Picker page and registers picked Drive files as
  `project_references` rows.
- `drive-writeback` — pushes an Atlas note's Markdown back into its linked Google Doc,
  per tab, with a staleness guard.
- `reference-pull` — on-demand "Sync now" pull for one Doc reference, reusing the same
  pull machinery as the cron.
- `capture` — the AI quick-capture endpoint (OpenRouter, GPT-4o-mini): splits free text
  into structured task/event/note items.
- `delete-account` — service-role account deletion: purges Vault secrets, then deletes the
  auth user; every other user-scoped table cascades off `auth.users`.
- `waitlist` — public landing-page signup endpoint (deployed with `--no-verify-jwt`).
- `_shared/google_pull.ts`, `_shared/doc_tabs.ts` — shared pull/tab-conversion machinery
  reused by `google-sync`, `drive-import`, and `reference-pull` (see below).

**pg_cron.** `0008_google_sync_cron.sql` schedules `google-sync` every 5 minutes
(`*/5 * * * *`). `0012_canvas_sync.sql` schedules `canvas-sync` every 15 minutes, offset to
minutes 2/17/32/47 so its ticks never coincide with google-sync's.

## Sync pipelines

**(a) Google Calendar — two-way.** `google-sync` runs server-side (cron, above) for any
user with an active `google_connections` row: it processes tombstones first (an Atlas-side
delete replays as a Google `DELETE /events/{id}`), pulls Google → Supabase (incremental
`events.list` with a stored `sync_token`, full resync on `410 GONE`), then pushes
Supabase → Google (rows changed since `last_synced_at`). A DB-enforced unique
`(user_id, google_event_id)`, an `events.google_origin` bit, and two sync timestamps
prevent duplicates and storms. While server sync is off (or not yet connected), the Mac
falls back to a client-side pull (`CalendarView.swift`, gated by `!state.serverSyncEnabled`)
using `GoogleCalendarService` directly, sharing the same reap-on-deletion safety rules,
extracted into `CalendarSync.swift` so they're unit-testable in isolation.

**(b) Google Docs notes — per-tab, two-way.** Pull: `_shared/google_pull.ts` fetches a
linked Doc (single- or multi-tab); `_shared/doc_tabs.ts` converts each tab's Docs-API JSON
into the RichDocMarkdown dialect (the same dialect `AtlasCore/RichDocMarkdown.swift` defines
client-side) and classifies each tab writable vs. read-only from its actual content.
Multi-tab docs land one row per tab in `doc_note_tabs`, keyed by note (so one Doc imported
into several projects shares one tab set). Write-back: `drive-writeback` writes per tab,
guarded by a staleness check against the Doc's last-known `modifiedTime`. Images are
downloaded at pull time and re-hosted into the `doc-images` bucket so display never depends
on a live/expired Google `contentUri`; as of 2026-07-08 read-only tabs' images are re-hosted
too, and images are re-inserted on write. **FROZEN ISLANDS**, also as of 2026-07-08: tables
and non-round-trippable images no longer lock an entire tab — they render read-only in
place (`!>`-marked lines, rendered by `DocTabContentViews.swift`) while the rest of the tab
stays editable; the write path splices new content only into the gaps between islands.
Table *editing* (vs. read-only display) is on the roadmap — see
`docs/specs/2026-07-08-table-editing-roadmap.md`.

**(c) Canvas — ICS, read-only.** `canvas-sync` (cron, above) does a conditional GET
(If-None-Match/If-Modified-Since) of each connected user's Canvas Calendar-Feed URL,
parses the ICS, and upserts by `(user_id, canvas_uid)`: assignment-style VEVENTs become
tasks (due date = DTSTART), everything else becomes events. There is no push path — Canvas
is never written to — and an item vanishing from the feed is not treated as a deletion
(Canvas hides past items routinely), so rows are never reaped.

## Client architecture

`AppState` (`Atlas/Data/AppState.swift` plus `AppState+Calendar/Canvas/Capture/Notes/
References.swift` extensions) is the app's single `@MainActor` store — `@Published` arrays
of spaces, projects, tasks, events, notes, goals, and references. It bootstraps by loading a
full snapshot through `AtlasDB` (the Supabase REST/PostgREST client layer in AtlasCore); a
first-run account with no spaces gets seeded from `MockData`'s templates — editable starting
content, not a permanent demo. `db: AtlasDB?` and `googleAuth: GoogleAuthService?` are
attached once available so write-through `Task {}` calls and Google-backed features have
what they need.

Realtime is scoped to **shared projects only**: `RealtimeSyncService` opens one Postgres
`postgres_changes` channel per shared project id and calls back on any task/event/note
change in that project; the app deliberately refetches the whole snapshot on signal rather
than hand-merging individual deltas.

Notable views: the calendar grid (`Atlas/Views/Calendar/CalendarView.swift`,
`MonthGridView.swift`, `TimeGridView.swift`) renders Apple (EventKit), Google, and
Atlas-native events side by side; the notes editor
(`Atlas/Views/Notes/NoteEditorView.swift`) edits the constrained `RichDoc` dialect block by
block, with `DocTabContentViews.swift` handling the read-only frozen-island content a
Doc-linked tab can't otherwise represent. Auth (`Atlas/Services/AuthService.swift`) wraps
Supabase Auth: email/password, Google OAuth, and Sign in with Apple.

## Key file map

- `project.yml` — XcodeGen target/scheme definitions; source of truth for the Xcode project.
- `AtlasCore/Sources/AtlasCore/Models.swift` — shared domain types (Space, Project, TaskItem, CalendarEvent, Note, …).
- `AtlasCore/Sources/AtlasCore/AtlasDB.swift` — the Supabase REST/PostgREST client and CRUD layer.
- `AtlasCore/Sources/AtlasCore/RichDoc.swift` — the constrained rich-text note model.
- `AtlasCore/Sources/AtlasCore/RichDocMarkdown.swift` — RichDoc ⇄ Markdown, the dialect shared with the server (`doc_tabs.ts`).
- `AtlasCore/Sources/AtlasCore/CalendarSync.swift` — pure Atlas ⇄ Google reconciliation/reaping rules, unit-tested in isolation.
- `AtlasCore/Sources/AtlasCore/RealtimeSyncService.swift` — shared-project Postgres realtime subscriptions.
- `Atlas/Data/AppState.swift` (+ `AppState+*.swift`) — the app's central store and bootstrap.
- `Atlas/Services/GoogleAuthService.swift`, `GoogleCalendarService.swift`, `GoogleDocsService.swift`, `GoogleDocWriteBackClient.swift` — client-side Google Calendar/Docs integration.
- `Atlas/Services/AuthService.swift` — Supabase auth (email/password, Google, Sign in with Apple).
- `Atlas/Views/Calendar/CalendarView.swift` — the unified calendar grid plus client-fallback Google pull.
- `Atlas/Views/Notes/NoteEditorView.swift`, `DocTabContentViews.swift` — the notes editor and frozen-island rendering.
- `supabase/functions/_shared/google_pull.ts`, `doc_tabs.ts` — shared Google pull and Docs-tab conversion machinery.
- `supabase/functions/google-sync/index.ts`, `canvas-sync/index.ts`, `drive-writeback/index.ts` — the cron runners and write-back function.
- `supabase/migrations/` — schema history, one file per change; the newest migration touching a table defines its current shape.

## Living docs

- `docs/SETUP.md` — how to configure and run Atlas locally.
- `docs/HANDOFF.md` — current handoff/status notes.
- `docs/atlas-vision.md` — product vision.
- `docs/specs/10-roadmap.md` — roadmap.
- `docs/specs/11-mobile-companion.md` — mobile companion design.
- `docs/specs/2026-07-06-run-report.md` — open decisions D1–D8 from the last big implementation run.
- `docs/specs/2026-07-08-table-editing-roadmap.md` — active: table editing in the notes editor.
- `docs/archive/` — superseded/shipped plans and specs, kept for history.
