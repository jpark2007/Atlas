# Running: iOS Interpretation of the 2026-08 Redesign

All redesign phases are **Mac-first**; this doc accumulates the iOS take so mobile ships the same mental model, natively. Update alongside each phase doc.

## Phase 1 — School
- Classes/Term browse: class list → class hub (assignments, notes, Class info card). Term switcher tucked behind the School header, not a nav level.
- Schedule ingestion (ICS link, screenshot upload, manual) works from iOS too — screenshot upload is arguably *more* natural on the phone (camera roll).
- "Enable School" setup must be completable entirely on iOS.

## Phase 2 — Time model / calendar
- Same five concepts, same channel rules (color = class, dashed = work session, deadlines never blocks).
- Day view: due markers + a compact "due today" header group (UpAhead-style LATE / DUE TODAY / TOMORROW list works well on phone width).
- Side rail has no room on phone → "Needs time" section (already exists) is the rail's mobile form; long-press or drag-to-schedule creates work sessions.
- Late bar: same pin/dismiss-daily semantics, rendered as a collapsible group at top of Today.
- Amber/red semantics identical.

## Phase 3 — Sync/dedup
- **Apple Calendar connect from iPhone (new requirement):** iOS gains EventKit connect + read; display-time merge/dedup shared via AtlasCore. Write-back settings stay device-local.
- Dedup logic lives in shared AtlasCore pure functions so Mac and iOS render the identical collapsed pool.

## Phase 4 — Brain Dump
- Commit + chip corrections is **required** on iOS: after capture, results sheet with per-item Class ▾ / Type ▾ / Due ▾ chips (thumb-sized), immediate commit, undo.
- Draft persistence: buffer saved every keystroke; survives app kill; pending queue covers all failure modes.

## Phase 5 — Simplicity/IA
- Settings mirror Mac's grouping/naming 1:1 (same words, same groups) so knowledge transfers between devices.
