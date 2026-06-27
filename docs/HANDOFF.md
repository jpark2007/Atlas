# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume work.** Where we are, the codebase map, what you must do by hand, and what's deferred.

_Last updated: 2026-06-27 — **Daily-driver v1 built, reviewed, building green** on branch `feat/daily-driver-v1` (NOT merged/pushed). 45/45 tests pass._

---

## TL;DR — where we are

**Atlas** is a native SwiftUI (macOS-first) smart life manager. Dark, orange `#ff8c42`. All core screens + the v1 feature set are built on branch **`feat/daily-driver-v1`** (17 commits ahead of `main`):

- **Real data** — Supabase Postgres + RLS, a DTO/mapper service (`AtlasDB`), load-on-sign-in, first-run seed, write-through on every mutation. Offline mode keeps mock data.
- **AI capture** — ⌘⇧K → Supabase Edge Function (`gpt-4o-mini`) auto-sorts text into task/event/note, with a plain-task fallback so it never breaks.
- **Calendar overhaul** — redesigned week view (sticky headers, today tint, auto-scroll to now), create/edit events, tap-empty-slot, right-click menu (Edit / Change duration / Move to time / Delete), click-event → jump to source.
- **Editable hotkeys** — Settings → Shortcuts (`ShortcutStore`, live rebinding of ⌘K / ⌘⇧K).
- **Metrics** — dashboard card + full page + ⌘K popup + ⌘K "New Task/Note/Event" actions.
- **Settings → Calendars** — source toggles + main-calendar picker + EventKit (Apple Calendar) **read-only** aggregate.

Built task-by-task with an adversarial reviewer per task + a 4-dimension whole-branch review at the end (plan: `docs/superpowers/plans/2026-06-27-atlas-daily-driver-v1.md`; per-task ledger: `.superpowers/sdd/progress.md`).

### Resume / build / run
```bash
cd "atlas life manager"
git checkout feat/daily-driver-v1
xcodegen generate
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' test  CODE_SIGNING_ALLOWED=NO   # 45 tests
```
> ⚠️ **Run a clean, known build before launching.** There are several stale `Atlas.app` copies in DerivedData; `open`-ing "the newest" can grab an OLD binary (this bit us — an old build with no Focus/Metrics/profile rows looked like a regression). Build with an explicit `-derivedDataPath ./.build-run` and launch *that* `.../Build/Products/Debug/Atlas.app`.

> ⚠️ **SourceKit lies** in this single-module XcodeGen setup ("Cannot find type X in scope" everywhere). These are FALSE. Trust `xcodebuild` only.

---

## Codebase structure (current)

`project.yml` globs all `Atlas/**.swift` + `AtlasTests/**` — new files need NO project edits, just `xcodegen generate`. `supabase/` lives outside the Xcode target.

```
Atlas/
  App/
    AtlasApp.swift            AppGate (loading/signedOut/signedIn/offline) — builds AtlasDB + bootstraps on sign-in; injects AppState/AuthService/CanvasService/ShortcutStore
    RootView.swift            Route enum (dashboard/calendar/focus/metrics/project) + split view + sheets (Settings, Metrics popup, Event editor)
    WindowConfigurator.swift  hides the window toolbar (the gray-bar fix)
  Config/
    SupabaseConfig.swift      project URL + anon key + authBase / restBase / functionsBase
  Services/
    SupabaseAuth.swift        GoTrue over URLSession (email + Apple id_token + Google PKCE)
    AuthService.swift         session restore/persist, state machine, displayName
    AtlasDB.swift             ★ PostgREST CRUD + Row DTOs/mappers (Color never persisted; ids preserved) + ColorToken
    AtlasAI.swift             ★ POSTs capture text to the edge function; CaptureResult
    EventKitService.swift     ★ Apple Calendar READ adapter (full-access request + range fetch → read-only CalendarEvents)
    CanvasService.swift       Canvas host+token (validates); token in UserDefaults (TODO: Keychain)
    ShortcutStore.swift       ★ @AppStorage-backed editable keyboard shortcuts (capture/search)
  DesignSystem/
    Theme.swift               AtlasTheme (Colors incl. accent/warning/danger/bgDeep, Font, Radius) + AtlasCard
  Models/
    Models.swift              Space, Project, CalendarEvent (+notes/isAllDay/projectID/isReadOnly), TaskItem, TaskStatus, Note, Goal — all `var id` (NOT Codable; DTOs handle persistence)
  Data/
    AppState.swift            the store: @Published spaces/events/tasks/notes/goals + UI flags + externalEvents; bootstrap() + write-through; addEvent/updateEvent/deleteEvent/addGoal/updateGoal
    AppState+Calendar.swift   calendarSpaceColor(named:), events(on:) etc.
    AppState+Notes.swift      addNote/updateNote
    Metrics.swift             ★ pure AtlasMetrics.compute(...) (honest, derivable-only metrics)
    MockData.swift            the seed: 3 spaces, 6 projects (1 rich), 5 events, 5 tasks, 3 notes, 3 goals
  Views/
    Sidebar/SidebarView.swift     nav rows (Dashboard/Calendar/Focus/Metrics) + profile row → Settings
    Dashboard/DashboardView.swift schedule/tasks/focus/goals + MetricsCard
    Calendar/                     CalendarView, TimeGridView, CalendarModels, UnscheduledTray,
                                  ★WeekColumnHeader, ★AllDayRowView, ★EventEditorSheet, ★EventContextMenuModifier
    Focus/                        FocusView, FocusViewModel (Pomodoro)
    Capture/CaptureOverlay.swift  ⌘⇧K quick-capture → AtlasAI (+ fallback)
    Search/CommandPalette.swift   ⌘K palette + quick actions (Open Metrics, New Task/Note/Event)
    Notes/                        NoteEditorView, NotesListView, NoteMentions ([[wikilinks]])
    Project/ProjectDetailView.swift
    Metrics/                      ★MetricsCard, ★MetricsView (route), ★MetricsPopupView
    Auth/                         SignInView (gate + continue-offline), SettingsView (Account/Canvas/Shortcuts/Calendars)
AtlasTests/                       AtlasDBMappingTests, AtlasAIDecodeTests, MetricsTests, ShortcutStoreTests, (smoke) — 45 tests
supabase/
  migrations/0001_init.sql        ★ tables + RLS (run in the SQL editor)
  functions/capture/index.ts      ★ Deno edge function (deploy via Supabase CLI)
docs/
  atlas-vision.md, specs/01..10, SETUP.md, HANDOFF.md (this file)
  superpowers/plans/2026-06-27-atlas-daily-driver-v1.md   the executed implementation plan
```
★ = added in the Daily-driver v1 build.

---

## Manual steps for YOU (human)

Done ✅: Supabase project + URL/anon key in app · Confirm-email OFF · `OPENROUTER_API_KEY` secret added · **`0001_init.sql` run** (per user, 2026-06-27).

Still needed:
- **Deploy the AI function:** `supabase functions deploy capture` + confirm `OPENROUTER_API_KEY` is a Function secret. *(Until then ⌘⇧K cleanly falls back to a plain task.)*
- **Apple / Google sign-in:** Supabase → Auth → Providers config (Apple needs the Xcode "Sign in with Apple" capability + signing). Email sign-in already works.
- **Apple Calendar aggregate:** grant calendar access at the macOS prompt when you toggle it on in Settings → Calendars.

---

## Verification status

- **Build + 45 unit tests:** green (authoritative `xcodebuild test`).
- **Reviewed:** every task individually + a final 4-dimension whole-branch review (1 Critical + 6 Important found and fixed; e.g. a right-click ghost-duplicate on scheduled-task tiles).
- **Pending live/manual checks (need YOU):** email sign-in → per-user persistence (now that SQL is run); ⌘K palette opens in the *fresh* build; ⌘⇧K after the function is deployed; Apple Calendar toggle after granting access. (Visual screenshot verification couldn't be automated — it captures the real screen.)

---

## Deferred to v2 (intentional, not bugs)
Google/Canvas calendar fetch + write-back · EventKit write-back · global system-wide hotkey · social (friends/shared spaces) · email capture (Gmail→AI) · iOS target · Drive folders.
Known hardening/edges: move the Canvas token to Keychain; a bootstrap-clobber edge case (an item added during the very first load reappears on next reload); Day-mode all-day events have no strip yet (week mode does).

---

## Architecture recap
Native SwiftUI, macOS-first. All UI talks to `AppState`; persistence is a DTO layer in `AtlasDB` so domain models stay clean (Color re-derived from `spaceName`, never persisted). Auth = Supabase GoTrue via URLSession. AI = OpenRouter `gpt-4o-mini` behind a Supabase Edge Function (key server-side only). `.gitignore` blocks secrets, the generated `.xcodeproj`, `.build-run/`, and `.superpowers/`.
```
