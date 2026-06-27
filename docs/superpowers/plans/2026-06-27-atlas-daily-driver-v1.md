# Atlas — Daily-Driver v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks are executed **sequentially on one branch** (`feat/daily-driver-v1`) — NOT in parallel worktrees.

**Goal:** Take Atlas from "all screens built on mock data" to a daily-usable v1: real per-user Supabase persistence, AI-powered quick-capture, an overhauled calendar (week redesign + create/edit/right-click/click-to-source), editable keyboard shortcuts, a metrics view, and a Settings→Calendars sync section with an EventKit read adapter.

**Architecture:** SwiftUI macOS-first app. All UI talks to `AppState` (an `ObservableObject`). Persistence is added as a **DTO/row-mapper layer in new files** — the domain models in `Models.swift` are NOT refactored (no Codable conformance forced on them, no `id` changes, no Color persistence). A new `AtlasDB` service maps domain structs ↔ Postgres row DTOs and write-through happens inside existing `AppState` mutation methods. AI runs server-side behind a Supabase Edge Function. Offline mode keeps using `MockData` unchanged.

**Tech Stack:** Swift 5 / SwiftUI, XcodeGen (`project.yml` globs `Atlas/**`), Supabase (GoTrue auth via URLSession — already shipped; PostgREST for data; Edge Functions/Deno for AI), OpenRouter `gpt-4o-mini`, EventKit (Apple Calendar read).

## Global Constraints

- **Build verification command (the ONLY source of truth — SourceKit/IDE "Cannot find type X" errors are FALSE in this single-module XcodeGen setup):**
  `xcodegen generate && xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- **Test command (pure-logic tasks only):** `xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
- **No model refactor.** Do NOT add `Codable`/change `id`/add raw values to types in `Atlas/Models/Models.swift` for persistence. Persistence uses separate DTO structs. (Tasks MAY add *new optional fields* to a model only where the plan explicitly says so — Task 5 adds 3 optional fields to `CalendarEvent`.)
- **`Color` is never persisted.** Tasks/events/notes/projects re-derive their `Color` from `spaceName` via `AppState.calendarSpaceColor(named:)` on load. Only `Space` persists a `color_token` string.
- **New `.swift` files under `Atlas/` need NO `project.yml` edit** — just `xcodegen generate`. `supabase/` lives outside the Xcode target.
- **Theme tokens (use these verbatim, never hardcode colors):** accent `AtlasTheme.Colors.accent` (#ff8c42), `accentDeep` (#ff6b1a), `bgBase` (#16130f), `bgCard` (#1c1814), `bgElevated` (#211d18), `bgSidebar` (#1a140f), `textPrimary` (#f3ede4), `textSecondary` (#a89b8a), `textMuted` (#6f655a), `border` (white @ 0.06), `Radius.card` (14). Wrap card content in `AtlasCard { … }`. Section labels: `.font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(AtlasTheme.Colors.textMuted)`.
- **Offline-safe:** every network call must no-op gracefully when `auth.session == nil` (offline mode) — fall back to in-memory `MockData` behavior, never crash, never block the UI.
- **Secrets:** `OPENROUTER_API_KEY` is read server-side via `Deno.env.get(...)` ONLY. Never in client code. The anon key in `SupabaseConfig` is safe to ship (RLS enforces access).
- **Commit after every task** with a clear message; never amend a prior task's commit.

---

### Task 0: Foundation — all shared-state edits (SOLO, commit before any feature task)

This is the only task that edits shared files (`Route` enum, `AppState`, `SupabaseConfig`, `project.yml`, `CommandPalette`, `SidebarView`, `DashboardView`). Every later task only ADDS new files (plus narrowly-scoped write-through inside `AppState` mutation methods already listed here). Landing this first is what prevents the duplicate-model / stale-fork failures of the prior session.

**Files:**
- Modify: `Atlas/App/RootView.swift` (Route enum + switch + sheets)
- Modify: `Atlas/Data/AppState.swift` (new @Published flags + event/goal CRUD methods + load/seed hook points)
- Modify: `Atlas/Config/SupabaseConfig.swift` (functionsBase, restBase)
- Modify: `Atlas/Views/Sidebar/SidebarView.swift` (Metrics nav row)
- Modify: `Atlas/Views/Dashboard/DashboardView.swift` (MetricsCard placeholder slot)
- Modify: `Atlas/Views/Search/CommandPalette.swift` (quick-actions scaffold)
- Modify: `project.yml` (add `AtlasTests` unit-test target)
- Create: `Atlas/Views/Metrics/MetricsView.swift` + `MetricsPopupView.swift` + `MetricsCard.swift` (minimal placeholders returning `Text("Metrics")` in AtlasCard — fleshed out in Task 8)
- Create: `AtlasTests/AtlasTests.swift` (one trivial passing test to prove the target runs)

**Interfaces (Produces — later tasks rely on these exact names):**
- `Route` gains `case metrics`.
- `AppState` gains: `@Published var presentMetrics = false`, `@Published var presentCalendarSync = false`, and methods:
  - `func addEvent(_ event: CalendarEvent)` — appends to `events` (+ DB write-through hook added in Task 2)
  - `func updateEvent(_ event: CalendarEvent)` — replace by `id`
  - `func deleteEvent(id: UUID)` — `events.removeAll { $0.id == id }`
  - `func addGoal(_ goal: Goal)` / `func updateGoal(_ goal: Goal)`
- `SupabaseConfig.functionsBase` and `SupabaseConfig.restBase` (computed URLs).
- `CommandPalette` exposes a `PaletteAction` struct `{ id: String; title: String; subtitle: String; icon: String; run: () -> Void }` and renders a "Quick actions" group when `query.isEmpty` (actions wired in Tasks 5/8 — for now: "Open Metrics" → `state.presentMetrics = true`).

- [ ] **Step 1:** Add `case metrics` to `Route`, `case .metrics: MetricsView()` to the detail switch in `RootView.swift`, and two sheets alongside the existing settings sheet: `.sheet(isPresented: $state.presentMetrics) { MetricsPopupView() }` and `.sheet(isPresented: $state.presentCalendarSync) { CalendarSyncSheet() }` — **NOTE:** `CalendarSyncSheet` doesn't exist until Task 9; for now wire only `presentMetrics`; add the `presentCalendarSync` sheet line as a `// TODO Task 9` comment so the build stays green.
- [ ] **Step 2:** Add the two `@Published` flags + the five CRUD methods to `AppState.swift` (in-memory only for now — DB write-through is layered in by Task 2). Keep `addEvent/updateEvent/deleteEvent/addGoal/updateGoal` pure array mutations.
- [ ] **Step 3:** Add `functionsBase`/`restBase` to `SupabaseConfig.swift`.
- [ ] **Step 4:** Add the Metrics nav row to `SidebarView` (`navRow(title: "Metrics", icon: "chart.bar.fill", route: .metrics, trailing: nil)`), and a `MetricsCard()` placeholder into the Dashboard right-column VStack.
- [ ] **Step 5:** Add `PaletteAction` + a `quickActions` list (just "Open Metrics" for now) shown when the query is empty in `CommandPalette.swift`; add the `.action` arm to `activate()`.
- [ ] **Step 6:** Create `Atlas/Views/Metrics/` placeholders (`MetricsView`, `MetricsPopupView`, `MetricsCard` — each an `AtlasCard`/VStack stub).
- [ ] **Step 7:** Add an `AtlasTests` unit-test target to `project.yml`:
```yaml
  AtlasTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - AtlasTests
    dependencies:
      - target: Atlas
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Atlas:
    build:
      targets:
        Atlas: all
        AtlasTests: [test]
    test:
      targets:
        - AtlasTests
```
  Create `AtlasTests/AtlasTests.swift` with `import XCTest; @testable import Atlas; final class SmokeTests: XCTestCase { func testItRuns() { XCTAssertTrue(true) } }`.
- [ ] **Step 8:** `xcodegen generate` + build green + `xcodebuild ... test` green.
- [ ] **Step 9:** Commit: `feat(foundation): shared-state for metrics/calendars + event/goal CRUD + test target`.

**Verification:** build green; `test` runs the smoke test green; app launches and shows a Metrics sidebar row (clicking it shows the placeholder); ⌘K shows "Open Metrics".

---

### Task 1: Persistence backend — SQL migration + AtlasDB + DTO mappers (+ unit tests)

**Files:**
- Create: `supabase/migrations/0001_init.sql`
- Create: `Atlas/Services/AtlasDB.swift` (PostgREST client + DTO structs + domain↔DTO mappers)
- Create: `AtlasTests/AtlasDBMappingTests.swift`

**Interfaces (Produces):**
- `final class AtlasDB` with `init(session: () -> SupabaseSession?)` and async methods: `loadAll() async throws -> AtlasSnapshot`, `upsertTask(_:)`, `deleteTask(id:)`, `upsertEvent(_:)`, `deleteEvent(id:)`, `upsertNote(_:)`, `upsertGoal(_:)`, `upsertSpace(_:)`, `upsertProject(_:)`, `seedInitial(_ snapshot:)`.
- `struct AtlasSnapshot { spaces, projects, tasks, events, notes, goals }` (domain arrays).
- DTO structs (`Codable`): `SpaceRow, ProjectRow, TaskRow, EventRow, NoteRow, GoalRow` with snake_case `CodingKeys` matching the SQL columns, and `.toDomain()` / `init(domain:)` mappers.

**SQL (`0001_init.sql`) — tables each with `user_id uuid not null default auth.uid() references auth.users` + RLS `using (auth.uid() = user_id)`:**
- `spaces(id uuid pk, user_id, name text, color_token text, sort int)`
- `projects(id uuid pk, user_id, space_id uuid references spaces, name, code text, is_class bool, meeting_info text, instructor text, canvas_synced bool, overview text)`
- `tasks(id uuid pk, user_id, project_id uuid null references projects, space_name text, title, due_date timestamptz null, status text, done bool, scheduled_at timestamptz null)`
- `events(id uuid pk, user_id, space_name text, title, subtitle text, start_at timestamptz, end_at timestamptz, notes text null, is_all_day bool default false, project_id uuid null)`
- `notes(id uuid pk, user_id, space_name text null, project_id uuid null, title, body text, updated_at timestamptz, is_external bool)`
- `goals(id uuid pk, user_id, title, progress float8, label text)`
- Enable RLS on every table; policy `for all using (auth.uid() = user_id) with check (auth.uid() = user_id)`.

**Mapping rules (critical — from discovery):**
- `Color` is NOT a column. On `toDomain()`, set `color` by looking it up later (AtlasDB returns domain structs with a placeholder accent color; `AppState` re-derives via `calendarSpaceColor(named:)` after spaces load). `SpaceRow.color_token` maps to a `Color` via a small token table (`"school"→accent`, etc.) — define `ColorToken` enum in AtlasDB.swift, NOT in Models.
- `TaskStatus` (no raw value) ↔ `status text`: map with an explicit switch (`.open↔"open"`, `.dueSoon↔"due_soon"`, `.upcoming↔"upcoming"`, `.submitted↔"submitted"`).
- `TaskItem.dueLabel` (display string) is NOT persisted; `tasks.due_date` is the real date; `dueLabel` stays whatever the domain has (persisting `due_date` is forward-looking — round-trip may leave `dueLabel` empty, acceptable for v1).
- All `Date` ↔ `timestamptz`: configure `JSONEncoder/Decoder` with `.iso8601` strategy.
- PostgREST request building **mirrors `SupabaseAuth.request(...)`** exactly (apikey header = `SupabaseConfig.anonKey`, `Authorization: Bearer <accessToken>`, base `SupabaseConfig.restBase`). Use `Prefer: resolution=merge-duplicates` + `?on_conflict=id` for upserts.

- [ ] **Step 1 (test first):** In `AtlasDBMappingTests.swift`, write tests that round-trip each DTO: build a domain `TaskItem`, `TaskRow(domain:)`, encode→decode JSON, `.toDomain()`, assert title/done/status/scheduledAt survive; same for `EventRow` (start/end/title/subtitle), `NoteRow`, `GoalRow`, `SpaceRow` (name/color_token), `ProjectRow`. Assert `TaskStatus.dueSoon` ↔ `"due_soon"`.
- [ ] **Step 2:** Run test → FAIL (types don't exist).
- [ ] **Step 3:** Write `AtlasDB.swift`: DTO structs + mappers + the PostgREST client methods + `ColorToken`. (Network methods aren't unit-tested; the mappers are.)
- [ ] **Step 4:** Run tests → PASS. Build green.
- [ ] **Step 5:** Write `0001_init.sql`.
- [ ] **Step 6:** Commit: `feat(db): AtlasDB PostgREST client + DTO mappers + 0001_init.sql migration`.

**Verification:** mapping tests pass; build green. (Live DB calls verified in Task 2.)

---

### Task 2: Persistence integration — load on sign-in, write-through, first-run seed

**Files:**
- Modify: `Atlas/Data/AppState.swift` (inject `AtlasDB`, add `bootstrap()`, add write-through to mutation methods)
- Modify: `Atlas/App/AtlasApp.swift` (call `state.bootstrap()` when signed in, passing the auth session accessor)

**Interfaces (Consumes):** `AtlasDB` from Task 1, `auth.session?.accessToken` / `auth.session?.user.id` from `AuthService`.

**Behavior:**
- On sign-in (`.signedIn`), `AppState.bootstrap(db:)` runs: `loadAll()`. If the user has zero rows (first run), `seedInitial(MockData snapshot mapped to today)` then `loadAll()` again. Populate the `@Published` arrays. Re-derive every `Color` from `spaceName` via `calendarSpaceColor(named:)` after spaces are set.
- **Offline mode** (`.offline`): do NOT call `bootstrap`; keep `MockData`. Guard every write-through with `guard db != nil && session != nil`.
- Write-through: at the end of `addTask`, `toggleTask`, `schedule`, `addNote`, `updateNote`, `addEvent`, `updateEvent`, `deleteEvent`, `addGoal`, `updateGoal` — fire-and-forget a `Task { try? await db.upsertX(...) }`. UI updates optimistically first (unchanged); DB sync is async and non-blocking.

- [ ] **Step 1:** Add `private var db: AtlasDB?` and `func bootstrap(db: AtlasDB) async` to AppState; load/seed logic. Re-derive colors.
- [ ] **Step 2:** Add the async fire-and-forget write-through call to each of the 10 mutation methods listed above (do not change their synchronous in-memory behavior or signatures).
- [ ] **Step 3:** Wire `AtlasApp.swift`: on `.signedIn`, build `AtlasDB(session: { auth.session })` and `await state.bootstrap(db:)` in a `.task {}`.
- [ ] **Step 4:** `xcodegen generate` + build green.
- [ ] **Step 5:** Commit: `feat(db): wire AppState to Supabase — load on sign-in, first-run seed, write-through`.

**Verification:** Build green. Manual/screenshot: sign in → app shows data (seeded on first run); create a task → it persists (verify by checking the Supabase table OR by relaunch). Offline mode still shows MockData. **(Requires the human to have run `0001_init.sql` — note in the report if unverified live.)**

---

### Task 3: AI brain — Edge Function + AtlasAI client + wire ⌘⇧K capture

**Files:**
- Create: `supabase/functions/capture/index.ts` (Deno/TypeScript)
- Create: `Atlas/Services/AtlasAI.swift`
- Create: `AtlasTests/AtlasAIDecodeTests.swift`
- Modify: `Atlas/Views/Capture/CaptureOverlay.swift` (on submit → call AtlasAI → create object; fallback to plain task)

**Edge Function `capture/index.ts`:**
- Verify the caller's Supabase JWT (read `Authorization` header; reject if missing).
- Body `{ text: string }`. Call OpenRouter `openai/gpt-4o-mini` with a strict JSON-schema system prompt; key from `Deno.env.get("OPENROUTER_API_KEY")`.
- Return `{ kind: "task"|"event"|"note", title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes? }`. Set CORS headers; handle OPTIONS.

**AtlasAI client (`AtlasAI.swift`):**
- `struct CaptureResult: Codable { kind, title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes? }`.
- `func parse(_ text: String, session: SupabaseSession) async throws -> CaptureResult` — POST to `SupabaseConfig.functionsBase/capture`, apikey + Bearer (mirror SupabaseAuth.request).

**Capture wiring:** on submit in `CaptureOverlay`, call `AtlasAI.parse`; map `kind` → `state.addTask` / `state.addEvent` (build a CalendarEvent from startISO+durationMin, color via `calendarSpaceColor(named: spaceName)`) / `state.addNote`; show a confirmation toast naming where it went. On any error/offline → `state.addTask(title: rawText)` (plain fallback) + a subtle "saved as task" note.

- [ ] **Step 1 (test):** `AtlasAIDecodeTests` — decode a sample JSON for each `kind` into `CaptureResult`; assert fields. Run → FAIL.
- [ ] **Step 2:** Write `AtlasAI.swift` (struct + parse). Tests PASS.
- [ ] **Step 3:** Write `capture/index.ts`.
- [ ] **Step 4:** Wire `CaptureOverlay` submit (AI → create + toast; fallback to plain task). Keep offline fallback.
- [ ] **Step 5:** Build green.
- [ ] **Step 6:** Commit: `feat(ai): capture edge function + AtlasAI client + ⌘⇧K auto-sort with fallback`.

**Verification:** Build + decode tests green. Manual: ⌘⇧K "essay due Thursday" → creates a task in the right space (or plain-task fallback if function not yet deployed). **Deploy (`supabase functions deploy capture`) is the human's manual step — note in report.**

---

### Task 4: Calendar — week-view redesign

**Files:**
- Modify: `Atlas/Views/Calendar/TimeGridView.swift` (sticky gutter via ScrollViewReader, today-column tint, auto-scroll to now)
- Modify: `Atlas/Views/Calendar/CalendarModels.swift` (add `CalendarLayout.allDayRowHeight`)
- Create: `Atlas/Views/Calendar/AllDayRowView.swift` (full-width all-day strip above the grid)
- Create: `Atlas/Views/Calendar/WeekColumnHeader.swift` (extracted sticky 7-day header)

**Spec (fix the "weak" week view per discovery):** sticky weekday+date headers (weekday name + day-number badge, today's badge filled accent); today's column gets a subtle `accent.opacity(0.04)` background tint; scrollable time column that auto-scrolls to the current hour on appear (`ScrollViewReader` + `.scrollTo` near `now`); an all-day row above the grid for events where `isAllDay` (Task 5 adds the field — until then the row renders empty/0-height). Keep the existing `packEventsIntoLanes` layout for timed events. Match Theme tokens.

- [ ] **Step 1:** Add `allDayRowHeight` to `CalendarLayout`; create `AllDayRowView` + `WeekColumnHeader`.
- [ ] **Step 2:** Wire sticky header + today tint + auto-scroll-to-now into `TimeGridView`/`WeekGridView`.
- [ ] **Step 3:** Build green.
- [ ] **Step 4:** Commit: `feat(calendar): redesigned week view — sticky headers, today tint, auto-scroll, all-day row`.

**Verification:** Build green + **screenshot week view** — headers sticky, today highlighted, opens scrolled to current time.

---

### Task 5: Calendar — create & edit events (sheet + tap-empty-slot + add button)

**Files:**
- Modify: `Atlas/Models/Models.swift` — add to `CalendarEvent` ONLY: `var notes: String? = nil`, `var isAllDay: Bool = false`, `var projectID: UUID? = nil` (the one sanctioned model change; keep all existing fields + the `var id`).
- Create: `Atlas/Views/Calendar/EventEditorSheet.swift` (title, space picker, start/end or all-day, notes)
- Modify: `Atlas/Views/Calendar/TimeGridView.swift` (tap empty slot → open editor pre-filled at that time)
- Modify: `Atlas/Views/Calendar/UnscheduledTray.swift` (or `CalendarView`) — "+ Add event" affordance opening the editor

**Interfaces (Consumes):** `state.addEvent/updateEvent` from Task 0. The editor returns a `CalendarEvent`; create → `addEvent`, edit → `updateEvent`.

- [ ] **Step 1:** Add the 3 optional fields to `CalendarEvent`.
- [ ] **Step 2:** Build `EventEditorSheet` (create + edit modes). Space picker uses `state.spaces`; color derived from chosen space.
- [ ] **Step 3:** Add "+ Add event" button + tap-empty-slot (maps y→fractional hour, pre-fills start) to open the editor.
- [ ] **Step 4:** Build green.
- [ ] **Step 5:** Commit: `feat(calendar): create/edit events — editor sheet, add button, tap-empty-slot`.

**Verification:** Build green + **screenshot**: add an event via button and via tap-empty-slot; edit it; it appears on the grid in the right space color.

---

### Task 6: Calendar — right-click context menu + click-event-to-source

**Files:**
- Create: `Atlas/Views/Calendar/EventContextMenuModifier.swift` (ViewModifier: Edit, Change duration (15/30/60/90), Delete, Open source)
- Modify: `Atlas/Views/Calendar/TimeGridView.swift` (apply `.contextMenu` + `.onTapGesture` to `EventTile`)

**Spec:** Right-click an event → Edit (opens Task 5 editor), Change duration (sets `end` relative to `start`, calls `updateEvent`), Move to time…, Delete (`deleteEvent`). Left-click an event → if it originated from a task/project/note (`projectID` set, or a scheduled-task event), navigate to its source (`state.route = .project(id)` or open the note/task); generalize a single `openSource(for:)` resolver.

- [ ] **Step 1:** Create `EventContextMenuModifier` with all actions wired to `state.updateEvent/deleteEvent` + an `onEdit`/`onOpenSource` closure.
- [ ] **Step 2:** Apply it + tap-to-open-source to `EventTile`. Add an `openSource(for event:)` resolver in `CalendarView`.
- [ ] **Step 3:** Build green.
- [ ] **Step 4:** Commit: `feat(calendar): right-click context menu + click-event-to-source navigation`.

**Verification:** Build green + **screenshot**: right-click menu shows; delete removes the event; changing duration resizes the tile; clicking a class-linked event jumps to its Project.

---

### Task 7: Editable keyboard shortcuts (Settings → Shortcuts)

**Files:**
- Create: `Atlas/Services/ShortcutStore.swift` (`ObservableObject`, `@AppStorage`-backed; per-action key + modifiers; exposes `KeyEquivalent` + `EventModifiers`)
- Create: `AtlasTests/ShortcutStoreTests.swift`
- Modify: `Atlas/Views/Capture/CaptureOverlay.swift` + `Atlas/Views/Search/CommandPalette.swift` (read binding from store instead of hardcoded `"k"`)
- Modify: `Atlas/Views/Auth/SettingsView.swift` (add a "SHORTCUTS" section)
- Modify: `Atlas/App/AtlasApp.swift` or `RootView.swift` (inject `ShortcutStore` as `@StateObject`/`environmentObject`)

**Spec:** `ShortcutStore` holds bindings for actions `capture` (default ⌘⇧K) and `search` (default ⌘K), serialized to `@AppStorage` as key-char + modifier bitmask. The hidden shortcut buttons read `store.binding(for: .capture).key` / `.modifiers` so changing them updates live (SwiftUI re-evaluates body). The Shortcuts settings section lists each action with its current combo and a "Record" button (a small recorder using `.onKeyPress` to capture the next chord). Validate against duplicates. (Global system-wide hotkey is OUT of scope — note it as deferred.)

- [ ] **Step 1 (test):** `ShortcutStoreTests` — set a binding (key `"j"`, ⌘⌥), assert it serializes/deserializes and that `EventModifiers`/`KeyEquivalent` reconstruct correctly. Run → FAIL.
- [ ] **Step 2:** Write `ShortcutStore`. Tests PASS.
- [ ] **Step 3:** Inject the store; make `CaptureOverlay` + `CommandPalette` read from it.
- [ ] **Step 4:** Add the SHORTCUTS section + recorder to `SettingsView`.
- [ ] **Step 5:** Build green.
- [ ] **Step 6:** Commit: `feat(settings): user-editable keyboard shortcuts via ShortcutStore`.

**Verification:** Build + tests green + **screenshot**: Settings shows Shortcuts; rebind search to ⌘J → ⌘J opens the palette, old ⌘K no longer does.

---

### Task 8: Metrics — view, dashboard card, popup, palette actions

**Files:**
- Replace placeholders: `Atlas/Views/Metrics/MetricsView.swift`, `MetricsCard.swift`, `MetricsPopupView.swift`
- Create: `Atlas/Data/Metrics.swift` (pure aggregation: `struct AtlasMetrics` + `static func compute(from state:) -> AtlasMetrics`)
- Create: `AtlasTests/MetricsTests.swift`
- Modify: `Atlas/Views/Search/CommandPalette.swift` (add "New Task/Note/Event" quick actions next to "Open Metrics")

**Spec:** Pure `compute` derives: tasks completed today / this week, open task count, focus minutes today (from focus sessions if available, else 0), events today/this week, per-Space task load, simple completion streak. `MetricsCard` (dashboard, 320-wide): a compact "Today" summary. `MetricsPopupView`: fuller breakdown (per-Space bars, week trend). `MetricsView` (route): the full page. Palette quick actions: "New Task" (→ capture/quick add), "New Note", "New Event" (→ open EventEditorSheet), "Open Metrics".

- [ ] **Step 1 (test):** `MetricsTests` — build an `AppState` with known tasks/events, assert `AtlasMetrics.compute` returns correct counts (completed today, open count, per-space). Run → FAIL.
- [ ] **Step 2:** Write `Metrics.swift`. Tests PASS.
- [ ] **Step 3:** Flesh out `MetricsCard` + `MetricsPopupView` + `MetricsView` using the computed metrics + Theme tokens + `AtlasCard`.
- [ ] **Step 4:** Add the 3 create quick-actions to the palette.
- [ ] **Step 5:** Build green.
- [ ] **Step 6:** Commit: `feat(metrics): metrics page, dashboard card, ⌘K popup + create actions`.

**Verification:** Build + tests green + **screenshot**: Metrics route + dashboard card show real numbers; ⌘K → Open Metrics works; New Event opens the editor.

---

### Task 9: Settings → Calendars + EventKit read adapter

**Files:**
- Create: `Atlas/Services/EventKitService.swift` (request read access; fetch events in a date range → `[CalendarEvent]` tagged source=apple)
- Create: `Atlas/Views/Auth/CalendarSyncSheet.swift` OR a `calendars` section in `SettingsView.swift` (sources list + main-calendar picker + per-source toggle + default-space mapping)
- Modify: `Atlas/Views/Auth/SettingsView.swift` (add CALENDARS section; replace the static integrations placeholder)
- Modify: `Atlas/Views/Calendar/CalendarView.swift` (merge EventKit read events into the aggregate display when the Apple source is enabled, read-only)
- Modify: `Atlas/App/RootView.swift` (un-stub the Task-0 `presentCalendarSync` sheet TODO if a sheet is used)

**Spec (the sync design — aggregate-to-read, pick-one-to-write):** Settings CALENDARS section lists sources (Apple/EventKit, Google [shows "connect" — wiring deferred], Canvas, Atlas-native) each with an on/off toggle; a "Main calendar" picker (Apple/Atlas for now). EventKit adapter requests calendar access and reads events in the visible range, returned as read-only `CalendarEvent`s (distinct visual treatment, e.g. a small source glyph) merged into `filteredEvents`. No write-back this task (main-calendar write is a follow-up). Add `Info.plist` usage string `NSCalendarsUsageDescription` via `project.yml` `INFOPLIST_KEY_NSCalendarsUsageDescription`.

- [ ] **Step 1:** Add `INFOPLIST_KEY_NSCalendarsUsageDescription` to `project.yml` Atlas target.
- [ ] **Step 2:** Write `EventKitService` (access request + range fetch → `[CalendarEvent]`). Guard unavailable/denied gracefully.
- [ ] **Step 3:** Build the CALENDARS settings section (toggles + main picker + space mapping), persisted to `@AppStorage`.
- [ ] **Step 4:** Merge Apple read-events into `CalendarView` aggregate when enabled (read-only, source glyph).
- [ ] **Step 5:** Build green.
- [ ] **Step 6:** Commit: `feat(calendars): Settings→Calendars sync UI + EventKit read adapter (read-only aggregate)`.

**Verification:** Build green + **screenshot**: Settings shows Calendars with toggles + main picker; enabling Apple (after granting access) shows real Apple events in the calendar with a source glyph; disabling hides them.

---

## Final whole-branch review

After Task 9: dispatch a parallel adversarial review (workflow) across dimensions — correctness/build, persistence write-through completeness, sync-design fidelity (aggregate-read/pick-one-write), Theme/UX consistency across all screens, offline-safety, and spec alignment vs `docs/specs/`. Then a solo integration pass: `xcodegen generate`, full build, **launch + screenshot every screen** (Dashboard, Calendar day+week, Focus, Project, Metrics, Settings incl. Shortcuts + Calendars, ⌘K, ⌘⇧K), fix Critical/Important findings as ONE batched fix wave, then finish the branch.

## Self-Review notes (coverage check)
- Real data → Tasks 1–2 ✅ · AI capture → Task 3 ✅ · Week redesign → Task 4 ✅ · Add/edit events → Task 5 ✅ · Right-click + click-to-source → Task 6 ✅ · Editable hotkeys → Task 7 ✅ · Metrics (card+popup+page) → Task 8 ✅ · Settings→Calendars + EventKit → Task 9 ✅ · Shared-state isolated → Task 0 ✅.
- Deferred (explicitly out of v1): Google/Canvas calendar write adapters, global Carbon hotkey, social, email capture, iOS target, Drive folders.
