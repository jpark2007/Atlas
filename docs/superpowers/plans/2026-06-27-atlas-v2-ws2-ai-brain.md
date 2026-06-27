# WS-2 — AI Brain Upgrade (plan)

**Date:** 2026-06-27 · Branch: `feat/daily-driver-v1`
**Spec:** docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md §4 WS-2

## Goal
Multi-item paragraph parsing + real space/project context injection. Cannot deploy
(endpoint 404, user must redeploy). Code + edge-function source only; mark redeploy needed.

## Changes

### 1. Edge function `supabase/functions/capture/index.ts`
- Accept body `{ text, spaces?: [{ name, projects: [string] }] }`.
- Build the system prompt dynamically: when `spaces` is present + non-empty, inject the
  user's real space names and their project names (replacing the hardcoded
  School/Work/Personal/Health/Finance/Other list).
- Return an **array** of capture items. OpenAI `response_format: json_object` requires a
  top-level object, so instruct the model to emit `{ "items": [ ... ] }`, then unwrap
  `items` and return the bare JSON array to the client. Tolerate the model returning a
  bare object/array too.
- Split a multi-item paragraph into multiple objects.

### 2. Client `Atlas/Services/AtlasAI.swift`
- `CaptureContextSpace { name, projects: [String] }` (Codable) + `AtlasAI.context(from:[Space])`.
- `AtlasAI.requestBody(text:spaces:)` — testable JSON body builder (omit `spaces` when empty).
- `AtlasAI.decodeResults(from:Data) -> [CaptureResult]` — decode array; tolerate a single
  object (wrap as one-element array). Testable.
- `parse(_:spaces:)` now returns `[CaptureResult]`, sends context, uses the two seams above.

### 3. Apply seam `Atlas/Data/AppState+Capture.swift`
- `AppState.applyCapture(_:CaptureResult) -> CaptureOutcome` — the per-kind switch
  (event/note/task/unknown) extracted from CaptureOverlay so it is unit-testable and
  reused for every item in a multi-item capture.

### 4. `Atlas/Views/Capture/CaptureOverlay.swift`
- Build context from `state.spaces`, call array `parse`, loop `applyCapture` over results,
  show count-aware confirmation. Keep degraded plain-task fallback on ANY error / empty.

### 5. `Atlas/Views/Capture/CaptureOutcome.swift`
- `CaptureOutcome.confirmation(for:[CaptureOutcome])` — single item keeps per-kind copy;
  multiple → "✓ Added N items".

## Tests (XCTest, @testable import Atlas)
- AtlasAIDecodeTests: decode JSON array (multi), single-object tolerance, requestBody shape
  (with + without context, decoded back — never string-compare), context(from:) mapping.
- AppStateCaptureTests / new: applyCapture for task(with/without date), event(with/without
  start), note, unknown kind; multi-item confirmation count via CaptureOutcome.confirmation(for:).

## Cannot do
- Deploy / end-to-end test (endpoint 404). List "redeploy capture function" under needsUser.
</content>
</invoke>
