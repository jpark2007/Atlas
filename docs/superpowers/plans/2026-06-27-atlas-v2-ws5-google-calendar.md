# WS-5 — Google Calendar Sync (scaffold + unit tests, testing-blocked)

**Date:** 2026-06-27
**Branch:** `feat/daily-driver-v1`
**Spec:** `docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md` §4 WS-5

## Goal
Two-way Google Calendar sync. The live OAuth consent click can only be done by
the human, so this workstream **scaffolds + unit-tests the pure logic** and wires
the Settings button. Status = **testing-blocked** until the user adds a test user
and clicks Connect → Allow once.

## Why a Desktop-app loopback flow (design decision)
The OAuth client created in Google Cloud is a **Desktop app** client. The two
redirect styles Google supports for installed apps are:

1. **Loopback IP** — `http://127.0.0.1:<ephemeral-port>`, caught by a transient
   local listener. Recommended by Google for native desktop apps.
2. Custom URI scheme (reversed client ID).

`ASWebAuthenticationSession` only intercepts **custom URL schemes**, not an
`http://127.0.0.1` loopback. Since the task specifies a **loopback redirect**
(Desktop-app client), the live flow opens the system browser
(`NSWorkspace.open`) and captures the redirect with a one-shot `NWListener`
(Network framework) on a loopback port. This is the canonical desktop flow and
keeps the redirect off any registered URL scheme. (Documented here so the next
reader knows why `ASWebAuthenticationSession` is not used for the http loopback.)

The **pure, testable** parts — PKCE S256, the authorization-URL builder, the
token request bodies, the token/event JSON decoders, the event write body — are
the load-bearing logic and are unit-tested. The browser round-trip + listener is
inert until OAuth completes (guarded by `isConnected`), so it cannot break the
tree before the human authorizes.

## Secret handling (no secret in committed source)
- `Config/Secrets.xcconfig` — **gitignored** (already in `.gitignore`). Holds
  `GOOGLE_OAUTH_CLIENT_ID` + `GOOGLE_OAUTH_CLIENT_SECRET` copied from `.env.local`.
- `Config/Secrets.example.xcconfig` — **committed** template (empty values) so a
  fresh clone knows what to create.
- `project.yml` references the xcconfig via `configFiles:` and maps the two
  values into the generated Info.plist with
  `INFOPLIST_KEY_GoogleOAuthClientID` / `INFOPLIST_KEY_GoogleOAuthClientSecret`
  (works because `GENERATE_INFOPLIST_FILE: YES`).
- At runtime `GoogleOAuthConfig` reads them via
  `Bundle.main.object(forInfoDictionaryKey:)`. The client ID is allowed to be
  embedded; the secret stays out of git (xcconfig is ignored). For a Desktop
  client the secret is not a hard boundary — PKCE is the real protection.
- If `Config/Secrets.xcconfig` is missing on a fresh clone, Xcode treats the
  base config reference as empty (warning, not error) → build still green, the
  Google values are just empty until the file is created.

## Files
- `Config/Secrets.xcconfig` (gitignored, created locally — NOT committed)
- `Config/Secrets.example.xcconfig` (committed template)
- `project.yml` (add configFiles + INFOPLIST_KEY_* + redirect note)
- `Atlas/Services/GoogleAuthService.swift`
  - `enum GoogleOAuthConfig` — reads Info.plist client id/secret; endpoints; scopes.
  - `enum GoogleOAuth` — **pure** static helpers: `authorizationURL(...)`,
    `tokenExchangeBody(...)`, `refreshBody(...)`, `decodeTokens(from:now:)`.
    Reuses the existing module `PKCE` enum for verifier/challenge (S256).
  - `struct GoogleTokens: Codable` — access/refresh/expiry/scope.
  - `enum GoogleKeychain` — minimal Sec* wrapper (save/load/delete JSON blob).
  - `@MainActor final class GoogleAuthService: ObservableObject` —
    `@Published isConnected`, `connect()` (browser + loopback `NWListener`),
    `disconnect()`, `validAccessToken()` (refresh-if-expired), restore on init.
- `Atlas/Services/GoogleCalendarService.swift`
  - `enum GoogleCalendarMapper` — **pure**: `decodeEvents(from:defaultSpaceName:color:)`,
    `eventBody(for:)` (RFC3339 / all-day date), stable UUID from Google id.
  - `final class GoogleCalendarService` — `listEvents(start:end:)`,
    `createEvent(_:)` → google id, `updateEvent(googleEventID:_:)`.
- `Atlas/Views/Auth/SettingsView.swift` — wire the disabled "Connect" stub to
  `GoogleAuthService.connect()`; show connected / Disconnect state.
- `Atlas/App/AtlasApp.swift` — inject `GoogleAuthService` as an environment object.
- `AtlasTests/GoogleAuthServiceTests.swift` — PKCE S256, auth-URL builder, token
  bodies, token decode.
- `AtlasTests/GoogleCalendarMapperTests.swift` — event decode (timed + all-day),
  event write body. Compare formatter output to formatter output (never hardcode
  locale strings).

## Tests (TDD)
- PKCE: `PKCE.challenge(v)` == base64url(SHA256(v)) recomputed; verifier length in 43…128.
- Auth URL: host `accounts.google.com`, path `/o/oauth2/v2/auth`,
  `response_type=code`, `code_challenge_method=S256`, scope contains
  `…/auth/calendar.events`, `access_type=offline`, redirect + client id present.
  Asserted via URLComponents queryItems — not whole-string compare.
- Token bodies: form-urlencoded round-trip parse of grant_type/code/verifier/refresh.
- Token decode: expires_in → `expiresAt` computed from injected `now`.
- Event decode: timed event start/end via ISO8601DateFormatter compare; all-day
  via date-only formatter; title/notes mapped.
- Event write body: decode JSON back, assert summary + start.dateTime equals an
  ISO8601DateFormatter rendering of the source date.

## Build/verify
`xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`

## needsUser (testing-blocked)
1. Google Cloud → Auth Platform → Audience → Test users → add
   **drewkhalil@gmail.com** (and `lets.flowstate@gmail.com`).
2. Settings → Calendars → Google Calendar → **Connect** → sign in → **Allow** once.
3. (If a scope wall appears) add `…/auth/calendar.events` under Data Access.
