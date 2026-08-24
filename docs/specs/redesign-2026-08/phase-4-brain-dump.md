# Phase 4 — Brain Dump (agreed 2026-08-24)

Part of the 2026-08 redesign. Status: **discussion converged; not yet planned/implemented.**

## Principles

Brain Dump stays the universal input: one box, natural language, Atlas does the admin. AI does not need to be perfect — it needs to be **fast to correct**.

## 1. Draft persistence (reliability — priority fix)

Rule: **if I typed it, Atlas saved it.**

- **Mac:** the capture overlay currently *discards* the draft by design (panel is nil'd on hide so `@State` resets — `CapturePanelController.hide()`). Change: persist the draft buffer as you type (local file/UserDefaults); Esc or focus-loss keeps the draft; next summon restores it. Add an offline pending queue (Mac has none today).
- **iOS:** capture text is plain `@State`, lost on app kill. Persist the buffer on every keystroke (SceneStorage/UserDefaults); the existing `PendingCaptureQueue` (network-failure only) extends to cover 413/5xx and app-kill cases.

## 2. Smarter parsing — give the model the user's world

The parse prompt gets real context:

- Class list with codes/names (so "bio lab" → BIO 201) + active term dates
- Upcoming deadlines/assignments (so "the essay" resolves to an existing item instead of creating a duplicate — capture can UPDATE/attach, not only create)
- Timezone/locale + "tomorrow/next week" resolution (deterministic repair module already exists)
- Recent capture history for referents

Classification target: task vs event vs deadline vs note, class attribution, due date/time.

## 3. Commit + chip corrections (the flow)

- Enter → items **commit immediately**. No review screen, no countdown, no "did it save?" ambiguity.
- Results remain on screen as item cards, each with **three tappable chips: Class ▾ · Type ▾ · Due ▾** plus Undo. Tap chip → one-tap menu → fixed live (the committed item updates).
- Walk away = committed as parsed. Corrections are ≤2 clicks. Per-item undo + "undo all" (capture history already exists as the substrate).
- Low-confidence parse = subtle marker on the chip, never a blocking dialog.
- **Review screens are reserved for batch imports only** (syllabus/schedule scan — Phase 1), never for a typed capture.

## 4. Mobile parity (required)

The commit+chips flow must exist on iOS in native form — chips as tap targets sized for thumbs, results sheet after capture, same immediate-commit rule. See `mobile-interpretation.md`.

## Research notes

Friction ranking from prior art: inline tokens (Todoist) ≈ live manipulable preview (Fantastical) < auto-commit+undo < modal review. Todoist-style live tokens rejected for v1: heavier build, poor fit for multi-item dumps (our main case). Revisit as polish later.
