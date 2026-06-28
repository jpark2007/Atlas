# 11 — Mobile Companion (iOS)

**A deliberately-minimal iPhone companion: capture on the go, glance at your day.**

- **Status:** Preliminary design draft — approved in brainstorm, parked for later review (build the macOS app first)
- **Date:** 2026-06-28
- **Scope:** iOS app + widgets only. NOT a port of the Mac cockpit.
- **Reviewers:** drew + design partner (capture mockups approved as direction; visuals to be molded to the macOS rebrand)

> Read [`../atlas-vision.md`](../atlas-vision.md) and [`01-architecture.md`](./01-architecture.md) first. This spec assumes the Supabase backend + data model already exist (they do — the phone is another client on them).

---

## 1. What it is (and isn't)

The phone is **not** a second Atlas. Its only two jobs:

1. **Capture** — whip it out, dump a thought (type or speak) before it's gone, let the AI sort it.
2. **Glance** — see today's schedule, what's next, what's due, and check things off.

Everything heavy — projects, notes, the metrics/graph view, deep planning — **stays on the Mac.** The phone is the mobile front door for getting things *in* and seeing what's *now*.

**Out of scope (v1):** notes · project management · metrics/graph · week view · quiet hours · auto-suggest scheduling · drag-to-schedule · 2×2 widget · inline lock accessory.

---

## 2. Architecture

| Layer | Choice | Why |
|---|---|---|
| App | **Native SwiftUI (iOS)** | Same language as the Mac app; touch-native views built fresh. |
| Logic | **Shared Swift package** | `Models`, `AtlasDB`, `AtlasAI`, capture parsing are pure Swift (no AppKit) — both apps consume one package. |
| Backend | **Same Supabase project** | Same auth, same row-level security, same `capture` Edge Function. The phone is *another client*, not a re-build. |
| AI | **Existing `capture` Edge Function** | Brain-dump → structured items already deployed and platform-agnostic. |
| Sync | Supabase + local cache | Sign in with the same Atlas account → your data appears. |

```
┌───────────────────────────┐     ┌───────────────────────────┐
│  Atlas macOS (cockpit)    │     │  Atlas iOS (companion)    │
│  full planning surface    │     │  capture + glance + widget│
└─────────────┬─────────────┘     └─────────────┬─────────────┘
              │   shared Swift package           │
              │   (Models / AtlasDB / AtlasAI)   │
              └───────────────┬──────────────────┘
                              │ HTTPS (authenticated, RLS)
                  ┌───────────▼────────────┐
                  │   Supabase backend     │
                  │   auth · Postgres ·    │
                  │   RLS · `capture` fn   │
                  └────────────────────────┘
```

**Key principle:** the phone re-uses logic, never re-implements it. New iOS code is limited to **views, widgets, notifications, and on-device speech.**

---

## 3. App structure

Three tabs + a settings gear. **Opens to Schedule.**

```
┌──────────────────────────────┐
│ Atlas                      ⚙︎ │   ← settings = gear, not a tab
│        ( screen body )       │
├─────────┬─────────┬──────────┤
│Schedule*│ Capture │  Tasks   │   *home / launch tab
└─────────┴─────────┴──────────┘
```

(The approved capture mockup labelled tabs *Today / Spaces / You* — reconcile to **Schedule / Capture / Tasks + gear** in the visual pass.)

---

## 4. Screens

### 4.1 Schedule (home)

A clean **daily view** — swipe ←/→ between days. Un-timed tasks due that day are **pinned on top** so you can give them a time right there.

```
Schedule (HOME)              [📅]  [space filter]   ← 📅 → Calendar (month) page
‹  Tue · Jun 28  ›    (swipe ← → for days)
──────────────────────────
Needs a time (2)             ← tap → set time → drops onto timeline below
  ▸ Email Dr. Lee
  ▸ Read ch. 4
──────────────────────────
 9a ── Lecture
11a ── Gym
 2p ── (free)
```

- **📅 button** → separate **Calendar (month) page** → tap a day → bounce back to Schedule on that day. Month is pure navigation; the daily view stays uncluttered.
- **Scheduling model:** tap a task → **set a specific time** yourself (no auto-suggest — that lives on the Mac; no drag on phone).

### 4.2 Capture (hero)

Type **or** speak. On-device `SFSpeechRecognizer` (same engine as the Mac, available on iOS).

Flow (all five states approved in mockup):

1. **Empty** — inviting dump box ("What's on your mind?"), mic to speak, "OR + Add a task manually".
2. **Listening** — live transcription + waveform, "we'll organise it for you".
3. **Thinking** — calm animated "Sorting it out…" (pulsing core, not a spinner).
4. **Result card** — centered rounded card listing every created item: *title · space color chip · tag · due*. Tap a chip/tag/date to fix; swipe a row to delete; **"Looks good — add all N"** commits; **"Undo this batch"** discards.
5. **Manual add** — bottom sheet: title · Space · Tag · Due date · Set-a-time toggle · "Add task". No AI.

- **One shared result card** for both voice and typing.
- **Offline:** hold the raw text on-device, process the moment signal returns (the AI lives server-side).

### 4.3 Tasks

All open tasks, with a grouping toggle at top.

```
Tasks                         [space filter]
[ Project | Due ]   ← default Project, remembers your pick
─── CS 351 ───
  ▸ …
─── Personal ───
  ▸ …
```

- **`Due`** mode reuses the Mac's `TaskGrouping.byDueBucket` (Overdue / Today / This week / Later).
- Check off inline; swipe a row for actions (set time / delete).

### 4.4 Settings (⚙︎ gear — in-app only)

Account / sign-out · default space · notifications (§7) · voice permission · Google-connected status. **No system-level settings.**

---

## 5. Global behaviors

- **Space filter** — `All / School / Personal / …` — **shared across Schedule + Tasks.** Set once, the whole app narrows. It is a **view filter only**: Capture can still route a dump to *any* space (so a personal thought dropped while filtered to "School" is never lost).
- **Swipe** — left/right on Schedule = prev/next day; row swipe on Tasks = quick actions. **Not** used for tab-switching (would collide with day-swipe and row-swipe).

---

## 6. Capture states reference

| State | What the user sees | Deep link in |
|---|---|---|
| Empty | Dump box + mic + manual-add | `atlas://capture` |
| Listening | Transcription + waveform + stop | `atlas://capture?mic=1` |
| Thinking | "Sorting it out… finding projects, tags & due dates" | — |
| Result | "Here's what I made · N items" card, editable chips | — |
| Manual | New-task sheet (Space / Tag / Due / time) | — |

---

## 7. Notifications

**The mechanism that matters:** local notifications, once scheduled, are owned by **iOS** — they fire whether Atlas is backgrounded or killed. The app only needs to have *scheduled* them while last open / on background refresh (iOS keeps ~64 pending). This is how the phone reminds you without the app running. Remote push (APNs) — how Google Calendar works — is only needed so the phone *learns about* events added/changed elsewhere (e.g. on the Mac) while it was asleep.

**Plan:**
- **v1 — local notifications.** Event + task reminders, daily digest, overdue nudges. Works offline; no server infra.
- **Fast-follow — APNs silent-push freshness layer**, hosted in a **Supabase Edge Function** (calls Apple's APNs HTTP/2 API with the `.p8` key; device tokens in a table; DB trigger fires on row change). Adopt if same-day cross-device changes start getting missed. *Kept on the radar — APNs is known/easy.*

**Settings (curated — no switch-wall):**

| Control | Type |
|---|---|
| Notifications | master toggle |
| Notify me about | Events · Tasks due · Daily digest · Overdue nudges |
| Remind me before | picker — At time / 5 / 15 / 30 / 60 min |
| Daily digest | time picker (shown only when digest on) |
| Spaces | multi-select — All / choose |

(No quiet hours — cut by decision.)

---

## 8. Widgets

One idea — **your day at a glance + one-tap capture** — surfaced where you'll look. Lean kit, no redundancy.

| Surface | Family | Content | Tap → |
|---|---|---|---|
| Home | **Medium 4×2** | Header + next 2–3 items + "Need a time" pill | rows → `atlas://today` · mic → `atlas://capture` |
| Home | **Large 4×4** | "Today" header, timeline of 4 items + NOW marker, "Need a time (N)" footer | rows → `atlas://today` · need-a-time → `atlas://unscheduled` |
| Lock screen | **Rectangular** | Next item + time | busy → `atlas://today` · empty → `atlas://capture` |
| Lock screen | **Circular** | Count left (gauge ring) | `atlas://today` |
| Control Center / Action Button | **Control** | Refined capture glyph + "Capture" | `atlas://capture` (hold → `?mic=1`) |

- Home widget is **one widget, two sizes** — the user picks medium or large.
- Home widget is **configurable** — pin one to a specific space (`atlas://today?space=id`).
- **Lock screen accessories** render in iOS's monochrome/vibrant tint — design in white/gray hierarchy with the accent ring as the one tinted element. *User likes the concept; pending partner's visual sign-off — fine to ship as an extra.*
- **Cut:** standalone small 2×2 (covered by medium + lock), inline lock accessory (covered by rectangular).

---

## 9. Design tokens

Visual style **inherits the macOS rebrand** (leaning faded-neumorphic). Tokens below are the agreed starting system.

**Color**
- bg radial `#18181d → #101013 → #0b0b0b` · card grad 160° `#16161b → #0e0e11`
- accent `#ff8c42` (hi `#ff9d5c`) · text `#f4f3f1` / `#85848b` muted / `#67666d`
- hairline `rgba(255,255,255,.06)`
- spaces — Work `#5a8dee` · Health `#5cb27e` · Errands `#d4a05a` · School `#9b8cf0`

**Radii** — widget S/M `24` · L `28` (continuous) · chip `13` · control `18–20`

**Neumorphic shadow**
- raised — `8 8 20 rgba(0,0,0,.5)` + inner `−6 −6 16 rgba(255,255,255,.022)` + `1px rgba(255,255,255,.04)` top edge
- recessed — `inset 4 4 11 rgba(0,0,0,.55)` + `inset −3 −3 9 rgba(255,255,255,.02)`

**Type — SF Pro Rounded** — clock 74/600 · next-time 33/700 · title 17–22/700 · row-title 15.5/600 · time 14–15/700 · label-caps 10.5–12/700 +0.8ls · meta 12.5–13/500. Body ≥ `#85848b` on card meets WCAG AA.

**Deep links** — `atlas://today` · `atlas://capture` · `atlas://capture?mic=1` · `atlas://unscheduled` · `atlas://today?space=id`

**Rule** — orange = *now / live / brand only*; the capture affordance is a **refined glyph, never a fill.**

---

## 10. Open / TBD

- Final visual style inherits the **macOS rebrand** (faded-neumorphic lean).
- "Orange overused" refinement on the capture screen (the big solid-orange confirm bar reads generic — reserve orange for live/now/brand, use raised-neutral for confirmations). Parked for the visual pass.
- Lock-screen visual redesign (concept approved, look TBD).
- Tab-naming reconcile (mockup said Today/Spaces/You; spec is Schedule/Capture/Tasks).

---

## 11. Where this sits in the build order

**After** the macOS daily-driver lands and the backend is exercised end-to-end (see [`10-roadmap.md`](./10-roadmap.md)). The shared Swift package is the bridge: extract `Models`/`AtlasDB`/`AtlasAI` into it during the Mac work so the iOS app is mostly views + widgets on day one. When ready to build, run the brainstorming → writing-plans flow to turn this spec into an implementation plan.

---

## Appendix A — Design generation prompts

Saved for later review / regenerating mockups. Paste the **Style block** at the top of any widget prompt.

### Style block (prepend to widget prompts)
```
You are a senior product designer. Render high-fidelity iOS widget mockups for
Atlas — a minimal capture-and-glance companion to a macOS life-manager. Use
this exact design system (do not improvise colors/shadows):

COLOR   bg radial #18181d→#101013→#0b0b0b · card grad 160° #16161b→#0e0e11
        accent #ff8c42 (hi #ff9d5c) · text #f4f3f1 / #85848b (muted) / #67666d
        hairline rgba(255,255,255,.06)
        space dots: Work #5a8dee · Health #5cb27e · Errands #d4a05a · School #9b8cf0
RADII   widget S/M 24 · L 28 (continuous corners) · chip 13 · control 18–20
NEU     raised: shadow 8 8 20 rgba(0,0,0,.5) + inner −6 −6 16 rgba(255,255,255,.022)
        + 1px rgba(255,255,255,.04) top edge
        recessed: inset 4 4 11 rgba(0,0,0,.55) + inset −3 −3 9 rgba(255,255,255,.02)
TYPE    SF Pro Rounded — clock 74/600 · next-time 33/700 · title 17–22/700
        row-title 15.5/600 · time 14–15/700 · label-caps 10.5–12/700 +0.8ls · meta 12.5–13/500
RULE    Orange = now / live / brand ONLY. Capture is a refined glyph, NEVER a fill.
        Subtle faded neumorphism on surfaces; crisp high-contrast text (WCAG AA,
        body ≥ #85848b on card). Calm, uncluttered, premium.
Sample data: 9:30 Standup (Work, NOW) · 11:00 Q3 deck review (Work) ·
2:00 Dentist (Health) · 4:30 Pick up dry cleaning (Errands) · 3 need a time.
```

### A.1 — Capture screen (app)
```
You are a senior product designer designing the iOS (SwiftUI) CAPTURE screen for
Atlas — a minimal capture-and-glance companion to a macOS life-manager. Three
tabs (Schedule, Capture, Tasks) + a settings gear; opens to Schedule.

Visual direction: dark near-black layered bg; accent #ff8c42 used sparingly for
primary/live/brand only (never the default fill); subtle FADED neumorphism on
surfaces; high-contrast, unmistakably tappable controls (WCAG AA); rounded
geometry, generous spacing, SF Pro / SF Rounded; springy micro-interactions.

CAPTURE specifics: a large dump box (tap to type, mic to speak); a calm animated
"thinking" state; a centered rounded RESULT card listing AI-created items, each
row = title + space color chip + tag + due, chips/tags/dates lightly tappable,
swipe-to-delete, "Looks good" confirms / "Undo" discards; a secondary
"Add a task manually" path (no AI).

Deliver every state — empty, listening/voice, thinking, result card, manual add.
Specify color tokens, spacing, radii, shadow values, typography. Production-grade
and restrained — no generic "AI app" gradients.
```

### A.2 — Home widget · Medium 4×2
```
[prepend Style block]
Design the HOME-SCREEN widget, MEDIUM family (4×2, wide-short).
A tight glance: header row "Today · Sat Jun 28 · 5 left" with a small mic glyph
top-right. Below, the next 2–3 timed items as rows: time · space color dot ·
title · trailing label (space name, or orange "NOW" for the current one). A
compact "Need a time · 3" pill bottom-left if any are unscheduled.
Deliver TWO states: BUSY (sample data) and EMPTY ("Nothing scheduled · tap to
capture", calm not sad). Tap targets: rows → atlas://today · mic → atlas://capture
· need-a-time → atlas://unscheduled. Specify spacing, radii, shadow, type per system.
```

### A.3 — Home widget · Large 4×4
```
[prepend Style block]
Design the HOME-SCREEN widget, LARGE family (4×4, square).
Header: orange brand dot + "Today", subtitle "Saturday, Jun 28 · 5 left", and a
raised neumorphic mic glyph top-right. A vertical timeline (thin hairline spine)
of 4 items: big time · space color dot on the spine · title · trailing label;
the current item gets a ringed dot + orange "NOW". Footer divided by a hairline:
a small rounded square badge "3" + "Need a time" + chevron.
Deliver TWO states: BUSY (sample data) and EMPTY (inviting "all clear" + capture
hint). Tap targets: rows → atlas://today · "Need a time" → atlas://unscheduled ·
mic → atlas://capture. Specify spacing, radii, shadow, type per system.
```

### A.4 — Lock screen · rectangular + circular
```
[prepend Style block]
Design the LOCK-SCREEN accessories (iOS 16+). IMPORTANT CONSTRAINT: lock-screen
accessories render in iOS's monochrome/vibrant tint — design primarily in
white/gray with hierarchy from weight, size, and fill (NOT color). The accent
ring may pick up a tint; make everything still read when fully desaturated.

CIRCULAR: a gauge ring showing items left — bold count "4" + tiny caps "LEFT",
ring partially filled (the filled arc is the one tinted element).
RECTANGULAR: next item — "9:30 Standup", second line muted "Work · then Q3 deck
11:00", a thin leading accent bar.
Deliver BUSY and EMPTY states (empty circular = "0 / clear"; empty rectangular =
"Nothing scheduled · tap to capture"). Tap targets: circular → atlas://today ·
rectangular(busy) → atlas://today · rectangular(empty) → atlas://capture.
Show them under a sample lock-screen clock for context.
```

### A.5 — Control Center / Action Button capture control (iOS 18)
```
[prepend Style block]
Design the iOS 18 CONTROL — a one-tap CAPTURE control for Control Center and the
Action Button. It's a single tile: a refined mic/✎ glyph (thin neumorphic stroke,
faint orange accent — never a solid orange fill) + label "Capture".
Show it three ways: (1) a tile in the Control Center grid, (2) selected on the
Action Button assignment screen, (3) the pressed/active state. Action: launches
Atlas straight into the dump box via atlas://capture (long-press → atlas://capture?mic=1
for voice). Unmistakably tappable but calm. Specify glyph weight, tile radius
(18–20), and the accent treatment per system.
```
