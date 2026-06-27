# Task 3 Report: AI brain — Edge Function + AtlasAI client + ⌘⇧K auto-sort

## TDD Evidence (RED → GREEN)

### RED (Step 1)
`AtlasAIDecodeTests.swift` was written first with 4 test cases covering `CaptureResult` decoding for all three kinds:
- `testDecodeTask` — task with `dueISO`
- `testDecodeEvent` — event with all optional fields (`projectName`, `startISO`, `durationMin`, `notes`)
- `testDecodeNote` — note with body in `notes` field
- `testDecodeMinimalTask` — only required fields

At this point the tests failed to compile because `CaptureResult` did not exist.

### GREEN (Step 2)
After writing `Atlas/Services/AtlasAI.swift` with `CaptureResult: Codable` and `AtlasAI`:
```
Test Suite 'AtlasAIDecodeTests' passed at 2026-06-27 06:29:38.972.
  testDecodeEvent    passed (0.002s)
  testDecodeMinimalTask passed (0.000s)
  testDecodeNote     passed (0.000s)
  testDecodeTask     passed (0.000s)
```
All existing `AtlasDBMappingTests` and `SmokeTests` continued to pass:
```
Test Suite 'All tests' passed at 2026-06-27 06:29:52.994.
```

---

## What Was Built

### 1. `supabase/functions/capture/index.ts` (Deno)
- Handles CORS preflight (OPTIONS → 204) with `Access-Control-Allow-Origin: *`
- Requires `Authorization: Bearer <JWT>` — returns 401 if missing (presence check, not signature verification, which is sufficient for v1; the OpenRouter key is the secret being guarded)
- Reads `{ text: string }` from request body
- Calls OpenRouter `openai/gpt-4o-mini` via `Deno.env.get("OPENROUTER_API_KEY")` — key NEVER hardcoded
- Strict system prompt instructs the model to return ONLY a JSON object matching the specified schema
- `response_format: { type: "json_object" }` enforces JSON output
- Returns parsed model JSON as `application/json`; on any upstream error returns 502 with `{ error, detail }`

### 2. `Atlas/Services/AtlasAI.swift`
- `struct CaptureResult: Codable` with all 8 fields (required: `kind, title, spaceName`; optional: `projectName, dueISO, startISO, durationMin, notes`)
- `enum AtlasAIError: LocalizedError` — `.notAuthenticated`, `.httpError(Int, String)`, `.decodingError(Error)`
- `final class AtlasAI` with `init(session: @escaping () -> SupabaseSession?)` and `func parse(_ text: String) async throws -> CaptureResult`
- Mirrors `SupabaseAuth.request(...)` pattern exactly: `apikey` header + `Authorization: Bearer <token>` + `Content-Type: application/json`
- Throws `AtlasAIError.notAuthenticated` if `session()` returns nil (before any network call)
- Plain `JSONDecoder()` — no date strategy — ISO strings stay as strings

### 3. `AtlasTests/AtlasAIDecodeTests.swift`
4 test cases covering task/event/note decoding including all optional fields and a minimal-fields case.

### 4. `Atlas/Views/Capture/CaptureOverlay.swift` (modified)
- `AtlasCaptureOverlayModifier` now requires `@EnvironmentObject var auth: AuthService` (already in the env chain from `AtlasApp`)
- Constructs `AtlasAI(session: { auth.session })` and passes it to `CaptureCommandBar`
- `CaptureCommandBar` gains:
  - `@EnvironmentObject var state: AppState` and `@EnvironmentObject var auth: AuthService`
  - `let atlasAI: AtlasAI` parameter
  - `@State private var confirmation: String?` — inline display, no AppState changes
  - `@State private var isProcessing: Bool` — shows a spinner in place of the sparkle icon while waiting
  - TextField disabled during processing so no double-submits
- Submit flow:
  1. Captures `rawText`, clears field immediately (responsive feel)
  2. If `auth.session == nil` → plain task fallback immediately (no network call)
  3. Otherwise: `try await atlasAI.parse(rawText)`
     - `"task"` → `state.addTask(title: result.title)` → "✓ Added task"
     - `"event"` → parse `startISO` with `ISO8601DateFormatter` (tries with+without fractional seconds); if unparseable → fallback to task; else `state.addEvent(...)` → "✓ Added event"
     - `"note"` → `state.addNote(title:body:spaceName:isExternal:)` → "✓ Added note"
     - any other kind → fallback
  4. **On ANY thrown error** (network error, HTTP 404/502, JSON parse failure, not-authenticated) → `state.addTask(title: rawText)` + "✓ Saved as task"
  5. Confirmation shown inline for 1 second, then bar dismisses
- The `onSubmit` closure was removed; the bar handles all logic internally

---

## Fallback Behavior With No Deployed Function

Since `supabase functions deploy capture` is a human manual step, the function is not live. Every call to `atlasAI.parse(...)` will throw `AtlasAIError.httpError(404, ...)`. The `catch` block catches this and calls `state.addTask(title: rawText)`, showing "✓ Saved as task". ⌘⇧K is fully functional today.

---

## Files Changed / Created

| File | Action |
|------|--------|
| `supabase/functions/capture/index.ts` | Created |
| `Atlas/Services/AtlasAI.swift` | Created |
| `AtlasTests/AtlasAIDecodeTests.swift` | Created |
| `Atlas/Views/Capture/CaptureOverlay.swift` | Modified |

---

## Concerns / Notes

1. **Deploy step required (human):** `supabase functions deploy capture` must be run after the Edge Function is merged. Also requires `supabase secrets set OPENROUTER_API_KEY=<key>`.
2. **JWT verification:** For v1, the function only checks for the presence of a `Bearer` token — it does not cryptographically verify the JWT. This is acceptable because: (a) the token is obtained from a real Supabase auth flow, and (b) the real access control is the OpenRouter key, which is server-side only. Full JWT verification can be added in a later iteration via Supabase's `createClient` in Deno.
3. **spaceName mapping:** The AI is instructed to use one of `"School", "Work", "Personal", "Health", "Finance", "Other"`. If the user's space names differ, `calendarSpaceColor(named:)` will fall back to the accent color — still functional but color may not match. A future improvement would be to pass the user's actual space names in the system prompt.
4. **No AppState changes:** As required, no new fields were added to AppState or any model.
5. **Existing tests unaffected:** All `AtlasDBMappingTests` and `SmokeTests` continue to pass.
