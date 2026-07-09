# Multi-Account Google Calendar — Design Spec
_Date: 2026-06-29_

## Overview

Allow up to 5 Google accounts to be connected simultaneously. Each Atlas Space maps to one Google account; events are read from all connected accounts and writes route to the account linked to the event's space.

---

## Architecture

### `GoogleAccountManager` (new)

`@MainActor ObservableObject` owned as `@StateObject` in `AtlasApp`. Replaces the single `GoogleAuthService` environment object.

- `@Published var accounts: [GoogleAuthService]` — up to 5 entries, ordered by slot index (0–4)
- `@Published var services: [GoogleCalendarService]` — parallel array, one per auth
- `func addAccount() async` — finds the next free slot index, creates a `GoogleAuthService(accountIndex:)`, runs the OAuth flow, fetches userinfo, appends to arrays
- `func removeAccount(at index: Int)` — disconnects, deletes Keychain entry, removes from arrays
- Persists slot count to `UserDefaults("google.accountSlots")` so accounts survive restarts

`AtlasApp` replaces:
```swift
@StateObject private var googleAuth = GoogleAuthService()
// .environmentObject(googleAuth)
```
with:
```swift
@StateObject private var googleAccountManager = GoogleAccountManager()
// .environmentObject(googleAccountManager)
```

### `GoogleAuthService` changes

- Add `init(accountIndex: Int = 0)` — all existing call sites pass 0 implicitly (backward compat)
- `GoogleKeychain` uses `account = "oauth-tokens-\(accountIndex)"` (was hardcoded `"oauth-tokens"`)
  - **Migration:** The existing `"oauth-tokens"` entry is read as slot 0 on first launch; re-keyed to `"oauth-tokens-0"` on first successful token load
- Add `@Published var email: String?` — populated from `/oauth2/v2/userinfo` after connect; persisted in `UserDefaults("google.email.\(accountIndex)")`
- Add `@Published var displayName: String?` — same source, `UserDefaults("google.name.\(accountIndex)")`

Userinfo fetch (added to `connect()` after token exchange):
```
GET https://www.googleapis.com/oauth2/v2/userinfo
Authorization: Bearer <access_token>
→ { "email": "...", "name": "..." }
```

### `Space` model changes

- Add `var googleAccountEmail: String?` — the email of the linked Google account (nil = no sync)
- Persisted via the existing Supabase write-through path in `AtlasDB`

### `AppState` changes

- Replace `weak var googleAuth: GoogleAuthService?` with `weak var googleAccountManager: GoogleAccountManager?`
- `func attachGoogle(_ manager: GoogleAccountManager)` replaces `attachGoogle(_ auth:)`
- `lastCalendarSyncError: String?` becomes `lastCalendarSyncErrors: [String: String]` — keyed by account email

---

## Data Flow

### Read (calendar pull)

`AppState` iterates `googleAccountManager.services` in a `TaskGroup`, fetching events in parallel. Per-account errors are stored in `lastCalendarSyncErrors[email]` without blocking other accounts. All results are merged into `externalEvents`.

### Write (event create/update/delete)

1. Look up `event.spaceName → space.googleAccountEmail`
2. Find matching `GoogleCalendarService` in `googleAccountManager.services` where `auth.email == space.googleAccountEmail`
3. Route write through that service; no-op if space has no linked account

### Error handling

- One failing account does not block others during pull
- Per-account errors shown in Settings next to each account row
- If a token refresh fails (e.g. revoked), that account shows "Reconnect" in Settings

---

## Settings UI

**Calendars section — Google Calendar subsection:**

```
GOOGLE ACCOUNTS
  [user@gmail.com]          [Disconnect]
  [work@company.com]        [Disconnect]
  [+ Add account]  (disabled at 5 accounts)
```

Each account row shows email and a per-account sync enabled/disabled toggle.

**Per-space Google account mapping:**

In the existing space list (or space detail), add a "Google account" picker:
```
Space: Work
  Google account: [work@company.com ▾]   (or "None")
```

---

## Keychain Migration

On first launch after update:
1. Attempt to load `"oauth-tokens"` (old key) from Keychain
2. If found, save it to `"oauth-tokens-0"` and delete old entry
3. Seed `UserDefaults("google.accountSlots") = 1`

---

## Out of Scope

- Per-account calendar selection (which of the account's sub-calendars to show) — future
- Series/recurring event write-back — already deferred in v1
- Google Docs/Drive multi-account — separate feature

---

## Open Questions

_None — all resolved during design review._
