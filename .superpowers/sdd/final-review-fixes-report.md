# Final Review Fix — Space Members N+1

## Finding

`AppState.loadCollabState()` called `AtlasDB.loadSpaceMembers(spaceId:)` once per space. That
method fetched the *entire* `space_members` table via `getAll("space_members")` and filtered
client-side to one space — so with N spaces, the whole table was fetched N times over the
network. The project-level equivalent already had the correct fix (`loadAllProjectMembers()`,
one fetch, grouped locally); the space-level path had not been given the same treatment.

## What I changed

### `AtlasCore/Sources/AtlasCore/AtlasDB.swift`

Added `loadAllSpaceMembers()` immediately after `loadSpaceMembers(spaceId:)` (around line 1039),
mirroring `loadAllProjectMembers()` exactly in style, doc-comment shape, and behavior:

Before (only method available):
```swift
public func loadSpaceMembers(spaceId: UUID) async throws -> [SpaceMemberRow] {
    let all: [SpaceMemberRow] = (try? await getAll("space_members", order: "added_at")) ?? []
    return all.filter { $0.spaceId == spaceId }
}
```

After (new method added, `loadSpaceMembers` untouched):
```swift
public func loadSpaceMembers(spaceId: UUID) async throws -> [SpaceMemberRow] {
    let all: [SpaceMemberRow] = (try? await getAll("space_members", order: "added_at")) ?? []
    return all.filter { $0.spaceId == spaceId }
}

/// Every space-member row the caller may see (RLS-scoped), grouped by
/// space id. One round-trip that replaces the per-space N+1 loop of
/// `loadSpaceMembers(spaceId:)` — the old path fetched the whole
/// `space_members` table once per space and filtered client-side.
/// Rows within each group keep `added_at` order (the fetch is ordered and
/// `Dictionary(grouping:)` preserves element order). Best-effort: a missing
/// table (pre-migration) yields an empty map rather than throwing.
public func loadAllSpaceMembers() async throws -> [UUID: [SpaceMemberRow]] {
    let all: [SpaceMemberRow] = (try? await getAll("space_members", order: "added_at")) ?? []
    return Dictionary(grouping: all, by: { $0.spaceId })
}
```

Note: `loadAllProjectMembers()` itself returns `[UUID: [ProjectMemberRow]]` (one fetch, grouped
client-side into a dictionary), not a flat array — so `loadAllSpaceMembers()` mirrors that exact
shape rather than the flat-array shape sketched in the task description, to stay consistent with
the real established pattern.

### `Atlas/Data/AppState.swift` — `loadCollabState()` (around line 434)

Before:
```swift
// Per-space membership rosters — mirrors the per-project loop above,
// one level up. Spaces themselves live only in `spaces`. Runs
// independently of the "shared with me" lookup below, which needs
// `myUserId` and may bail early.
var membersBySpace: [UUID: [SpaceMemberRow]] = [:]
for space in spaces {
    membersBySpace[space.id] = (try? await db.loadSpaceMembers(spaceId: space.id)) ?? []
}
self.spaceMembers = membersBySpace
```

After:
```swift
// One round-trip for every visible space-membership row, grouped by
// space, mirroring the per-project fetch above — instead of one
// fetch-and-filter per space. Spaces themselves live only in `spaces`.
// Runs independently of the "shared with me" lookup below, which
// needs `myUserId` and may bail early.
let membersByAllSpaces = (try? await db.loadAllSpaceMembers()) ?? [:]
var membersBySpace: [UUID: [SpaceMemberRow]] = [:]
for space in spaces {
    membersBySpace[space.id] = membersByAllSpaces[space.id] ?? []
}
self.spaceMembers = membersBySpace
```

The loop over `spaces` remains (to build the `[UUID: [SpaceMemberRow]]` map keyed exactly to
today's visible spaces, defaulting missing spaces to `[]`, matching the project-members pattern),
but it no longer performs a network call per iteration — it only indexes into the
already-fetched dictionary.

## N+1 confirmation

`db.loadAllSpaceMembers()` is called exactly once per `loadCollabState()` invocation, regardless
of the number of spaces. The `for space in spaces` loop that follows does no I/O — it is a pure
dictionary lookup (`membersByAllSpaces[space.id]`). This is the same shape as the already-fixed
`loadAllProjectMembers()` call directly above it. N fetches → 1 fetch.

## Test result

`cd AtlasCore && swift test`: **71 tests, 0 failures, 0 unexpected** (plus an empty Swift Testing
run with 0 tests/0 suites — expected, this package uses XCTest).

## Build result

`xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**, no errors.

## Files changed

- `AtlasCore/Sources/AtlasCore/AtlasDB.swift` — added `loadAllSpaceMembers()`
- `Atlas/Data/AppState.swift` — `loadCollabState()` now calls `loadAllSpaceMembers()` once and
  groups locally instead of looping `loadSpaceMembers(spaceId:)`

## Concerns

- `loadSpaceMembers(spaceId:)` now has **zero callers** in the codebase (verified via grep across
  all `.swift` files). It was left in place per instructions, since it may be a useful
  single-space accessor for future callers — but it is currently dead code, same situation its
  project-level sibling `loadProjectMembers(projectId:)` was likely already in. Flagging rather
  than deleting, as instructed.
- No other concerns. The fix is a mechanical mirror of the already-reviewed, already-passing
  project-members pattern; no new abstractions, no behavior change to the resulting
  `spaceMembers` dictionary shape or contents.
