# One-Shot Polish Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four tracks in one run: (A) synced user settings + connections UI on both apps + identity linking, (B) Canvas source correctness + target-space setting + E2E verification, (C) Apple Calendar write-back + recurring Atlas-native events, (D) paste-a-URL links on tasks/events + Mac notifications.

**Architecture:** All cross-platform logic lands in AtlasCore (shared Swift package); per-user server state lands in new Supabase migrations 0025–0028 following the existing singleton-row + owner-RLS patterns; edge-function changes extend `canvas-connect` only. Tracks run sequentially (they share Models.swift / AtlasDB.swift / SettingsView.swift).

**Tech Stack:** SwiftUI (macOS 14 / iOS), Supabase (PostgREST + GoTrue + edge functions in Deno TS), XcodeGen project, hand-rolled `SupabaseAuth` REST client (no supabase-swift Auth product).

## Global Constraints

- Build check: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` — must succeed before any commit that claims done.
- iOS build check: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- Swift tests: `cd AtlasCore && swift test` for package tests; `xcodebuild ... -scheme Atlas ... test` for AtlasTests.
- **NO prod deployment inside tasks.** Migrations are written + applied to nothing; Task 16 is the single deploy/E2E gate and requires Drew's explicit OK before `supabase db push` / `functions deploy`.
- CLAUDE.md rule 5 (never mislabel a source) governs every source/read-only decision.
- Match existing style: editorial/paper UI, `atlasMono` small-caps section labels on Mac, `edCapsLabel()`/`rowStyle()` on iOS, `-- ====` banner comments + idempotent DDL in migrations.
- SourceKit single-file diagnostics about AppState/AtlasTheme are noise; xcodebuild is truth.
- UI behavior is NOT provable by green build — every UI task ends "applied, builds, needs Drew's check", collected in Task 16's device-check list.
- Commit style: `feat(scope): ...` / `fix(scope): ...`, frequent, one logical change per commit.

---

## Track A — Synced settings + connections

### Task 1: `user_settings` table + AtlasDB plumbing

**Files:**
- Create: `supabase/migrations/0025_user_settings.sql`
- Modify: `AtlasCore/Sources/AtlasCore/AtlasDB.swift` (DTO near `SpaceRow` ~line 106; methods near `loadCanvasConnection()` ~line 1096)
- Test: `AtlasTests/AtlasDBMappingTests.swift` (append)

**Interfaces:**
- Produces: `public struct UserSettingsRow: Codable, Equatable` with fields `userId: UUID`, `defaultSpaceName: String?`, `appleCalendarDefaultSpace: String?`, `googleTwoWaySync: Bool?`, `textScale: Double?`, `sidebarMode: String?`, `tasksGrouping: String?`, `perTabDocsSync: Bool?`, `notificationPrefsJSON: String?`, `updatedAt: Date?`; `AtlasDB.loadUserSettings() async throws -> UserSettingsRow?`; `AtlasDB.upsertUserSettings(_:) async throws`.
- Consumes: existing `getAll`, `send`, `requireSession`, `isoEncoder` in AtlasDB.

- [ ] **Step 1: Write the migration**

```sql
-- ============================================================
-- 0025_user_settings.sql — synced per-user settings (singleton row)
-- Canonical home for preferences that are about the USER, not the
-- device. Clients map their local @AppStorage keys to these columns
-- (Mac "tasks.defaultSpaceName" and iOS "defaultSpaceName" both map
-- to default_space_name). Device-specific state (hotkeys, window
-- geometry, session tokens, notification PERMISSION) stays local.
-- Idempotent; safe to re-run.
-- ============================================================

create table if not exists user_settings (
  user_id                     uuid primary key references auth.users on delete cascade,
  default_space_name          text,
  apple_calendar_default_space text,
  google_two_way_sync         boolean,
  text_scale                  float8,
  sidebar_mode                text,
  tasks_grouping              text,
  per_tab_docs_sync           boolean,
  -- Same JSON shape NotificationPrefs already encodes for @AppStorage
  -- on iOS; Mac (Task 14) reads/writes the identical blob.
  notification_prefs          jsonb,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

alter table user_settings enable row level security;

drop policy if exists "user_settings: owner access" on user_settings;
create policy "user_settings: owner access" on user_settings
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists user_settings_set_updated_at on user_settings;
create trigger user_settings_set_updated_at
  before update on user_settings
  for each row execute function public.set_updated_at();
```

- [ ] **Step 2: Add `UserSettingsRow` DTO + methods to AtlasDB**

DTO beside the other row structs (snake_case CodingKeys like `SpaceRow`). `notification_prefs` travels as a JSON string client-side; encode with a `RawJSON` passthrough: declare the property `notificationPrefsJSON: String?` and custom-decode via `container.decodeIfPresent(AnyJSONString.self, ...)` — simplest reliable approach given PostgREST returns jsonb as a JSON object: decode with `JSONSerialization` into `String` in `init(from:)`, encode by wrapping the string back to a JSON fragment in `encode(to:)`. Methods (mirror `loadCanvasConnection` + `upsertSpace`):

```swift
public func loadUserSettings() async throws -> UserSettingsRow? {
    let rows: [UserSettingsRow] = try await getAll("user_settings")
    return rows.first
}

public func upsertUserSettings(_ s: UserSettingsRow) async throws {
    let sess = try await requireSession()
    let body = try isoEncoder.encode(s)
    try await send(method: "POST", table: "user_settings",
                   query: [.init(name: "on_conflict", value: "user_id")],
                   extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"],
                   body: body, sess: sess)
}
```

- [ ] **Step 3: Round-trip mapping test** in `AtlasDBMappingTests` (pattern: `testEventRowRoundTrip`): encode a full `UserSettingsRow`, decode, assert equality; plus a nils-decode test from minimal JSON `{"user_id":"..."}`.
- [ ] **Step 4: Run** `xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO` → tests pass.
- [ ] **Step 5: Commit** `feat(db): 0025 user_settings synced-preferences table + AtlasDB row/load/upsert`

### Task 2: Mac settings-sync plumbing

**Files:**
- Create: `Atlas/Services/SettingsSyncService.swift`
- Modify: `Atlas/Data/AppState.swift` (bootstrap, ~where `refreshGoogleConnection()` is called), `Atlas/Views/Auth/SettingsView.swift` (push on change), `Atlas/App/AtlasApp.swift` + `Atlas/App/RootView.swift` (no key changes, values now flow through sync)

**Interfaces:**
- Consumes: `AtlasDB.loadUserSettings()` / `upsertUserSettings(_:)` (Task 1).
- Produces: `@MainActor final class SettingsSyncService: ObservableObject` with `func pullAndApply(db: AtlasDB) async` and `func push(db: AtlasDB) async` reading/writing these local keys ↔ columns: `tasks.defaultSpaceName`↔`default_space_name`, `calendar.apple.defaultSpace`↔`apple_calendar_default_space`, `calendar.google.enabled`↔`google_two_way_sync`, `appearance.textScale`↔`text_scale`, `sidebar.mode`↔`sidebar_mode`, `notes.perTabDocsSync.enabled`↔`per_tab_docs_sync`.

**Merge policy (encode exactly this):** pull-and-apply runs at bootstrap and on app-foreground; **server wins on pull** (apply row values to UserDefaults when the column is non-nil). Push runs ONLY on a user-initiated change of a synced setting (never at launch), so a fresh device with defaults can't clobber the server. Push sends the full row (all synced keys' current local values).

- [ ] **Step 1: Write `SettingsSyncService`** with the two methods, a `private static let syncedDefaults = UserDefaults.standard`, and a debounced push (`Task.sleep` 500ms, cancel previous) so a settings-screen drag doesn't spam upserts.
- [ ] **Step 2: Wire pull** into `AppState` bootstrap right after `refreshGoogleConnection()` and into the existing scene-foreground path in `AtlasApp.swift`.
- [ ] **Step 3: Wire push**: in `SettingsView.swift` add `.onChange(of:)` for each synced `@AppStorage` binding → `settingsSync.push(db:)`. (`sidebar.mode` changes in RootView; add the same onChange there.)
- [ ] **Step 4: Build Mac target** → succeeds. Manual check note: needs prod table (Task 16) to observe live.
- [ ] **Step 5: Commit** `feat(mac): settings sync — pull-on-launch/foreground, push-on-change to user_settings`

### Task 3: iOS settings-sync plumbing

**Files:**
- Create: `AtlasMobile/Services/SettingsSyncService.swift` (iOS twin; can share logic only if trivially — otherwise small duplicate, note it)
- Modify: `AtlasMobile/Data/MobileStore.swift` (pull after snapshot load), `AtlasMobile/Views/Settings/SettingsView.swift`, `AtlasMobile/Views/Tasks/TasksView.swift` (push on change of `defaultSpaceName`, `tasksGrouping`, `notificationPrefs`)

**Interfaces:** consumes Task 1 methods; maps `defaultSpaceName`↔`default_space_name`, `tasksGrouping`↔`tasks_grouping`, `notificationPrefs` (JSON string)↔`notification_prefs`. Same merge policy as Task 2, verbatim.

- [ ] **Step 1–3:** mirror Task 2 (pull in `MobileStore.bootstrap`/scene-active; push on user change; 500ms debounce).
- [ ] **Step 4: Build iOS target** → succeeds.
- [ ] **Step 5: Commit** `feat(mobile): settings sync for default space, tasks grouping, notification prefs`

---

## Track B — Canvas correctness + space setting + E2E

### Task 4: `.canvas` source in AtlasCore (the shared fix)

**Files:**
- Modify: `AtlasCore/Sources/AtlasCore/Models.swift:62-75` (enum), `Models.swift:166-217` (TaskItem), `AtlasCore/Sources/AtlasCore/AtlasDB.swift:298-368` (EventRow), `AtlasDB.swift:194-292` (TaskRow)
- Test: `AtlasCore/Tests/AtlasCoreTests/EventRowSourceTests.swift` (extend), `AtlasTests/AtlasDBMappingTests.swift`

**Interfaces:**
- Produces: `EventSource.canvas` (displayName `"Canvas"`); `CalendarEvent` rows with `canvas_uid` decode to `source: .canvas, isReadOnly: true`; `TaskItem.canvasUID: String?` (non-nil ⇒ Canvas assignment; task stays completable/schedulable, but title+due are Canvas-owned).
- Consumed by Tasks 5, 6.

- [ ] **Step 1: Failing tests first**: `EventRowSourceTests` — row with `canvas_uid` → `.canvas` + `isReadOnly == true`; row with both `canvas_uid` nil and `google_event_id` set → still `.google`; TaskRow with `canvas_uid` → `canvasUID` non-nil. Run `cd AtlasCore && swift test` → FAIL (fields don't exist).
- [ ] **Step 2: Implement**: add `case canvas` (+ displayName "Canvas"); add `canvasUid: String?` to `EventRow` + `TaskRow` CodingKeys (`canvas_uid`); in `EventRow.toDomain()` replace the source line:

```swift
let derivedSource: EventSource =
    canvasUid != nil ? .canvas :
    (googleEventId != nil ? .google : .atlas)
// Canvas rows are server-owned: sync stomps title/start/end on every tick.
return CalendarEvent(..., isReadOnly: canvasUid != nil, source: derivedSource, ...)
```

Add `canvasUID` to `TaskItem` + `TaskRow.toDomain()` and the reverse `TaskRow(domain:)` / `EventRow(domain:)` mappers so upserts round-trip the column unchanged (critical: client edits of a Canvas task must not null out `canvas_uid`).
- [ ] **Step 3:** `swift test` → PASS; run AtlasTests too (EventRow round-trip tests must still pass — update fixtures for the new field).
- [ ] **Step 4: Commit** `feat(core): EventSource.canvas — canvas_uid decoded, events read-only, tasks flagged (rule 5)`

### Task 5: Mac Canvas surfaces

**Files:**
- Modify: `Atlas/Views/Calendar/CalendarEventDetailView.swift:113-125` (banner), `Atlas/Views/Calendar/EventContextMenuModifier.swift:30-35` (already generic via `source.displayName` — verify only), `Atlas/Views/Task/TaskDetailView.swift` (Canvas banner + title/due gating)

- [ ] **Step 1:** Event detail: extend the lock-banner copy switch with `.canvas` → `"From Canvas — synced automatically. Schedule it; title and dates update from your feed."`. Drag/context gating needs no change (keys off `isReadOnly`, now set by Task 4).
- [ ] **Step 2:** `TaskDetailView`: when `task.canvasUID != nil`, show the same banner style above the title, and `.disabled(true)` the title `TextField` and due-date picker only (notes/schedule/done stay live — matches canvas-sync's USER-DATA-SAFE partial update, `supabase/functions/canvas-sync/index.ts:415-424`).
- [ ] **Step 3:** Build Mac → succeeds. UI needs Drew's check (Task 16 list).
- [ ] **Step 4: Commit** `feat(mac): Canvas events/tasks labeled + gated per source`

### Task 6: iOS Canvas surfaces

**Files:**
- Modify: `AtlasMobile/Views/Components/ItemDetailSheet.swift:377-394` (+ banner at 112-116 pattern), `AtlasMobile/Views/Schedule/DayGridView.swift:203-210`

- [ ] **Step 1:** `isEditable`/`canDelete`: events → `e.source == .atlas || e.source == .google` (unchanged) so `.canvas` falls to read-only; tasks → still `true`, but when `task.canvasUID != nil` render the read-only title/due treatment + `"From Canvas"` banner (mirror the existing Google banner pattern at 112-116). `readOnlyEvent` covers `.apple` **or** `.canvas`.
- [ ] **Step 2:** `DayGridView.isWritable`: comment + logic already exclude non-atlas/google events — verify `.canvas` now falls through to false; for `.task` blocks add `where task.canvasUID == nil` is NOT required (tasks stay movable — moving sets `scheduled_at`, which Canvas never touches). Leave tasks movable; add that rationale to the existing comment.
- [ ] **Step 3:** Build iOS → succeeds; commit `feat(mobile): Canvas source respected — read-only events, badged tasks`

### Task 7: Canvas target-space is changeable (server + Mac UI)

**Files:**
- Modify: `supabase/functions/canvas-connect/index.ts` (add PATCH), `Atlas/Views/Auth/SettingsView.swift:218-250` (`canvasConnectedRow`), `AtlasCore/Sources/AtlasCore/CanvasService.swift` (add `updateSpace`)

**Interfaces:** `PATCH canvas-connect` body `{spaceName: string}` → updates `canvas_connections.space_name` for the JWT's user (service-role write, JWT verified exactly like POST at index.ts:66-ish); `CanvasService.updateSpace(spaceName:jwt:)`.

- [ ] **Step 1:** Add the PATCH branch beside POST/DELETE: verify JWT → `admin.from("canvas_connections").update({ space_name: spaceName }).eq("user_id", userId)`; 404 if no row. Validate `spaceName` non-empty.
- [ ] **Step 2:** `CanvasService.updateSpace` mirrors `connect()` (index.ts is the same endpoint, method PATCH).
- [ ] **Step 3:** Mac `canvasConnectedRow`: replace the static "→ SpaceName" text with the same `Picker` used in the connect form (line 263-286), `.onChange` → `updateSpace` → `state.refreshCanvasConnection()`.
- [ ] **Step 4:** Build → commit `feat(canvas): destination space editable after connect (PATCH canvas-connect + Mac picker)`

### Task 8: iOS Connections section (Google status + Canvas manage)

**Files:**
- Modify: `AtlasMobile/Views/Settings/SettingsView.swift:249-263` (`connectionsSection`)

**Interfaces:** consumes `store.db.loadGoogleConnection()` (status/lastError/lastSyncedAt), `store.db.loadCanvasConnection()`, `CanvasService.connect/disconnect/updateSpace` (AtlasCore, shared — works from iOS as-is).

- [ ] **Step 1: Google row** — three states from `GoogleConnectionRow`: `active` → "Connected · synced Xm ago"; `error`/`revoked` → warning color + "Reconnect needed — open Atlas on your Mac" (connect flow is a Desktop-OAuth loopback, Mac-only today; do NOT attempt OAuth on iOS in this task); nil → "Not connected — set up on your Mac".
- [ ] **Step 2: Canvas rows** — mirror Mac: when connected show status + space picker (spaces from snapshot) + Disconnect (confirmation dialog); when not, a paste-URL field + space picker + Connect button using the same `validCanvasFeedURL` predicate copied from `SettingsView.swift:372` (extract it into AtlasCore `CanvasService.isValidFeedURL(_:)` so both platforms share it — remove the Mac copy).
- [ ] **Step 3:** Build both targets → commit `feat(mobile): connections — Google status + full Canvas manage from the phone`

### Task 9 (E2E — folded into Task 16): Canvas verification happens at the deploy gate, not before; see Task 16 Step 3.

---

## Track C — Apple write-back + recurring events

### Task 10: EventKit write methods + durable Apple id

**Files:**
- Modify: `Atlas/Services/EventKitService.swift`
- Create: `supabase/migrations/0026_apple_event_id.sql` (`alter table events add column if not exists apple_event_id text;` + same for `tasks`, banner comment: Mac-only mirror id; EventKit ids are per-device — column is best-effort continuity, Mac is the only EventKit device)
- Modify: `AtlasCore/Sources/AtlasCore/Models.swift` (`CalendarEvent.appleEventId: String?`), `AtlasDB.swift` EventRow/TaskRow (decode + round-trip `apple_event_id`)
- Test: `AtlasTests/AtlasDBMappingTests.swift` (round-trip incl. new field)

**Interfaces (produces):**
```swift
// EventKitService
func createEvent(_ event: CalendarEvent, calendarId: String?) async throws -> String  // returns eventIdentifier
func updateEvent(appleEventID: String, with event: CalendarEvent) async throws
func deleteEvent(appleEventID: String) async throws
func writableCalendars() -> [(id: String, title: String)]
```

- [ ] **Step 1:** Mapping tests for the new row field (fail → implement → pass, as Task 4).
- [ ] **Step 2:** Implement the four methods with `EKEvent(eventStore:)`, `store.save(_:span:.thisEvent)`, `store.remove(_:span:.thisEvent)`; `updateEvent` fetches via `store.event(withIdentifier:)` and throws a typed `EventKitWriteError.notFound` if the id no longer resolves. Guard every method on `.fullAccess`.
- [ ] **Step 3:** Build + commit `feat(mac): EventKit write surface + apple_event_id round-trip (0026)`

### Task 11: Apple events editable + Atlas→Apple mirror toggle

**Files:**
- Modify: `Atlas/Services/EventKitService.swift:84-97` (ingest: `isReadOnly` false for events whose EKCalendar `allowsContentModifications`, keep `true` for subscribed/recurring — set `isRecurring` from `ekEvent.hasRecurrenceRules`, fixing the Apple labeling gap), `Atlas/Data/AppState.swift:919-1002` (source-switch + `shouldWriteBackApple`), `Atlas/Views/Auth/SettingsView.swift` `calendarsSection` (new toggle row + target-calendar picker)

**Interfaces:** `UserDefaults key "calendar.apple.writeback"` (Bool, default false, **DEVICE-local** — EventKit is per-device); `AppState.pushNewEventToApple/pushUpdatedEventToApple/pushDeletedEventToApple` mirroring the Google trio at `AppState.swift:1016/1028/1044`; gate `shouldWriteBackApple(_:)` = `appleWritebackEnabled && eventKit.authorized && !event.isReadOnly && event.source == .atlas && event.rrule == nil` (rrule from Task 12; until then omit that clause).

- [ ] **Step 1:** `updateEvent`/`deleteEvent` in AppState get an `.apple` branch mirroring the `.google` external-edit branch at 919-937: writable Apple event edits → `eventKit.updateEvent`, update `externalEvents`, never touch Supabase (Apple events remain unpersisted).
- [ ] **Step 2:** Atlas-native mirror: on add/update/delete of `.atlas` events, when gated on, call the EventKit trio; stamp returned identifier into `appleEventId` + `db.upsertEvent` (pattern: `pushWorkBlockToGoogle`, AppState.swift:822-836). Add `backfillEventsToApple()` fired when the toggle flips on (pattern: `backfillEventsToGoogle()` at 1008).
- [ ] **Step 3:** Settings UI: toggle + `Picker` over `eventKit.writableCalendars()` storing `calendar.apple.writeback.calendarId` (String, device-local).
- [ ] **Step 4:** Build. Behavior needs Drew's device check (edits appear in Calendar.app both directions). Commit `feat(mac): Apple Calendar write-back — editable Apple events + optional Atlas→Apple mirror`

### Task 12: Recurrence model + expander (pure, TDD)

**Files:**
- Create: `supabase/migrations/0027_event_rrule.sql` (`alter table events add column if not exists rrule text;` — banner: simple subset `FREQ=DAILY|WEEKLY|MONTHLY;INTERVAL=n;BYDAY=...;UNTIL=yyyymmdd`; masters only, instances are client-expanded, NEVER pushed to Google/Apple in v1 — google-sync ignores the column entirely, and the client push gates exclude rrule events to avoid the singleEvents=true echo storm)
- Create: `AtlasCore/Sources/AtlasCore/RecurrenceExpander.swift`
- Modify: `Models.swift` (`CalendarEvent.rrule: String?`), `AtlasDB.swift` (EventRow field + round-trip)
- Test: Create `AtlasCore/Tests/AtlasCoreTests/RecurrenceExpanderTests.swift`

**Interfaces (produces):**
```swift
public enum RecurrenceExpander {
    /// Expand a master event into concrete instances intersecting [windowStart, windowEnd).
    /// Instances share the master's id-derived stable UUIDs (FNV-1a of "\(master.id)-\(occurrenceIndex)")
    /// so SwiftUI identity is stable across refreshes. Master itself is replaced by its instances.
    public static func expand(_ master: CalendarEvent, window: DateInterval, calendar: Calendar) -> [CalendarEvent]
    public static func parse(_ rrule: String) -> RecurrenceRule?   // nil = unrecognized, treat event as non-recurring
    public struct RecurrenceRule: Equatable { public var freq: Freq; public var interval: Int; public var byDay: Set<Int>?; public var until: Date? }
}
```

- [ ] **Step 1: Tests first** (`swift test`, FAIL): daily interval 1 over a 7-day window → 7 instances with correct dates/durations; weekly BYDAY=MO,WE → only Mon/Wed; UNTIL respected; instance UUIDs stable across two expand calls; malformed rrule → `parse` nil; window that excludes the master's own start still yields in-window instances; expanded instances carry `isRecurring = true` and `rrule = nil` (instances are not masters).
- [ ] **Step 2:** Implement with pure `Calendar` date math (no Date.now; window passed in). Keep to the documented subset — reject anything else via `parse → nil`.
- [ ] **Step 3:** `swift test` PASS → commit `feat(core): 0027 rrule column + RecurrenceExpander (daily/weekly/monthly subset, TDD)`

### Task 13: Recurrence UI + display expansion + sync guards

**Files:**
- Modify: `Atlas/Views/Calendar/EventEditorSheet.swift` (repeat picker), `Atlas/Data/AppState.swift` (expansion where views read events; guards), `AtlasMobile` schedule pipeline (wherever `MobileStore` snapshot events feed `DayGridView`/list — expand there via the same helper)

- [ ] **Step 1: Editor**: `Picker("Repeats")` — None / Daily / Weekly / Monthly / Weekdays (Mon–Fri) + optional end `DatePicker`, serializing to the rrule subset; only for `.atlas` events. Editing any expanded instance opens the master (find by stripping instance UUID → master id kept in a new `CalendarEvent.recurrenceMasterID: UUID?` set by the expander) and edits the series; deleting deletes the series (confirmation copy says so). No per-instance exceptions in v1.
- [ ] **Step 2: Display**: at the point Mac merges `events + externalEvents` for the visible range, map masters through `RecurrenceExpander.expand`; same at the iOS snapshot→blocks step. Masters with rrule never render directly.
- [ ] **Step 3: Guards**: client Google push paths (`shouldWriteBack`, AppState.swift:994-1002) and Apple mirror gate (Task 11) exclude `event.rrule != nil`. Editor shows a footnote: "Repeats in Atlas only — not synced to Google or Apple yet."
- [ ] **Step 4:** Build both targets; needs Drew's check. Commit `feat(calendar): recurring Atlas events — series editor, client expansion, sync-guarded`

---

## Track D — Links on anything + Mac notifications

### Task 14: Paste-a-URL links on tasks/events

**Files:**
- Create: `supabase/migrations/0028_reference_project_optional.sql` (`alter table project_references alter column project_id drop not null;` — banner: personal links attach directly to a task/event via reference_attachments without a project pool)
- Modify: `Atlas/Views/Task/TaskDetailView.swift:~470` + `Atlas/Views/Calendar/CalendarEventDetailView.swift:~223` (referencesSection: add "Add link" button → `AddLinkSheet` in a new attach-on-create mode), `Atlas/Views/References/AddLinkSheet.swift` (optional `attachTo: ReferenceAttachTarget?`), `Atlas/Data/AppState+References.swift:47` (`addLink` accepts nil projectID + immediate attach), `AtlasMobile/Views/Components/ItemDetailSheet.swift` (read-only attached-links list, rows open via `@Environment(\.openURL)` — reuse `externalURL` logic from `AttachReferencePicker.swift:24-33`, moving it into `AtlasCore/Sources/AtlasCore/Reference.swift` so iOS can use it)
- Test: `AtlasTests/AtlasDBMappingTests.swift` reference row round-trip with nil project

- [ ] **Step 1:** Migration + AtlasCore `Reference` model allows nil projectID; move `externalURL` to the model; mapping test.
- [ ] **Step 2:** Mac: "Add link" in both detail views — sheet saves reference (projectID = item's project, else nil) and creates the `reference_attachments` row in one flow; row renders with existing `ReferenceListRow` (`AttachReferencePicker.swift:40-80`).
- [ ] **Step 3:** iOS: attached links section in `ItemDetailSheet` (list + tap-to-open; no add UI on phone in v1 — capture-first philosophy, note in commit).
- [ ] **Step 4:** Build both → commit `feat(refs): paste-a-URL links attach directly to tasks/events; iOS shows them`

### Task 15: Mac notifications

**Files:**
- Create: `Atlas/Services/MacNotificationScheduler.swift` (port of `AtlasMobile/Services/NotificationScheduler.swift`, consuming shared `NotificationPlanner` from AtlasCore verbatim)
- Modify: `Atlas/Data/AppState.swift` (feed planner from `events+externalEvents+tasks` on the existing 60s `startClock()` tick at line 196-201, debounced like mobile's 1s pattern), `Atlas/Views/Auth/SettingsView.swift` (new Notifications section)

**Interfaces:** prefs = the SAME `NotificationPrefs` JSON, now synced via `user_settings.notification_prefs` (Tasks 1–3), so lead time/digest hour set on the phone apply on Mac. One **device-local** master switch `UserDefaults "notifications.mac.enabled"` (default OFF) — this is the dedup story: both devices firing is expected behavior when both masters are on; the per-device master lets Drew choose. Say exactly this in the settings row subtitle: "Also notifying on iPhone? Reminders fire on every device that has this on."

- [ ] **Step 1:** Move `NotificationPrefs` from `AtlasMobile/Data/` into `AtlasCore/Sources/AtlasCore/` (keep the RawRepresentable AppStorage bridge; iOS imports move — mechanical). Build iOS to prove no regression.
- [ ] **Step 2:** `MacNotificationScheduler`: `UNUserNotificationCenter` authorization + `reschedule(events:tasks:prefs:now:)` calling `NotificationPlanner.plan(...)` (same 60-cap, same triggers). Hook to clock tick + data-change points, 1s debounce.
- [ ] **Step 3:** Settings UI: master toggle (requests permission on first enable), lead-time stepper, digest time picker, kind toggles — writing the shared prefs (which sync via Task 2's push).
- [ ] **Step 4:** Build → commit `feat(mac): local notifications — shared NotificationPlanner, synced prefs, per-device master`

---

## Track E — Identity linking (last: highest external uncertainty)

### Task 16 — renamed Task 15b: see ordering note. Identity linking (Apple ↔ Google ↔ email on one account)

**Files:**
- Modify: `AtlasCore/Sources/AtlasCore/SupabaseAuth.swift` (add `userIdentities()`, `linkIdentityAuthorizeURL(provider:)` → `GET/POST user/identities/authorize?provider=google&skip_http_redirect=true`, `unlinkIdentity(id:)`, `linkAppleIdentity(idToken:nonce:)`), `Atlas/Services/AuthService.swift` + `Atlas/Views/Auth/SettingsView.swift` account section (Linked accounts rows), `AtlasMobile/Views/Settings/SettingsView.swift` accountSection (same rows), `AtlasMobile/Data/MobileStore.swift`
- Reference implementation to mirror request-shapes from: the checked-out SDK source `AtlasCore/.build/checkouts/supabase-swift/Sources/Auth/AuthClient.swift:1214-1305` (`userIdentities`, `getLinkIdentityURL`, `linkIdentityWithIdToken`, `unlinkIdentity`) — copy the endpoint/paths/params into our hand-rolled client; do NOT link the Auth product (keeps the dependency-free philosophy stated in `SupabaseAuth.swift:47`).

**PRECONDITION (Step 1 probes it):** GoTrue "manual linking" must be enabled on the project. If the probe fails with `manual_linking_disabled`, implement everything but leave the UI behind `identityLinkingAvailable` (probed at settings-open), and hand Drew the one-toggle instruction (Dashboard → Auth → Providers → "Allow manual linking").

- [ ] **Step 1: Probe** prod with a minted test-account JWT (pattern: `scripts/doc_tabs_e2e.py` JWT minting): `curl -H "Authorization: Bearer $JWT" "$SUPABASE_URL/auth/v1/user/identities"` → expect 200 list. Then `POST .../user/identities/authorize?provider=google&skip_http_redirect=true` → expect a URL or the disabled error. Record which.
- [ ] **Step 2:** Implement the four SupabaseAuth methods mirroring SDK request shapes; unit-test URL/param construction in `AtlasTests/GoogleAuthServiceTests.swift` style (new `IdentityLinkingTests.swift`: authorize URL contains `skip_http_redirect`, provider, correct path; no network).
- [ ] **Step 3:** Mac UI: "Linked accounts" rows (Apple/Google/email with Link/Unlink; Google link opens the returned URL via `ASWebAuthenticationSession`, Apple link reuses `AppleSignInCoordinator` → `linkAppleIdentity`). Guard: never allow unlinking the last identity (GoTrue rejects it; catch + toast).
- [ ] **Step 4:** iOS UI: same rows, Apple-link + Google-link via `ASWebAuthenticationSession`.
- [ ] **Step 5:** Build both → commit `feat(auth): identity linking — Apple/Google/email on one account (hand-rolled GoTrue client)`

---

## Task 17: Deploy gate + E2E + device-check list (CHECKPOINT — needs Drew's OK)

- [ ] **Step 1: STOP — ask Drew** before touching prod: `supabase db push` (0025–0028) + `supabase functions deploy canvas-connect`. Migrations are additive-only (new table, 3 nullable columns, one dropped NOT NULL) — state that when asking. Verify post-push with PostgREST per the live-DB-access pattern (project ref jxrmozhgsebwtbdleyxp).
- [ ] **Step 2: Settings-sync E2E**: with Drew's test account (NOT the 3 real-data accounts), set default space on one platform, pull on the other, assert value; verify a fresh account doesn't clobber (launch-without-change pushes nothing — check `user_settings` row absent).
- [ ] **Step 3: Canvas E2E** (the "never actually tested" item): `curl -s "$SUPABASE_URL/functions/v1/canvas-sync?dryRun=1" -X POST -H "Authorization: Bearer $SERVICE_ROLE"` → inspect intended writes against Drew's live connection; then a live tick; then PostgREST asserts: assignments exist as tasks with `canvas_uid` + correct due dates, events carry `canvas_uid` + `google_origin=true`, re-run is idempotent (row counts stable), completing a Canvas task in-app survives the next sync, target-space PATCH moves future unmatched items.
- [ ] **Step 4: Full test suite + both builds** green; run `AtlasCore` `swift test` + AtlasTests.
- [ ] **Step 5: Write Drew's device-check list** (append to docs/mobile-backlog.md "Where we're at"): Canvas read-only feel on both platforms · iOS connections section · Canvas space picker · Apple write-back both directions in Calendar.app · recurring event create/edit/delete series · links on tasks/events (Mac add, iOS open) · Mac notifications fire (master on) · identity link/unlink round-trip · settings change on phone appears on Mac after foreground.
- [ ] **Step 6: Commit + push** everything (Drew's standing pattern: work lands on main).

## Execution order

1 → 2 → 3 (settings foundation) → 4 → 5 → 6 → 7 → 8 (Canvas) → 10 → 11 → 12 → 13 (calendar) → 14 → 15 (links + notifications; 15 depends on 1–3) → 16/15b (identity linking) → 17 (deploy gate).

Tasks are sequential — Models.swift/AtlasDB.swift/SettingsView.swift are shared hot files; do not parallelize edits to them.
