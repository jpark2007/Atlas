# 01 — Architecture

## Stack

| Layer | Choice | Why |
|---|---|---|
| App | **Swift / SwiftUI**, shared codebase for **iOS + macOS** | One language, runs on both, deep Apple Calendar access via EventKit. Apple-only for now. |
| Backend | **Supabase** | Auth + Postgres + realtime + Edge Functions in one tool — ideal for 2 devs. |
| AI | **OpenRouter** API, model **GPT-4o-mini** | Swappable model behind one endpoint; key hidden server-side. |
| Sync | Local cache (offline-first) + Supabase realtime | Instant open, works offline, live multi-device + multi-user sync. |

## Diagram

```
┌─────────────────────────────────────────────┐
│   Atlas App  (Swift / SwiftUI)              │
│   iOS + macOS, one shared codebase          │
│   • Unified calendar, drag-drop, spaces     │
│   • EventKit → Apple Calendar (read/write)  │
│   • Local cache (offline-first)             │
└───────────────┬─────────────────────────────┘
                │  HTTPS (authenticated)
┌───────────────▼─────────────────────────────┐
│   Backend  (Supabase)                       │
│   • Auth — separate login per person        │
│   • Postgres — spaces, projects, tasks,     │
│     notes, links, friends, shared data      │
│   • Realtime — device ↔ device ↔ friends    │
│   • Edge Functions — proxy OpenRouter,       │
│     Google (Cal+Drive), Canvas, Gmail       │
└───────┬───────────┬───────────┬─────────────┘
        │           │           │
   ┌────▼───┐  ┌────▼────┐  ┌───▼─────┐
   │OpenRtr │  │ Google  │  │ Canvas  │
   │GPT-4o- │  │ Cal +   │  │  API    │
   │ mini   │  │ Drive   │  │ (LMS)   │
   └────────┘  └─────────┘  └─────────┘
```

## Key principles

- **Secrets never live in the app.** OpenRouter key, Google/Canvas/Gmail OAuth secrets all live in Supabase Edge Functions. The app calls *our* backend, never third-party APIs with embedded keys.
- **Offline-first.** The app holds a local copy of the user's data; reads/writes hit local storage immediately and sync to Supabase in the background. Apple Calendar (EventKit) is read/written directly on-device.
- **Multi-user from day one.** Supabase auth means every person has their own account. Sharing (spaces/projects/availability) is enforced with Postgres Row-Level Security so users only see what they're allowed to.
- **Realtime sync.** Supabase realtime pushes changes so your phone, your Mac, and collaborators stay current without manual refresh.

## What talks to what

- **Apple Calendar** → directly on-device via **EventKit** (read + write).
- **Google Calendar / Drive, Canvas, Gmail** → via Supabase Edge Functions (OAuth + secrets server-side). Scheduled functions handle periodic pulls (Canvas sync, email scan).
- **OpenRouter (AI)** → only ever via an Edge Function that injects the key.

## Free-tier note

Supabase free tier (500MB Postgres, ~50K monthly active auth users, 500K function calls/mo) comfortably covers us two + early individual users. Free projects pause after ~1 week of inactivity — a non-issue once we use it daily. Upgrade when there's a real user base (the "monetize later" trigger).

## Open questions

- Exact local-cache mechanism (SwiftData vs. a hand-rolled cache over Supabase) — decide in Foundation phase.
- Conflict resolution strategy for offline edits to shared items (last-write-wins to start).
