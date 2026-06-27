# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume work.** Snapshot of where we are, what's left, and a ready-to-run sub-agent/workflow plan.

_Last updated: 2026-06-27 — auth + all screens shipped; next up: AI brain, real data, calendar overhaul._

---

## TL;DR for a new session

> **Atlas** is a native SwiftUI (macOS-first) smart life manager. **Dark, orange `#ff8c42`.** All core screens are built and building green: Dashboard, Calendar, Focus, Project/Class detail, ⌘K command palette, ⌘⇧K quick-capture, Notes editor. **Auth is live against Supabase** (email working; Apple/Google wired but need provider config). The app gates on sign-in with a "continue offline" escape. Data is still **mock** (same for every user) — wiring it to Supabase Postgres is the next big step.

**Resume:**
```bash
cd "atlas life manager"
xcodegen generate
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
open Atlas.xcodeproj   # or run the built .app
```
Then tell the new chat: *"Continue Atlas from docs/HANDOFF.md — run the Session 3 plan."*

> ⚠️ **SourceKit lies in this single-module XcodeGen setup**: the IDE shows "Cannot find type X in scope" constantly. These are FALSE. Trust `xcodebuild` only.

---

## Current state (what's DONE and building green)

- **Screens:** Sidebar (+ profile/settings row), **Dashboard** (schedule from `events`, tasks, focus, goals), **Calendar** (day/week grid from `state.events`, space filter, drag-to-schedule tray), **Focus** (Pomodoro), **Project/Class detail** (backlinks, pinned, Canvas badge), **⌘K command palette**, **⌘⇧K quick-capture pill**, **Notes editor**.
- **Auth (Stage 3a — DONE):** Supabase REST auth (no SDK, just URLSession) — see `Atlas/Services/`:
  - `SupabaseConfig.swift` — project URL + anon key (anon key is safe to ship).
  - `SupabaseAuth.swift` — signup / password / refresh / id_token (Apple) / PKCE (Google) / logout.
  - `AuthService.swift` — session restore+persist (UserDefaults), email, Apple (`ASAuthorizationController`), Google (`ASWebAuthenticationSession` + PKCE).
  - `CanvasService.swift` — token + host store, validates against Canvas API.
  - UI: `Views/Auth/SignInView.swift` (gate, with "continue offline"), `Views/Auth/SettingsView.swift` (account + Canvas + integrations, opened from the sidebar profile row).
  - `AppGate` in `AtlasApp.swift` routes loading / signedOut / signedIn|offline.
- **Window chrome:** the gray title-bar strip is FIXED (`Atlas/App/WindowConfigurator.swift` + `.toolbar(.hidden, for: .windowToolbar)`).

### What WORKS to test now
- **Email sign up / sign in** → hits the real Supabase project, creates a user. (Confirm-email is now OFF in the dashboard, so it's instant.)
- **Continue without an account** → full app on mock data.
- **Canvas connect** (Settings → host + token) validates live.

### What's WIRED but needs config (the "fix all paths" work)
- **Google** — full PKCE flow coded; needs: Supabase → Auth → Providers → Google (client id/secret) + Auth → URL Configuration → Redirect URLs → add `atlas://auth-callback`.
- **Apple** — button + id_token exchange coded; needs: Supabase Apple provider enabled + Xcode "Sign in with Apple" capability under a team (requires signing).

---

## File map (key paths)
```
Atlas/
  App/         AtlasApp (AppGate), RootView (Route enum + split view + overlays), WindowConfigurator
  Config/      SupabaseConfig.swift
  Services/    SupabaseAuth, AuthService, CanvasService   (add: AtlasDB, AtlasAI here)
  DesignSystem/Theme.swift (AtlasTheme + AtlasCard)
  Models/      Models.swift (Space, Project, CalendarEvent, TaskItem, Note, Goal, …)
  Data/        AppState (store), AppState+Calendar, AppState+Notes, MockData
  Views/       Sidebar/, Dashboard/, Calendar/, Focus/, Capture/, Search/, Notes/, Project/, Auth/
docs/          atlas-vision, specs/01..10, SETUP, HANDOFF (this file)
```
`project.yml` globs all `Atlas/**.swift` — new files need NO project edits, just `xcodegen generate`.

---

## SESSION 3 — what to build (everything below)

The user wants **all of it**. Three tracks plus a calendar overhaul and the sync design. Run them as the workflow in the next section.

### Track A — AI brain (capture → auto-sort) 🔑 secret `OPENROUTER_API_KEY` already set
1. Write a Supabase **Edge Function** `capture` (Deno/TypeScript) that:
   - Auth: verifies the caller's Supabase JWT.
   - Takes `{ text }`, calls OpenRouter (`openai/gpt-4o-mini`) with a strict JSON schema prompt.
   - Returns `{ kind: "task"|"event"|"note", title, spaceName, projectName?, dueISO?, startISO?, durationMin?, notes? }`.
   - Reads the key from `Deno.env.get("OPENROUTER_API_KEY")`. **Never** in the client.
   - Deliver the function file under `supabase/functions/capture/index.ts` for the user to `supabase functions deploy capture`.
2. Client `Atlas/Services/AtlasAI.swift` — POSTs to `{url}/functions/v1/capture` with the user JWT.
3. Wire **⌘⇧K capture**: on submit → call AI → create the parsed object in the right Space/project → confirmation toast. Fall back to a plain task if AI/offline fails.

### Track B — Real data persistence (Supabase Postgres)
1. SQL migration (`supabase/migrations/0001_init.sql`) — tables `profiles, spaces, projects, tasks, events, notes, pinned_resources, backlinks`, each with `user_id uuid references auth.users` + **RLS** (`auth.uid() = user_id`). Deliver for the user to run in the SQL editor.
2. `Atlas/Services/AtlasDB.swift` — PostgREST CRUD over `{url}/rest/v1/...` with `apikey` + user `Authorization: Bearer`.
3. Swap `AppState` internals: on sign-in, load from Supabase (seed the new user with the mock data on first run so it isn't empty); write-through on every mutation (`addTask`, `toggleTask`, `schedule`, `addNote`, `updateNote`, event CRUD). **Offline mode keeps using `MockData`.** UI must not change.

### Track C — Calendar overhaul + interactions + polish
- **Week view redesign** (user: "weekly view sucks") — readable 7-day grid: sticky day headers with weekday+date, today highlighted, scrollable time column, events laid out per-day with the existing lane-packing, an optional all-day row. Make it feel like a real calendar.
- **Add events from the calendar** — an "+ Add event" affordance in the calendar (in/near the unscheduled tray sidebar) AND click-empty-slot-to-create. Opens a quick event editor (title, space, start, duration). Writes to `state.events` (→ Track B persists).
- **Right-click an event → context menu** — Edit time / change duration / move to specific time / delete. (Reschedule precisely, not just drag.)
- **Click an event → link to its source** — selecting an event/task tile navigates to the underlying item (its Project/Class, Task, or Note). Generalize "click a node → open it" across backlinks/linked-references too.
- **⌘K palette** (user likes it) — extend: tasks should navigate somewhere (task detail or its project), add "Create new task/note/event" actions, keep the glass look.
- Verify the **gray bar fix** holds on every route (Dashboard/Calendar/Focus/Project/Settings).

### Track D — Auth paths + Calendar SYNC logic (design + scaffold)
- **Fix all auth paths:** verify Google PKCE end-to-end (after dashboard config), Apple (after capability), Canvas; surface clear errors.
- **Sync design (the open question the user raised — recommended answer below).** Build the Settings → **Calendars** section to support it.

---

## Calendar sync — recommended logic (resolve this in Session 3)

Per `docs/specs/03-unified-calendar.md`, the answer is **aggregate-to-read, pick-one-to-write**:

- **Aggregate everything for display.** Atlas shows events from **all** connected sources at once — Apple Calendar (EventKit, on-device), Google Calendar (OAuth), Canvas (assignments + class meetings), and Atlas-native. Color-code by **Space** (with a subtle source glyph). Each source has an on/off toggle in Settings.
- **Pick ONE "main" calendar for writes.** In Settings → Calendars the user chooses their main (Apple *or* Google). New Atlas-created events default to the main and **two-way sync** to it (so they also show in the user's native Apple/Google app). All other sources remain **read-only** mirrors inside Atlas.
- **Conflict policy:** last-write-wins to start (revisit later). Edits in Atlas push to the source if the event lives there; external edits pull on next sync.
- **Settings UI to build:** a "Calendars" group — list each source with connect/toggle, a "Main calendar" picker, and a default Space mapping per source.

This keeps it simple (no N-way merge engine) while showing a true unified calendar. Implement the Settings UI + the source toggles now; wire EventKit/Google/Canvas read adapters incrementally (EventKit first — it's local and needs no OAuth).

---

## Session 3 — sub-agent / workflow plan (ready to run)

Use a **workflow** (or sub-agents in worktrees). Suggested shape:

**Phase 0 — Discovery / review (parallel, read-only):** spawn agents to (a) audit the codebase vs `docs/specs/` and list discrepancies/gaps, (b) inventory every `AppState` mutation that Track B must persist, (c) sanity-check the auth paths and list exactly what each provider needs. Output: a punch-list.

**Phase 1 — Build (parallel, each in its own git worktree, NEW files + `extension AppState` only; do NOT edit Models/Theme/RootView except via the integration step):**
- Agent A — **AI brain** (Track A): `supabase/functions/capture/index.ts`, `Services/AtlasAI.swift`, capture wiring.
- Agent B — **Persistence** (Track B): `supabase/migrations/0001_init.sql`, `Services/AtlasDB.swift`, AppState load/write-through.
- Agent C — **Calendar overhaul** (Track C): week view, add/edit event, right-click menu, click-to-link.
- Agent D — **Auth paths + Sync settings** (Track D): Settings → Calendars UI, source toggles, main-calendar picker, EventKit read adapter, provider error handling.

**Phase 2 — Review (parallel, adversarial):** a reviewer per agent — correctness, conflict-rule compliance, design fidelity, spec alignment. Apply fixes.

**Phase 3 — Integrate (solo):** merge worktrees, wire the few route/sheet hooks, `xcodegen generate`, full build, **launch + screenshot every screen**, compare to mockups, iterate.

**Conflict rules for parallel agents:** only ADD files; extend the store via `extension AppState { }` (methods only — stored `@Published` props must be added to `AppState.swift` up front in a tiny solo "Stage 0.3" pass, e.g. `presentEventEditor`, `mainCalendarSource`, source toggles). Each agent must `xcodebuild` green in its worktree before reporting. **Worktrees fork from `main`'s HEAD — make sure the coordinator commits the shared-state additions to `main` BEFORE fanning out** (last session the worktrees forked from a stale commit and every agent built duplicate models; don't repeat that).

---

## Manual steps for YOU (human) — Supabase dashboard / Xcode

Done ✅: Supabase project created, URL + anon key in app, **Confirm email OFF**, `OPENROUTER_API_KEY` secret added.

Still needed, by track:
- **Track A (AI):** after we hand you `supabase/functions/capture/index.ts`, run `supabase functions deploy capture` (needs the Supabase CLI + `supabase link`). Confirm `OPENROUTER_API_KEY` is set as a Function secret.
- **Track B (data):** paste the contents of `supabase/migrations/0001_init.sql` into Supabase → SQL Editor → Run (creates tables + RLS).
- **Google:** Auth → Providers → Google (client id/secret from Google Cloud) + Auth → URL Configuration → Redirect URLs → add `atlas://auth-callback`. Optionally set **Site URL** to `atlas://auth-callback` so email links stop pointing at `localhost:3000`.
- **Apple:** Auth → Providers → Apple; in Xcode enable **Sign in with Apple** capability under your team (this also requires turning on signing — see `SETUP.md`).
- **Canvas / Google Calendar / Drive / Gmail:** per-user tokens/OAuth, wired incrementally.

---

## Architecture recap
- Native SwiftUI, macOS-first. All UI talks to `AppState`; Track B swaps its guts for Supabase without touching screens.
- Auth = Supabase GoTrue via URLSession (swap for `supabase-swift` SDK if/when we want realtime).
- AI = OpenRouter `gpt-4o-mini` behind a Supabase Edge Function (`OPENROUTER_API_KEY` server-side only).
- `.gitignore` blocks secrets, the generated `.xcodeproj`, and `.claude/worktrees/`. Commit `project.yml` + Swift source; run `xcodegen generate` after pulling.
