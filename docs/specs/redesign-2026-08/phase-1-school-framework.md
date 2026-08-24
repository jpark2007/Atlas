# Phase 1 — School Framework (agreed 2026-08-24)

Part of the 2026-08 product-direction redesign (see `docs/product-direction-2026-08.md`).
Status: **discussion converged; not yet planned/implemented.**

## Decision summary

School stops being "projects with school names" and becomes a **built-in framework** you enable (or hide) from Settings. Not user-customizable structure — an actual purpose-built mode.

### Structure

```
School (enable/hide in Settings)
└── Term  e.g. "Fall 2026"  — start/end dates, breaks, Key Dates
    └── Class  — color, code, instructor, meeting pattern, linked sources
        ├── Assignments / tasks / deadlines
        ├── Notes / resources
        └── Class info card (from syllabus scan)
```

- **Term is a first-class object.** Classes belong to exactly one term. The app filters by the active term. "Start a new semester" flow creates the next term and offers copy-forward of recurring structure. Ending a term **soft-archives** its classes (grades/notes stay queryable, out of the way — never wipe). Prior art: MyStudyLife (the reference), Shovel; nobody wipes.
- **Key Dates live on the Term** (classes begin, add/drop deadline, holidays, breaks). Seeded from the registrar's academic calendar (ICS/URL) when available, else manual. Rendered as flags on the calendar. Competitors all make students type these — cheap differentiation.
- **Class = first-class object** (implementation may extend today's `projects.is_class` row — the user-facing model is what changes). Carries: name, code, color, instructor, structured meeting pattern, linked Canvas course / feeds, term id.
- **A class can hold lightweight projects** (agreed 2026-08-24): assignments/tasks/notes live on the class directly, plus optional nested projects ("Group research project") bundling their own tasks/notes, shown nested under the class in the sidebar.

### Onboarding & templates (agreed)

- **No fake seed data.** New account: Personal space + Getting Started checklist; the School section shows a **"Set up your semester" wizard** instead of a seeded example class. New classes start empty with a starter-checklist prompt. (Replaces the current `My First Class` seed in trigger 0024.)
- **Wizard order:** ask *"are you a student?"* → if yes, an instruction popup walks them through copying their **Canvas ICS link** (Canvas → Calendar → Calendar Feed) → import runs → Atlas lists the courses it found as a **checklist: "create these as classes?"** → confirm → semester built. Then term dates + optional syllabus scans. Non-Canvas path: add classes manually / school ICS / screenshot.
- **Auto-create offer also fires on later syncs** when a feed contains unknown courses.
- **Unmatched imports never drop or block:** they land wearing an "Unassigned · pick a class" chip; the first manual assignment teaches the mapping permanently.
- **Migration:** existing `is_class` projects auto-migrate into School under a term the user dates once on first launch. Best-effort — user base is founders/family; Drew plans to reset his account regardless.

### Class schedule ingestion — "your schedule already exists somewhere"

One setup step: *"How does your class schedule exist?"* Four doors, same landing place (Class knows its meeting blocks; calendar draws them; availability counts them as busy):

1. **School ICS link** (registrar/timetable feed) — reuse the existing Canvas-ICS pipeline + course-code attribution.
2. **Already in Google/Apple calendar** — Atlas recognizes recurring events matching class codes/titles and tags them as that class's meetings (attribution, not duplication; ties into cross-calendar dedup, Phase 3).
3. **Screenshot / PDF upload** — AI extracts the weekly schedule (same pipeline as syllabus scan).
4. **Manual entry** — fallback only, not the main path.

Meeting blocks respect term dates and breaks. No hand-built timetable UI as the primary flow; free-text `meeting_info` survives only as an optional note.

### Syllabus / schedule AI scan

- Input: PDF or screenshot. Output: **draft → review list → commit** (never silent commit; the one place a review screen is justified). Items grouped by class, editable inline, accept-all.
- Extracts: class meeting times, assignments/exams/quizzes with due dates.
- **Additionally extracts a "Class info" card** shown on the class detail page: grade-weight bullets, late/attendance-policy notes, office hours. Static info only — **no grades tracking, no chatbot** (scope freeze on grades stands).
- Market note: AI syllabus scan is table stakes in 2026 (UpAhead, Sylly, Shovel, DormWay…), typically paywalled ~$9/mo; differentiation is the post-import experience.

## Explicitly out of scope

- Grades tracking / GPA / grade calculators (dropped for good per scope freeze).
- Rotation timetables (A/B days) — high-school pattern; Atlas targets college. Design meeting-pattern storage so it could be added, don't build it.
- Syllabus chatbot.

## Open items deferred to later phases

- How class meetings render vs events/deadlines/work sessions → Phase 2 (calendar language).
- Dedup when the same lecture arrives via school ICS *and* Google/Apple sync → Phase 3.
- Settings placement + onboarding flow of "Enable School" → Phase 5 (simplicity/IA).
