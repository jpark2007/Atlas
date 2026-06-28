# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume.** Where we are, what just shipped, what's
left, what you must do by hand, and the honest caveats.

_Last updated: 2026-06-28 — **v2 + a full follow-up sweep done, builds & launches, 220/220 tests green** on `feat/daily-driver-v1` (HEAD `3abccc4`). The global-hotkey crash is **FIXED**, the real logo is **MERGED**, and a relationship **graph view**, **calendar write-back wiring**, and the **notes↔project native foundation** all landed this sweep. The only un-proven surface is live Google (needs your OAuth consent)._

---

## ✅ Just shipped this sweep (all verified: build + 220 tests green)

| # | What | State |
|---|---|---|
| 1 | **⌘⇧K hotkey crash** | **FIXED** (`AtlasApp.swift`) — `GlobalHotkeyInstaller` now takes the concrete `AppState` instead of reading `@EnvironmentObject` in the escaping Carbon callback. Global capture works while Atlas runs. |
| 2 | **Real Atlas logo** | **MERGED** from `feat/brand-real-logo` — real AppIcon, in-app `AtlasMark`, menu-bar `MenuBarExtra` (Open / Quick Capture / Quit). |
| 3 | **Relationship graph** | **NEW** `Atlas/Views/Graph/GraphView.swift` — Obsidian-style force-directed Canvas map of spaces/projects/tasks/notes/events/goals, derived purely from existing relationships. Drag/pan/zoom/select. Opens from a subtle logo button on the Metrics popup, full Metrics page, and Settings (full-window overlay). `GraphSnapshot.build` is pure + unit-tested. |
| 4 | **Live dashboard date** | Hardcoded "JUNE 26" → live date kicker + time-aware greeting (driven by the published clock). |
| 5 | **Calendar write-back** | **WIRED** — `AppState` mirrors user-created events to Google on add/update/delete when connected (never external/read-only). Build-verified; **live unverified**. |
| 6 | **Notes ↔ project** | **NATIVE FOUNDATION** — `Note.projectID` (persisted), per-project NOTES section in `ProjectDetailView`, `addNote(projectID:)`/`notes(in:)`. Google Docs sync layer documented + deferred. |

---

## Where we are

**Atlas** — native SwiftUI (macOS), dark, orange `#ff8c42`. Branch **`feat/daily-driver-v1`**, HEAD **`3abccc4`**, ~37 commits ahead of `main`. Builds, launches, **220/220 tests pass**. AI capture is live. Real logo in place.

### Build / run
```bash
cd "atlas life manager"
git checkout feat/daily-driver-v1
xcodegen generate
xcodebuild test  -scheme Atlas -destination 'platform=macOS' -derivedDataPath build   # 220 tests
xcodebuild build -scheme Atlas -configuration Debug -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/Atlas.app
```
> Build to an explicit `-derivedDataPath` and launch *that* `.app`. SourceKit "Cannot find AtlasTheme / No such module XCTest" warnings are isolation noise — the real `xcodebuild` is green.

---

## What's built (v2 + this sweep, all on `feat/daily-driver-v1`)

Everything from v2 (AI capture, scheduling, ⌘K palette, projects, add-a-space, editable
empty templates, dashboard+metrics, calendar month/list, voice, donut charts) **plus** the
six items in the table above. The earlier per-area v2 detail still lives in git history /
the specs under `docs/superpowers/`.

Key services: `GoogleAuthService` (PKCE OAuth, scopes: `calendar.events`, `documents`,
`drive.file`), `GoogleCalendarService` (read + create/update/delete), `GoogleDocsService`
(`RichDoc`↔Docs mapper, `createBackingDoc`, `fetchDoc`, `pushDoc`), `NoteSync.reconcile`
(last-write-wins, tested). See **`docs/notes-docs-sync-architecture.md`** for the
notes↔Docs model and exactly what the live layer plugs into.

---

## Manual steps — done vs. remaining

**Done ✅:** OpenRouter key set as Supabase secret · `capture` edge fn deployed (multi-item, HTTP 401 live) · `notes.google_doc_id` migration run · Google Cloud project + Calendar/Docs APIs + Desktop OAuth client created (creds in gitignored `.env.local` + `Config/Secrets.xcconfig`) · branch pushed to `origin` (jpark2007/Atlas).

**Remaining ⛳:**
1. **Google test user + consent (THE unlock):** Google Cloud → Auth Platform → Audience → Test users → add `drewkhalil@gmail.com`; then in-app Settings → Calendars → **Connect → Allow**. This is the only way to verify Calendar write-back and to build the live notes↔Docs sync.
2. **(Optional) one more `capture` redeploy** for description-aware routing: `supabase functions deploy capture`.
3. **Voice permissions:** approve mic + speech on first mic-button tap.

---

## Next work (priority order)

1. **Verify Calendar write-back live** — connect Google, create/edit/delete an Atlas event, confirm it round-trips. Then **persist `googleEventId`** (events-table column + migration) so edits patch instead of duplicating across relaunches (currently in-memory only).
2. **Notes ↔ Google Docs, live** — build the deferred layer per `docs/notes-docs-sync-architecture.md`: per-project Drive folder (`GoogleDriveService`), `createDoc(in:folder)`, adopt-existing UI, two-way polling + `reconcile` + conflict UI, persist `Note.docSyncedAt` + `projects.google_drive_folder_id`.
3. **Enrich the graph / notes hub** — note↔task links, a standalone notes hub, more graph edges.
4. **New-account onboarding = editable templates** (not the demo seed, not blank). Pattern exists (`ProjectTemplate`); make it the fresh-account default. NB: the demo seed (`MockData`) is still present for existing accounts — stripping in code only affects new/offline; clearing your own account needs a one-time Supabase reset.
5. **`⌘N` quick-note** into the current project's Drive folder (future idea).
6. **Email capture** — later.

---

## Honest caveats (what's NOT proven)

- **Live Google is unverified** — write-back is wired and notes↔project is native-only; neither has touched Google live (OAuth consent is human-only). `GoogleCalendarService`/`GoogleDocsService` are unit-tested but not exercised end-to-end.
- **`googleEventId` is in-memory** — after a relaunch, editing a previously-synced event re-creates rather than patches it on Google, until durable persistence lands (next-work #1).
- **Graph view is build-verified + unit-tested, not visually run** — the layout/gestures compile and `GraphSnapshot.build` is tested, but it hasn't been eyeballed live.
- **Voice** built but unproven at runtime (needs permission grants); this Debug build is ad-hoc signed (hardened runtime disabled).
- **Seed/mock data still present** for existing accounts (demo "Jordan" world) — cosmetic; see next-work #4.
- The real-logo branch `feat/brand-real-logo` is now merged in; it can be deleted once this lands on `main`.
