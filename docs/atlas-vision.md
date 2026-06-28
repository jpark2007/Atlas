# Atlas — Vision Document

**A smart life manager built around one unified calendar.**

- **Status:** Vision / design draft
- **Date:** 2026-06-26
- **Team:** 2 people (this is a personal project, built for our own use first)
- **Repo:** https://github.com/jpark2007/Atlas

> Read this file first for the big picture. Each subsystem has a detailed spec in [`specs/`](./specs/).
> A preliminary **iOS companion** design (capture + glance + widgets) is drafted in [`specs/11-mobile-companion.md`](./specs/11-mobile-companion.md) — parked for later, after the macOS app.

---

## 1. What Atlas is

Atlas is a **smart life manager** that organizes your entire life around **one unified calendar**. Instead of juggling Apple Calendar, Google Calendar, Canvas, a notes app, and a to-do list, everything lives in Atlas — aggregated, intelligently bucketed, and schedulable by dragging tasks onto your timeline.

The magic is twofold and equal:
1. **Aggregation** — one native calendar that merges Apple + Google + Canvas + Atlas's own items, with *you* choosing which calendar is your "main."
2. **Intelligence** — you brain-dump your life in plain English ("essay due Thursday, gym 3x this week, dinner with mom Sunday") and Atlas parses it into events/tasks, files each into the right part of your life, and suggests *when* to do the unscheduled ones.

It's organized into **Spaces** (School / Personal / Business…) so different parts of life stay separate but live in one app. You can add friends, share spaces and projects, see each other's availability, and collaborate on group work.

## 2. Who it's for

Built by us, for us (students juggling classes + personal life + side projects) — but designed from day one to support **individual accounts** so other people can use it too. Not monetized now; possible monetization/publication later, which is why the account system and backend are built to scale even though we start with just the two of us.

## 3. The core mental model

```
Spaces  (School / Personal / Business …)   ← top-level "scenes" / buckets
  └── Projects  (in School, Projects = Classes)
        └── Tasks · Events · Notes          ← every item is a linkable node
```

- **Spaces** are lenses on your life. App starts with **School** + **Personal** templates; add more (Business, etc.) over time. A space can be **private** or **shared**.
- **Projects** live inside spaces and bundle tasks + events + notes + a Google Drive folder. In the **School** space, **projects are Classes** (auto-synced from Canvas). Projects can be solo or **group/shared**.
- **Items**: **Tasks** (must belong to a space; *may* sit outside a project), **Events** (timed, on the calendar), **Notes/lists**. Every item is a **linkable node** — you reference/tag items to each other (a simplified, tag-style version of Obsidian's `[[links]]`) and see backlinks.
- Everything flows into **one unified calendar** — the home screen.

## 4. Feature overview

| Area | What it does | Spec |
|---|---|---|
| **Unified Calendar** | Aggregates Apple + Google + Canvas + Atlas into one view; pick your main calendar; drag-drop tasks onto time; filter by space. | [03](./specs/03-unified-calendar.md) |
| **The Brain (AI)** | NL capture, auto-bucketing, smart scheduling, long-term goal suggestions. OpenRouter → GPT-4o-mini. | [04](./specs/04-ai-brain.md) |
| **Spaces & Projects** | The life-manager shell: spaces, projects, tasks, notes. | [02](./specs/02-data-model.md) |
| **Canvas** | Sync classes + assignments (auto due dates + notes). | [05](./specs/05-canvas.md) |
| **Notes & Linking** | Notes attachable to anything; `[[tag]]`-style references + backlinks. | [06](./specs/06-notes-and-linking.md) |
| **Social** | Friends, see availability, shared spaces & group projects. | [07](./specs/07-social.md) |
| **Email Capture** | AI scans connected email, drafts tasks tagged "from email." | [08](./specs/08-email-capture.md) |
| **Integrations** | Google Drive folders in projects, paste-a-URL media (Spotify/podcasts), Pomodoro focus pill. | [09](./specs/09-integrations.md) |

## 5. How it's built (at a glance)

- **App:** Swift / SwiftUI, **one shared codebase for iOS + macOS**. Apple-only for now (a Windows port would be a separate rebuild — a "when we have users" problem, not now).
- **Backend:** **Supabase** — auth (separate logins per person), Postgres (shared data), realtime sync (phone ↔ Mac ↔ friends), and Edge Functions to safely proxy the OpenRouter key + Google/Canvas/Gmail integrations.
- **AI:** OpenRouter API with **GPT-4o-mini** (model is swappable later via OpenRouter).
- **Sync:** offline-first local cache; Supabase realtime keeps devices and collaborators in sync.

Full detail in [`specs/01-architecture.md`](./specs/01-architecture.md).

## 6. Build order

We build in layers so each stands on the last (full detail in [`specs/10-roadmap.md`](./specs/10-roadmap.md)):

1. **Foundation** — app shell (iOS+Mac), Supabase auth, Spaces/Projects/Tasks data model + offline sync.
2. **Unified Calendar** — Apple (EventKit) + Google sync, calendar views, drag-drop scheduling.
3. **The Brain v1** — NL capture + auto-bucketing.
4. **Canvas + Notes + Linking.**
5. **Social** — friends, availability, shared spaces/projects.
6. **Polish** — Drive folders, Pomodoro focus pill, media URLs, email capture, goal suggestions.

We're *using Atlas ourselves by the end of step 2.*

## 7. Carried over from the old prototype

Two pieces from our earlier Atlas prototype are being ported into this app, then the old project is deleted:
- **Global pill hotkey** — system-wide shortcut that summons a floating command pill.
- **Focus-mode pill timer** — compact floating Pomodoro/focus timer.

Both will be restyled (cleaner, "liquid glass" look). See [`specs/09-integrations.md`](./specs/09-integrations.md). Harvested code lives in [`carryover/`](./carryover/) until integrated.
