# 10 — Roadmap (Build Order)

Not a scope cut — the full app ships. This is the order two people build it so each layer stands on the last.

## Phase 1 — Foundation
- Swift/SwiftUI app shell for **iOS + macOS** (shared codebase).
- **Supabase auth** — separate logins per person.
- Core **data model**: Spaces → Projects → Tasks/Events/Notes ([02](./02-data-model.md)).
- Offline-first local cache + realtime sync.
- Ship the **School + Personal** starter templates.

## Phase 2 — Unified Calendar
- **EventKit** (Apple Calendar) read/write.
- **Google Calendar** sync via backend.
- Day/Week/Month views, filter by space.
- **Drag-and-drop** task scheduling.
- → *We're using Atlas ourselves by the end of this phase.*

## Phase 3 — The Brain v1
- NL capture → structured items via OpenRouter/GPT-4o-mini.
- Auto-bucketing into spaces/projects.
- Review-and-confirm UI.

## Phase 4 — Canvas + Notes + Linking
- Canvas sync (classes + assignments, due dates + notes).
- Notes attachable to anything.
- `[[tag]]`-style references + backlinks.

## Phase 5 — Social
- Friends + availability.
- Shared spaces + group projects (shared tasks/scheduling/meetings).
- Row-Level Security for permissions.

## Phase 6 — Polish & extras
- Google Drive folders in projects.
- **Pomodoro focus pill** + **global pill hotkey** (ported + restyled).
- Paste-a-URL media.
- Email capture (Gmail → AI → tasks).
- Long-term goal suggestions.
- "Liquid glass" UI pass.

## Parallelization (2 devs)
- While one builds backend/data (Phase 1), the other can work on **UI design** (Claude / frontend-design mockups) — we're in person often, so coordinate live.

## Smart scheduling AI (Phase 3+)
- Suggest *when* to do unscheduled tasks around free/busy.

## Later / exploring
- iPad / Apple Notes sync.
- Windows port (separate rebuild — only if there's a user base).
- Monetization / public release.

---

## CURRENT STATE + NEAR-TERM ORDER (updated 2026-07-02)

Mobile Polish v2 shipped on feat/mobile-phase1 @ bede132 (15 tasks: freshness, truthful
sources, timezone-correct capture, space-color system, motion/haptics, capture hero, today
pill). Capture edge function is deployed + timezone-aware. Drew TestFlight-tested; feedback
became Wave 3.

Order of operations from here (updated after Wave 3 + W4 mini-wave SHIPPED @ 035a975 —
mobile v1 feature-final, pushed; Drew archives → TestFlight → Jonah):
1. **Server-side Google Calendar sync** — THE FOUNDATION: Supabase cron edge function,
   server-held Google tokens, sync-state tables, dedupe/conflict rules. Mac ↔ Google ↔
   iPhone live-sync with nothing open. Free plan suffices. (Calendar scope only, no CASA
   needed for personal/testing use.)
2. **Canvas ICS sync** — server-side on the SAME cron rails (ICS feed URL, no OAuth:
   fetch → parse → upsert). Cheapest project once #1 exists. Its task volume unlocks the
   parked mobile items (search, real project grouping, post-commit undo) which land with it.
3. **Google Docs ↔ notes link** — DECIDED (Drew, 2026-07-02): the **file-picker import
   path** (`drive.file` scope — user picks specific files), NOT broad readonly/monetized
   scopes. Keeps Google verification light so App Store publishing stays easy later.
   Mostly Mac-side UX once #1's token infra exists.
4. **Landing page** — independent web work (prelaunch/beta positioning; privacy policy +
   ToS required before App Store; scroll animation, three.js ok — Claude's call on
   direction). MUST include download links/buttons for the mobile AND Mac apps, even as
   empty placeholders pre-launch. Runs IN PARALLEL with any of the above.
5. Publish the app after that (and after the Mac revamp).

Design language name (for the Jonah pitch): **Editorial Minimal** — paper bg, ink
typography, no card chrome, clay brand accent, space colors = meaning.
