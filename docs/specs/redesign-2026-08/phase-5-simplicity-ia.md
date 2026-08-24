# Phase 5 — Simplicity Pass: Nav, Settings IA, Language (agreed 2026-08-24)

Part of the 2026-08 redesign. Status: **discussion converged; not yet planned/implemented.**
Test for every decision here: *"Could a dumb-but-not-braindead college student use this without being taught?"*

## Sidebar (Mac) — one structural change

Before: `Dashboard / Calendar / Focus / SPACES → (School space) → class-projects`
After:  `Dashboard / Calendar / Focus / School / SPACES (Personal, …)`

- **School becomes its own top-level sidebar section** (active term + classes) — pulled out of the generic SPACES tree. This is the visible face of the Phase 1 framework.
- Dashboard, Calendar, Focus unchanged. **Dashboard keeps its name, layout, and the mini month calendar**; its widgets absorb Phase 2 objects (due-today rail, Late bar, tonight's work sessions). Only the recent-notes widget gives up its slot. Revisit a "Today" rename only after the new widgets land.
- Visual mockups approved by Drew 2026-08-24 (design canvas "Atlas Redesign Preview"): sidebar w/ School section, calendar day/week language, class hub, settings — implement to those, keeping everything consistent with the editorial theme.
- **Notes stay out of the sidebar** (status quo formalized): notes live in their class/project hub + ⌘K search + Focus.
- **Brain Dump is never a nav item**: global hotkey + capture pill on Mac; center Capture tab on iOS (no hotkey exists there — intentional platform difference).

## Settings — 4 tabs → 5 human headings

| Heading | Contents |
|---|---|
| **Account** | identity, nickname, sign out, delete account (unchanged) |
| **Calendars** | ONE unified list, one row per source (Apple / each Google account / Canvas / by-link). Each row: **"Show these events in Atlas"** + **"Send my Atlas events here → [Space]"**. Kills the Feeds-vs-Calendars split, the duplicate Canvas row, "Items land in"/"Events land in"/"None (read-in only)". Mirror-to-Apple toggles restated as "Also add my Atlas events to Apple Calendar". Outbound toggles from Phase 3 live here (events/work sessions/deadlines). |
| **Capture & Tasks** | default space, shortcut recorder ("Quick capture key" / "Search key"), the History tab folded in as **"Recent captures"** with undo |
| **Notes & Files** | Notes & Docs Google login; per-tab Docs sync reworded "Edit multi-tab Google Docs (beta)" |
| **App & Help** | text size, sidebar visibility, tips, report a bug, about/version |

Metrics moves out of Settings → sidebar-adjacent "Progress" surface OR stays put — decide at implementation; not settings material either way. Graph's hidden-logo entry: leave for now, note as later cleanup.

## Language fixes (from fresh-eyes audit — all agreed, "fix for sure")

Full audit report is in the session research; key items, each with plain-language replacement:

1. **Delete** "Sign in with Apple — Enable signing in Xcode to use on device" (dev note shipped to users) — `SettingsView.swift:662`.
2. Rewrite the CALENDARS header sentence (three implementation concepts in one line) — `SettingsView.swift:841`.
3. De-duplicate Canvas (one row, connect form inline) — `SettingsView.swift:298` vs `:924`.
4. Purge jargon everywhere it appears: "ICS" → "calendar link"; "read-in only" → "Just show these events (don't send mine here)"; "sync events out" → "send my Atlas events to"; "Mirror" → "Also add to"; "read-only import" → "shown, not editable".
5. "History" tab → "Recent captures"; "GOAL AVG" → "Goals on track"; "N nodes" → "N items".
6. **Mac first-run zero state**: seed or guide — sidebar zero-state copy ("Start with a Space — School, Personal…") + port the iOS Get-started checklist to Mac. New-account server seed already creates School/Personal; the zero-state covers pre-seed/edge cases and orientation.
7. Runner-up fixes: "Toggle to request access", "type your dump", "Sort it out", "Notes are kept as tasks", "LINKED REFERENCES" → "Mentioned in", "Command Palette" shortcut label → "Search".

## Interaction-quality standing rule (§11)

Every new surface in phases 1–4 passes: fewest clicks, visible feedback, no modal unless committing something, keyboard path exists, drag works. Plus the dogfooding friction log (`docs/friction-log.md`, to be created): one line every time Atlas felt clunky or you reached for another app; burned down in waves.
