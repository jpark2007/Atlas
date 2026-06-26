# Atlas

A **smart life manager** built around one unified calendar — for iOS + macOS.

Atlas aggregates Apple Calendar, Google Calendar, and Canvas into a single native calendar,
organizes your life into **Spaces** (School / Personal / Business…), and uses AI to turn plain-English
brain-dumps into scheduled tasks bucketed into the right part of your life.

> Personal project, built by two people for our own use first. Possible public release later.

## 📚 Start here

- **[docs/atlas-vision.md](docs/atlas-vision.md)** — the full vision (read this first).
- **[docs/specs/](docs/specs/)** — detailed spec per subsystem (architecture, data model, calendar, AI, Canvas, notes/linking, social, email, integrations, roadmap).
- **[docs/carryover/](docs/carryover/)** — code lifted from an earlier prototype (global pill hotkey + focus timer), pending integration.

## Core idea

```
Spaces  (School / Personal / Business …)
  └── Projects  (in School → Classes, synced from Canvas)
        └── Tasks · Events · Notes   ← every item is a linkable node
```

Everything flows into **one unified calendar**. Drag tasks onto your timeline; the AI helps you
capture, bucket, and schedule.

## Stack

| Layer | Choice |
|---|---|
| App | Swift / SwiftUI — shared iOS + macOS codebase |
| Backend | Supabase (auth, Postgres, realtime, edge functions) |
| AI | OpenRouter API → GPT-4o-mini |
| Calendar | EventKit (Apple) + Google Calendar API |

See **[docs/specs/01-architecture.md](docs/specs/01-architecture.md)** for detail.

## Roadmap (build order)

1. Foundation — app shell, auth, data model, sync
2. Unified Calendar — Apple + Google, drag-drop scheduling
3. The Brain v1 — NL capture + auto-bucketing
4. Canvas + Notes + Linking
5. Social — friends, availability, shared spaces/projects
6. Polish — Drive, Pomodoro pill, media URLs, email capture, goal suggestions

Full detail: **[docs/specs/10-roadmap.md](docs/specs/10-roadmap.md)**.

## Team

Two collaborators. We're in person often — backend + UI work can proceed in parallel.
