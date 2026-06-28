# Atlas — Handoff / Continue-Here

**Read this first in a new chat to resume.** Where we are, the #1 bug to fix, what's done, what you must do by hand, and what's next.

_Last updated: 2026-06-28 — **Daily-driver v2 + follow-ups built, builds & launches, 214/214 tests green** on `feat/daily-driver-v1` (NOT merged/pushed). AI capture is LIVE. One launch-time crash on the global hotkey (fix below)._

---

## 🚨 #1 — FIX FIRST: global hotkey (⌘⇧K) crashes the app

Pressing the system-wide capture hotkey **crashes Atlas** (`EXC_BREAKPOINT`/SIGTRAP). Crash report confirmed.

**Root cause:** `GlobalHotkeyInstaller` (`Atlas/App/AtlasApp.swift:33-49`) reads `@EnvironmentObject var state` **inside the escaping hotkey closure**. `@EnvironmentObject.wrappedValue` is only valid during `body` evaluation; when the Carbon hotkey fires later, `HotkeyService.handleHotKeyPressed()` → `onPress?()` → the closure reads the property wrapper outside `body` → SwiftUI `EnvironmentObject.error()` → fatal.

**The fix (pass the concrete instance, don't read the wrapper in the closure):**
```swift
// AtlasApp.swift body — `state` here is the @StateObject (concrete AppState):
.background(GlobalHotkeyInstaller(state: state))

private struct GlobalHotkeyInstaller: View {
    let state: AppState                       // ← was: @EnvironmentObject private var state
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .onAppear {
                HotkeyService.shared.register {
                    NSApp.activate(ignoringOtherApps: true)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        state.presentCapture = true
                    }
                }
            }
    }
}
```
`AppState` is a class (reference), so capturing the concrete instance is safe to call from the escaping Carbon callback. The voice mic button does NOT have this bug (it reads `state` during `body`, not in an escaping closure).

**Is the hotkey "actually global"?** Yes — `HotkeyService` uses Carbon `RegisterEventHotKey`, which is **system-wide**: ⌘⇧K fires no matter what app is focused, as long as Atlas is running (no Accessibility/Input-Monitoring permission needed). The crash report itself proves it fired. It just crashes on the EnvironmentObject access — once the fix above lands, it's truly global while Atlas runs in the background.

---

## Where we are

**Atlas** — native SwiftUI (macOS), dark, orange `#ff8c42`. Branch **`feat/daily-driver-v1`**, HEAD `6398d70`, ~33 commits ahead of `main`, **unpushed**. Builds, launches, **214/214 tests pass**.

**Verified live this session:** app launches & renders the Dashboard (donut metrics, "+ Space", per-space "+", Metrics moved off main nav, BrandLogo in sidebar). AI capture endpoint is deployed (HTTP 401 = live). Google client-ID Info.plist bug fixed.

### Build / run
```bash
cd "atlas life manager"
git checkout feat/daily-driver-v1
xcodegen generate
xcodebuild test  -scheme Atlas -destination 'platform=macOS' -derivedDataPath build   # 214 tests
xcodebuild build -scheme Atlas -configuration Debug -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/Atlas.app
```
> Build to an explicit `-derivedDataPath` and launch *that* `.app` (stale DerivedData copies have bitten us). SourceKit "Cannot find AtlasTheme / No such module XCTest" warnings are isolation noise — the real `xcodebuild` is green.

---

## What's built in v2 (all on `feat/daily-driver-v1`)

| Area | State |
|---|---|
| **Foundation** | `TaskItem` has real `dueDate`/`durationMin` + label formatter, persisted; capture wires the AI's `dueISO` into tasks; `CaptureOutcome` surfaces an "⚠︎ AI offline" degraded state instead of silently dumping raw text |
| **AI brain (WS-2)** | `capture` edge fn returns a **JSON array** (multi-item paragraphs), injects the user's real **Spaces + projects (+ descriptions)** as routing context; client decodes array, tolerant of single-object/legacy deploys; "✓ Added N items" |
| **Scheduling (WS-3)** | auto-find-a-slot (`SlotFinder`/`suggestSlot`), drag still works, **revert-after-slot** (`isEffectivelyUnscheduled` + 60s clock — a scheduled-but-passed unchecked task resurfaces), **space-filtered** Unscheduled tray, click-task → due-date popover |
| **⌘K palette (WS-7)** | persistent leading **"Create '<query>' as task"**; searches tasks; copy: "⌘K find or create · ⌘⇧K braindump" |
| **Projects (WS-8)** | per-Space "+" → new-project sheet; **editable overview**; `addProject`/`updateProjectOverview` |
| **Add-a-Space (follow-up)** | "+ Space" in sidebar header → name+color sheet; `addSpace` |
| **Empty templates (follow-up)** | empty projects render an **editable starter** (overview prompt + sample tasks), not blank; empty spaces show "Add your first project" |
| **Dashboard+Metrics (WS-9)** | full-width **tasks-below-schedule** grouped Overdue/Today/This week/Later + space filter (`TaskGrouping.byDueBucket`); **Metrics removed from main nav** → popup + ⌘K + a row near profile; **donut/ring charts** (Swift Charts) replace bars |
| **Calendar views (WS-4)** | **Month** + **List/agenda** views added to Day/Week; in-calendar search; color/category filter chips; native **traffic-light window controls** restored (`WindowConfigurator`) |
| **Voice + hotkey (WS-6)** | system-wide ⌘⇧K via Carbon `HotkeyService` (**crashes — see #1**); **click-to-talk** mic button in capture corner, on-device `SFSpeechRecognizer`, never auto-listens; mic/speech Info.plist strings + entitlement |
| **Google Calendar (WS-5)** | **partial** — full PKCE OAuth (`GoogleAuthService`), read + write-back (`GoogleCalendarService`), "Connect Google" wired; **client-ID Info.plist bug FIXED** this session. Live OAuth consent is human-only (untested) |
| **Notes↔Docs (WS-10)** | **scaffold** — constrained `NoteEditorView` over `RichDoc` (H/sub-H/normal + B/I/U + lists), `GoogleDocsMapper` (RichDoc↔Docs, unit-tested), `NoteSync.reconcile`, `googleDocId` on notes. Live calls no-op until Google connected |
| **Brand/logo** | a "bloom" AppIcon + `BrandLogo` are on this branch; the **real Atlas-titan logo** is on a separate branch — see Pending merge |

Specs/plans: `docs/superpowers/specs/2026-06-27-atlas-daily-driver-v2-design.md`, `docs/superpowers/specs/2026-06-27-v2-followups.md`, and per-workstream plans under `docs/superpowers/plans/`.

---

## Pending merge — real logo (separate worktree)

The real Atlas-titan logo (figure shouldering the sphere, from `~/Downloads/ATLASLM LOGO.jpg`) was built in an **isolated worktree** to avoid clobbering this session:
- Branch **`feat/brand-real-logo`** (commit `18c2f23`), worktree `/Users/drewkhalil/Documents/atlas-brand-logo`.
- Adds: AppIcon (transparent trace), `AtlasMark` (in-app), `AtlasMenuBar` (template) + a `MenuBarExtra` (Open Atlas / Quick Capture / Quit), `BrandLogo` → real mark, `tools/gen_brand_assets.py`. Deletes the orphaned bloom icons + `tools/gen_app_icon.swift`.
- **To adopt:** `git merge feat/brand-real-logo` from the main checkout. Expect conflicts in `BrandLogo.swift` + `AppIcon.appiconset` — **resolve in favor of `feat/brand-real-logo`** (the real-image versions).

---

## Manual steps — done vs. remaining

**Done ✅:** OpenRouter key set as Supabase secret · `capture` edge fn deployed (multi-item version, HTTP 401 live) · `notes.google_doc_id` SQL migration run · Google Cloud project + Calendar/Docs APIs + Desktop OAuth client created (creds in gitignored `.env.local` + `Config/Secrets.xcconfig`).

**Remaining ⛳:**
1. **Google test user + consent:** Google Cloud → Auth Platform → Audience → Test users → add `drewkhalil@gmail.com`; then in-app Settings → Calendars → **Connect → Allow** (the only way to verify Calendar/Docs live).
2. **(Optional) one more `capture` redeploy** for description-aware routing (the follow-up updated the fn; deployed version still routes at space level without descriptions). `supabase functions deploy capture`.
3. **Voice permissions:** approve mic + speech on first mic-button tap.
4. **Push** `feat/daily-driver-v1` when you decide (currently local only).

---

## Next work (user-requested priorities)

1. **Fix the hotkey crash** (#1 above) — unblocks global capture.
2. **Merge the real logo** branch.
3. **Google Calendar write-back** (Atlas→Google) — code exists but isn't auto-wired to push events; finish + exclude seed/external events.
4. **Notes ↔ Google Docs, for real** — the model the user wants: **a Google Drive folder per class/project**; notes are Docs in that folder; create new or adopt existing; **two-way real-time** so writing in Docs (in class) or in Atlas both sync. Project detail gets a "Notes" list from that folder. (May need a broader Drive scope / file-picker to adopt existing folders vs `drive.file`.)
5. **Notes hub + note↔task linking** + the **Obsidian-style graph view** (animated node/edge map of notes/tasks/projects/events) behind a subtle logo button on Metrics/Settings. Build the linking data first, graph on top.
6. **Strip seed/mock data → editable templates** (no fake events; the dashboard "June" date is mock).
7. **Email capture** — later, after the above.

---

## Honest caveats (what's NOT proven)

- **Global hotkey crashes on press** (fix above) — top blocker.
- **Google live sync unverified** — all code unit-tested, but OAuth consent is human-only; not exercised end-to-end. Write-back not auto-wired.
- **Notes↔Docs** is scaffold + tested mapping only; no live network until Google connected.
- **Voice** built but unproven at runtime (needs permission grants); this Debug build is ad-hoc signed (hardened runtime disabled).
- **Only the Dashboard was eyeballed** running — Calendar Month/List, capture, voice not visually verified live.
- **Seed/mock data still present** (wrong dates, demo events) — cosmetic until stripped.
- Branch **unpushed**; real-logo branch **unmerged**.
