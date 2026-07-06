# Final Review Fix Pass — Collab Phase 2 (Shared Projects)

Post-final-review fixes for 4 findings surfaced by cross-task-interaction tracing. All 8 tasks in this branch individually passed review; these are bugs only visible once tasks are considered together.

## Finding 1 (Critical): `claimTask` corrupted ownership + orphaned project linkage

**Root cause confirmed:** `AtlasDB.upsertTask(_:)` (AtlasCore/Sources/AtlasCore/AtlasDB.swift, was line 1021) unconditionally set `row.userId = userId` (the CALLER, not the true owner) and `TaskRow(domain:)` unconditionally sets `projectId = nil` (no `projectID` field exists on `TaskItem`). `AppState.claimTask` routed claims through this general upsert, so a member claiming a shared task silently reassigned `tasks.user_id` to themselves and wiped `tasks.project_id` to NULL for everyone.

**Fix:**
- Added a new scoped method `AtlasDB.claimTask(id:assigneeId:)` (AtlasDB.swift, after `deleteTask`, ~line 1041) that does a PATCH filtered by `id=eq.<uuid>` with only `{"assignee_id": ...}` in the body — mirrors the `respondToInvite` decline-path pattern (PATCH via `send(...)`). It never touches `user_id` or `project_id`.
- `upsertTask` itself is UNCHANGED in this respect (still stamps `userId`, still leaves `projectId` nil) — that's out of scope per the brief and used by every other task write path.
- Changed `Atlas/Data/AppState.swift`'s `claimTask(_:)` (was line 344) to call `db?.claimTask(id: taskId, assigneeId: userId)` instead of `db?.upsertTask(updated)`. Kept the local `tasks[i].claim(by: userId)` mutation for immediate UI feedback.

**Verified:** `claimTask` now leaves `user_id`/`project_id` completely untouched — the PATCH body only ever contains `assignee_id`.

## Finding 2 (Important): Realtime had no user auth token

**Real API found:** Inspected the resolved package at `AtlasCore/.build/checkouts/supabase-swift/Sources/Realtime/`:
- `Types.swift` (`RealtimeClientOptions`) exposes `headers: [String: String]` in its public init, and internally maps a special `HTTPField.Name.apiKey = "apiKey"` header key (`headers[.apiKey]` → `var apikey`).
- `RealtimeClientV2.init(url:options:)` (RealtimeClientV2.swift ~line 166-191) reads `options.headers[.authorization]` at construction time and seeds `mutableState.accessToken` from it directly (splitting off the `Bearer ` prefix): this is the exact per-connection auth mechanism — passing an `"Authorization": "Bearer <token>"` header at init sets the socket's JWT used for both the WS handshake (via `connectionManager` built with `headers: options.headers.dictionary`) and channel joins (`_getAccessToken()` falls back to `mutableState.accessToken` when no `accessToken` closure is configured).
- (There is also an `accessToken: (@Sendable () async throws -> String?)?` closure option for refresh-on-demand scenarios — not needed here since `RealtimeSyncService` is constructed fresh per `startRealtimeSync` call with a freshly-fetched token, so the simpler header-seeded path suffices and matches the existing REST client's pattern of reading `sess.accessToken` fresh each call.)

**Fix:**
- Added `AtlasDB.currentAccessToken()` (AtlasDB.swift, next to `currentUserId()`) — `try requireSession().accessToken`.
- `RealtimeSyncService.init` (RealtimeSyncService.swift) now takes `accessToken: String` and builds `RealtimeClientOptions(headers: ["apikey": anonKey, "Authorization": "Bearer \(accessToken)"])`.
- `AppState.startRealtimeSync` (AppState.swift ~line 268) now fetches `db?.currentAccessToken()`, guards on it being present (bails silently if not — same degrade-silently posture as other collab loads), and threads it into `RealtimeSyncService(...)`.

## Finding 2b (Important): `tasks`/`events`/`notes` not in `supabase_realtime` publication

Appended a new idempotent `do $$ ... $$` block to the end of `supabase/migrations/0016_shared_projects.sql` (section "── 7." — the file already had a "── 6." for `accept_invite`, so numbered this one 7 to avoid a duplicate section number) that adds each of `tasks`/`events`/`notes` to `supabase_realtime` only if not already a member (checked via `pg_publication_tables`). Not applied to any live database — read-through only, consistent with this plan's posture on migrations.

## Finding 3 (Important): Realtime subscribed to the wrong project set

**Fix:** One-line change in `AppState.startRealtimeSync` (AppState.swift ~line 270-271):

```swift
let sharedProjectIds = spaces.flatMap { $0.projects }.filter(isShared).map(\.id)
    + sharedWithMeProjects.map(\.id)
```

Now includes projects shared TO the user (only ever present in `sharedWithMeProjects`, never in `spaces`), not just ones the user owns and shared out.

## Finding 4 (Important): `created_by` never populated on new writes

**Fix (tasks):** In `AtlasDB.upsertTask(_:)` (AtlasDB.swift ~line 1021), after `row.userId = userId`:

```swift
if row.createdBy == nil { row.createdBy = userId }
```

Only stamps `createdBy` when the domain object doesn't already carry one, so an existing task's original creator is preserved across edits by other members; only a brand-new task defaults to the caller.

**Events — checked, genuinely out of scope:** `CalendarEvent` has NO `createdByID` field (confirmed by reading its full definition and `EventRow` in AtlasDB.swift), and `EventRow` has no `createdBy`/`created_by` column mapping either. There is no client-side domain field to read from, so `events.created_by` has the same underlying gap (NULL on every new write) but it is not fixable within this task's scope — it would require adding a new field to `CalendarEvent` and `EventRow`, which is a new-feature-shaped change beyond "wire an existing field through," not this fix pass's job. Flagging this as a follow-up item, not fixed here.

## Test Results

`cd AtlasCore && swift test`: **67 tests, 0 failures** (0 unexpected), plus a 0-test Swift Testing run with 0 failures. No regressions — all existing suites (including `TaskAssignmentTests`, which already covers `TaskItem.claim(by:)` domain logic) passed unchanged.

## Build Result

`xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**, no errors. (`Atlas.xcodeproj` already existed in this worktree; `xcodegen generate` was not needed.)

## Files Changed

- `AtlasCore/Sources/AtlasCore/AtlasDB.swift` — added `claimTask(id:assigneeId:)`, `currentAccessToken()`, `created_by` default-fill in `upsertTask`.
- `AtlasCore/Sources/AtlasCore/RealtimeSyncService.swift` — `init` now takes `accessToken: String`, passes `Authorization: Bearer <token>` header.
- `Atlas/Data/AppState.swift` — `claimTask` calls new scoped DB method; `startRealtimeSync` includes `sharedWithMeProjects`, fetches and passes access token.
- `supabase/migrations/0016_shared_projects.sql` — appended publication-membership block for `tasks`/`events`/`notes` (not applied to any DB).

## Concerns

None blocking. One follow-up noted: `events.created_by` has the same "never populated" gap as tasks did, but fixing it requires adding a `createdByID` field to `CalendarEvent`/`EventRow` first — out of scope for this fix pass (no existing domain field to wire through), left as a future task rather than papering over it with a workaround.

There is a pre-existing unstaged modification to `.superpowers/sdd/task-8-report.md` in this worktree that predates this fix pass and is unrelated to any of the 4 findings — left untouched and NOT included in the commit(s) below.
