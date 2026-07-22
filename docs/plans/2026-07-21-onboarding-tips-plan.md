# Onboarding & Tips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved onboarding surface (`docs/specs/2026-07-21-onboarding-tips-design.md`) before the iOS App Store v1 archive: a Mac `.help()` hover sweep, ten shared TipKit tips across Mac + iOS, a Global Capture Key first-run popup + permanent Settings rebind, an iOS getting-started checklist, and a 2-step iOS calendar-views spotlight. Nothing beyond that spec.

**Architecture:** Tip *definitions* + shared TipKit *event* declarations live in the `AtlasCore` SwiftPM package (it already targets macOS 14 / iOS 17 — TipKit's exact floors — so `import TipKit` compiles for both platforms; per-platform copy is forked with `#if os(macOS)` inside each tip). *Anchors* (`.popoverTip`), *donations* (`Event.donate()`), the Carbon-hotkey sync layer, the first-run popup, the iOS checklist, and the iOS spotlight are all target-side (Mac `Atlas/`, iOS `AtlasMobile/`) because they touch platform-only views/services. `Tips.configure()` runs once per app at launch.

**Tech Stack:** Swift 5, SwiftUI, Apple TipKit (system framework, no dependency to add), Carbon (`HotkeyService`, Mac only), UserDefaults/@AppStorage for local flags, WidgetKit (`WidgetCenter.getCurrentConfigurations` — already imported in `AtlasMobile/Data/WidgetSnapshotWriter.swift`) for the soft widget check. XcodeGen (`project.yml`) generates `Atlas.xcodeproj`.

## Global Constraints

- macOS 14 / iOS 17 minimum floors — already satisfied; TipKit needs no availability guards.
- `.help()` copy: Atlas editorial voice, **sentence case, no trailing period, one line each**.
- Tips trigger on **anchor view appearing while rules pass** — never on click or hover.
- **One tip displayed at a time** per anchor (TipKit UI behavior). `displayFrequency(.immediate)` in Task 1 matches TipKit's default and is intentional — rules do the throttling.
- `Tips.configure()` is called **exactly once per app** at launch, before any tip renders.
- Event donations happen at the **real call site** where the user does the thing (choke-points listed per task), never speculatively.
- A tip retires itself with `invalidate(.actionPerformed)` (or an `#Rule` that reads a donated event) the moment the user does the thing unprompted.
- New Swift files under `Atlas/` or `AtlasMobile/` require **`xcodegen generate`** before `xcodebuild` (XcodeGen globs source dirs at generation time). New files under `AtlasCore/Sources/AtlasCore/` are auto-globbed by SPM — no regen needed.
- **UI/behavior is NOT proven by a green build.** Every task's verification ends with a specific manual check for Drew. This project has **no UI test target** — do not invent one; verification is `xcodebuild` + a manual checklist.
- Mac build command:
  `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- iOS build command (scheme `AtlasMobile` per `project.yml` line 185-189; iOS Simulator destination):
  `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Commit after each task with the message given. Do NOT push; do NOT open a PR (Drew's call).

---

## Judgment calls made while writing this plan (confirm with Drew)

1. **Tips live in AtlasCore.** Verified `AtlasCore/Package.swift` declares `platforms: [.macOS(.v14), .iOS(.v17)]` — exactly TipKit's floors — so `import TipKit` compiles there. This lets the ten tip structs + shared `Tips.Event` values be defined once. Per-platform copy is a one-line `#if os(macOS)` fork inside each tip. (If a future TipKit compile issue appears in the package, the fallback is to duplicate the structs into each app target — but there is no reason to expect that here.)
2. **New-account detection = auth user `created_at`, added as an optional String.** Verified there is **no** client-side creation timestamp today: the `profiles` table (migration `0015`) has no `created_at` column, `ProfileRow` (`AtlasDB.swift:985`) omits it, and `SupabaseUser` (`SupabaseAuth.swift:5`) decodes only `id/email/user_metadata`. GoTrue's session JSON *does* carry `user.created_at`. Task 5 adds `createdAt: String?` (CodingKey `created_at`) to `SupabaseUser` — decoded as a **String**, not a Date, so a missing/oddly-formatted value can never throw and break auth (synthesized `decodeIfPresent` for optionals). New-account = `created_at` parsed and within 7 days of now AND a permanent local `onboarding.captureKeyPopupSeen` flag is unset. Existing users (created weeks/months ago) never qualify; if GoTrue omits the field the popup simply never shows (safe — tip #6 is the backstop). **Drew: confirm your Supabase returns `created_at` on the session user** (Task 5 adds a one-line debug log to verify on-device).
3. **Widget-added detection IS feasible.** `WidgetCenter.shared.getCurrentConfigurations` returns installed widget kinds and is already available (`WidgetSnapshotWriter` imports WidgetKit). The bonus checklist item auto-checks by matching the Atlas kinds (`AtlasToday`, `AtlasLockRect`, `AtlasLockCircular`). It stays **soft** (never required for 4/4 completion), per spec.

---

## Task 1 — TipKit foundation (AtlasCore)

Define all ten tips + shared events in AtlasCore, and configure TipKit once in each app entry point.

**Files**
- Create `AtlasCore/Sources/AtlasCore/AtlasTips.swift`
- Modify `Atlas/App/AtlasApp.swift` (configure at launch; `.onAppear` on `AppGate`/`GlobalHotkeyInstaller` already exists ~L235)
- Modify `AtlasMobile/AtlasMobileApp.swift` (configure in the `RootTabView().task` ~L22)

**Interfaces**
- Produces: `enum AtlasTips` namespace exposing the ten `Tip` structs and an `AtlasTipEvents` namespace of `Tips.Event` values; a helper `AtlasTips.configureOnce()`.
- Consumes: TipKit `Tips`, `Tip`, `Tips.Event`, `Rule`.

**Steps**

- [ ] Create `AtlasCore/Sources/AtlasCore/AtlasTips.swift` with the full content below. Copy is forked per platform with `#if os(macOS)`. Each tip's rules read donated events and/or a per-tip `@Parameter` open-count. Events are module-level `Tips.Event` values so both the donation site and the rule reference the same identifier.

```swift
import SwiftUI
import TipKit

// MARK: - Shared donation events
//
// One event per "user did the thing". Donated at real call sites (see Mac Task 2,
// iOS Task 6). Tips read them in #Rule closures to self-retire or to gate display.

public enum AtlasTipEvents {
    public static let openedApp        = Tips.Event(id: "atlas.openedApp")
    public static let usedSearch       = Tips.Event(id: "atlas.usedSearch")
    public static let scheduledByDrag  = Tips.Event(id: "atlas.scheduledByDrag")
    public static let connectedSource  = Tips.Event(id: "atlas.connectedSource")
    public static let captured         = Tips.Event(id: "atlas.captured")
    public static let openedNote       = Tips.Event(id: "atlas.openedNote")
    public static let sawFrozenIsland  = Tips.Event(id: "atlas.sawFrozenIsland")
    public static let invited          = Tips.Event(id: "atlas.invited")
    public static let usedGlobalCapture = Tips.Event(id: "atlas.usedGlobalCapture")
    public static let scheduledOnCalendar = Tips.Event(id: "atlas.scheduledOnCalendar")
    public static let peekedMonth      = Tips.Event(id: "atlas.peekedMonth")
    public static let reportedBug      = Tips.Event(id: "atlas.reportedBug")
}

// MARK: - Tips

public enum AtlasTips {

    /// 1 — ⌘K command palette (Mac only). Rule: app opened ≥2 times AND search never used.
    public struct CommandPalette: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Jump anywhere") }
        public var message: Text? { Text("Press ⌘K to search notes, classes, and commands from anywhere") }
        public var image: Image? { Image(systemName: "magnifyingglass") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 2 }
            #Rule(AtlasTipEvents.usedSearch) { $0.donations.isEmpty }
        }
    }

    /// 2 — Drag-to-schedule (both). Rule: first calendar visit AND ≥1 unscheduled task.
    public struct DragToSchedule: Tip {
        @Parameter public static var hasUnscheduled: Bool = false
        public init() {}
        public var title: Text { Text("Block time for it") }
        #if os(macOS)
        public var message: Text? { Text("Drag a task from the tray onto the grid to schedule it") }
        #else
        public var message: Text? { Text("Tap a task in “Needs a time”, then place it on the day") }
        #endif
        public var image: Image? { Image(systemName: "hand.draw") }
        public var rules: [Rule] {
            #Rule(Self.$hasUnscheduled) { $0 == true }
            #if os(macOS)
            #Rule(AtlasTipEvents.scheduledByDrag) { $0.donations.isEmpty }
            #else
            #Rule(AtlasTipEvents.scheduledOnCalendar) { $0.donations.isEmpty }
            #endif
        }
    }

    /// 3 — Connect Google/Canvas (both). Rule: app opened ≥3 times AND nothing connected.
    public struct ConnectSource: Tip {
        @Parameter public static var appOpens: Int = 0
        @Parameter public static var hasConnection: Bool = false
        public init() {}
        public var title: Text { Text("Bring in your calendar") }
        public var message: Text? { Text("Connect Google or Canvas to see everything in one place") }
        public var image: Image? { Image(systemName: "link") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 3 }
            #Rule(Self.$hasConnection) { $0 == false }
            #Rule(AtlasTipEvents.connectedSource) { $0.donations.isEmpty }
        }
    }

    /// 4 — Per-calendar checkboxes (Mac only). Rule: shown inside the auto-opened
    /// connection sheet on first connect. Gated entirely by its anchor appearing;
    /// no extra rule beyond "not yet dismissed".
    public struct PerCalendarPicker: Tip {
        public init() {}
        public var title: Text { Text("Pick what syncs") }
        public var message: Text? { Text("Turn calendars on or off — only the checked ones show in Atlas") }
        public var image: Image? { Image(systemName: "checklist") }
    }

    /// 5 — Report a Bug (both, beta only). Rule: app opened ≥4 times.
    /// Beta-only gating is applied at the ANCHOR with `if AtlasBuild.isBeta` (Task 2/6),
    /// so no rule is needed here beyond the session count.
    public struct ReportBug: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Hit a snag?") }
        public var message: Text? { Text("Send it straight to us from here — no email needed") }
        public var image: Image? { Image(systemName: "ant") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 4 }
            #Rule(AtlasTipEvents.reportedBug) { $0.donations.isEmpty }
        }
    }

    /// 6 — Global capture reminder (Mac only). Rule: app opened ≥3 times AND
    /// the global capture key has never been used.
    public struct GlobalCapture: Tip {
        @Parameter public static var appOpens: Int = 0
        public init() {}
        public var title: Text { Text("Capture from any app") }
        public var message: Text? { Text("Press ⌘⇧K from anywhere to jot a task or speak it") }
        public var image: Image? { Image(systemName: "bolt") }
        public var rules: [Rule] {
            #Rule(Self.$appOpens) { $0 >= 3 }
            #Rule(AtlasTipEvents.usedGlobalCapture) { $0.donations.isEmpty }
        }
    }

    /// 7 — Doc tabs basics (Mac only). Rule: first time inside a note that has tabs.
    public struct DocTabs: Tip {
        public init() {}
        public var title: Text { Text("Switch between tabs") }
        public var message: Text? { Text("This note has more than one tab — tap to move between them") }
        public var image: Image? { Image(systemName: "doc.on.doc") }
    }

    /// 8 — Drive sync (Mac only). Rule: gated at the anchor (first note in a
    /// Drive-linked project AND Google connected).
    public struct DriveSync: Tip {
        public init() {}
        public var title: Text { Text("Kept in sync with Drive") }
        public var message: Text? { Text("Edits here round-trip to the linked Google Doc") }
        public var image: Image? { Image(systemName: "arrow.triangle.2.circlepath") }
    }

    /// 9 — Frozen islands (Mac only). Rule: first time an island is visible.
    public struct FrozenIslands: Tip {
        public init() {}
        public var title: Text { Text("Frozen from Google") }
        public var message: Text? { Text("Shaded blocks are read-only content Atlas keeps exactly as Google has it") }
        public var image: Image? { Image(systemName: "lock.doc") }
        public var rules: [Rule] {
            #Rule(AtlasTipEvents.sawFrozenIsland) { $0.donations.isEmpty }
        }
    }

    /// 10 — Invite people (Mac only). Rule: gated at the anchor (on a space page
    /// AND the user is the only member).
    public struct InvitePeople: Tip {
        public init() {}
        public var title: Text { Text("Bring someone in") }
        public var message: Text? { Text("Invite a teammate to share this space") }
        public var image: Image? { Image(systemName: "person.badge.plus") }
        public var rules: [Rule] {
            #Rule(AtlasTipEvents.invited) { $0.donations.isEmpty }
        }
    }

    /// Call once per app at launch, before any tip renders. Wraps `Tips.configure`
    /// and bumps the shared `appOpens` counters used by rules 1/3/5/6.
    public static func configureOnce() {
        #if DEBUG
        // Uncomment locally to preview every tip regardless of rules:
        // Tips.showAllTipsForTesting()
        #endif
        try? Tips.configure([
            .displayFrequency(.immediate),   // rules already throttle; one-at-a-time is TipKit default UI behavior
            .datastoreLocation(.applicationDefault)
        ])
        bumpAppOpens()
    }

    private static func bumpAppOpens() {
        let next = min(CommandPalette.appOpens + 1, 99)
        CommandPalette.appOpens = next
        ConnectSource.appOpens = next
        ReportBug.appOpens = next
        GlobalCapture.appOpens = next
    }
}
```

> Note on `displayFrequency(.immediate)`: this governs how soon a *rule-eligible* tip appears, not how many show at once. TipKit still surfaces one popover tip at a time per anchor. Do not change it to a throttled interval — the spec wants tips to appear promptly when their rule passes.

- [ ] Add a tiny beta-build helper used by tips #5's anchor gating. Create it in AtlasCore so both apps share it. Append to `AtlasTips.swift`:

```swift
public enum AtlasBuild {
    /// Beta = a Debug build OR the direct-download/TestFlight beta. Report-a-bug tip
    /// only fires on beta builds per spec. Refine if a dedicated beta flag is added.
    public static var isBeta: Bool {
        #if DEBUG
        return true
        #else
        return true   // current v0.9 distribution is beta across the board; flip when GA ships
        #endif
    }
}
```

- [ ] Wire `configureOnce()` into the Mac app. In `Atlas/App/AtlasApp.swift`, inside `GlobalHotkeyInstaller`'s `.onAppear` (currently ~L235, where `CapturePanelController.shared.configure` runs), add as the FIRST line of the closure:

```swift
                AtlasTips.configureOnce()
```

- [ ] Wire `configureOnce()` into the iOS app. In `AtlasMobile/AtlasMobileApp.swift`, inside `RootTabView().task { ... }` (~L22), add as the FIRST line:

```swift
                            AtlasTips.configureOnce()
```

- [ ] Add `import TipKit` to `Atlas/App/AtlasApp.swift` and `AtlasMobile/AtlasMobileApp.swift` (AtlasCore's `AtlasTips.swift` already imports it; the app files reference `AtlasTips` which is re-exported via `import AtlasCore`, but `Tips`/`Tip` types are not needed in the app files for this task — only `AtlasTips.configureOnce()`. If the compiler is happy with just `import AtlasCore`, skip the TipKit import here; add it only if a symbol is unresolved).

**Verify**
- [ ] Build AtlasCore in isolation: `cd AtlasCore && swift build` → expect "Build complete!". (Confirms TipKit compiles in the package for the host platform.)
- [ ] `xcodegen generate` (no new app-target files this task, but harmless), then Mac build command → expect **BUILD SUCCEEDED**.
- [ ] iOS build command → expect **BUILD SUCCEEDED**.
- [ ] Manual (Drew): none yet — no anchors are attached. This task only proves configuration compiles and runs without crashing. Launch each app once; confirm no crash at startup.

**Commit**
```
feat(tips): TipKit foundation — shared tip defs + events in AtlasCore, configure per app
```

---

## Task 2 — Mac tip anchors + event donations

Attach `.popoverTip` at the verified anchor views and donate events at the verified choke-points. (All line refs verified against the live tree.)

**Files**
- Modify `Atlas/Views/Sidebar/SidebarView.swift` (search anchor L195; report-bug anchor L162)
- Modify `Atlas/Views/Search/CommandPalette.swift` (palette-open donation, `CommandPaletteOverlay.body` `.onChange(of: state.presentSearch)` ~L113)
- Modify `Atlas/Views/Calendar/CalendarView.swift` (drag-commit donation in `schedule(taskID:on:hour:)` after the write at ~L578; drag tip anchor on `UnscheduledTray`)
- Modify `Atlas/Views/Capture/CaptureOverlay.swift` (capture-commit donation in `submit()` ~L288)
- Modify `Atlas/Views/Auth/SettingsView.swift` (Google connect success in `saveNewGoogleAccount()` after `createConnection` ~L1194; Canvas connect success after `canvas.connect(...)` ~L412; per-calendar picker tip anchor in the connection detail sheet)
- Modify `Atlas/Views/Notes/NoteEditorView.swift` (note-open donation `.onAppear` ~L110; doc-tabs anchor L194-211; frozen-island donation in `frozenRow(display:)` ~L815)
- Modify `Atlas/Views/Space/SpaceDetailView.swift` (invite tip anchor on the "Invite people" button L140-153)
- Modify `Atlas/Views/Space/InviteToSpaceSheet.swift` (invite donation after `state.inviteToSpace` ~L52)

**Interfaces**
- Consumes: `AtlasTips.*`, `AtlasTipEvents.*`, `Tip.invalidate(_:)`.
- Produces: no new public types.

**Steps**

Each anchor holds a `@State` tip instance and applies `.popoverTip(tip)`. Each donation calls `Task { await AtlasTipEvents.<x>.donate() }` at the choke-point. Add `import TipKit` to any file that uses `.popoverTip` (SidebarView, CalendarView/UnscheduledTray, SettingsView, NoteEditorView, SpaceDetailView).

- [ ] **Tip #1 anchor + rule param.** In `SidebarView.swift`, add near the other `@State`: `@State private var searchTip = AtlasTips.CommandPalette()`. Attach to `searchField` (L195 button) `.popoverTip(searchTip, arrowEdge: .bottom)`. On tap, retire it — in the button action add `searchTip.invalidate(reason: .actionPerformed)` (belt-and-suspenders alongside the donation below).

- [ ] **Tip #1 donation.** In `CommandPalette.swift`, inside `CommandPaletteOverlay.body`'s `.onChange(of: state.presentSearch)` block (~L113), when `presented == true` add:

```swift
                Task { await AtlasTipEvents.usedSearch.donate() }
```

- [ ] **Tip #2 rule param + anchor (Mac).** In `CalendarView.swift`, set `AtlasTips.DragToSchedule.hasUnscheduled` from the live tray count where the calendar body computes unscheduled tasks (find the array feeding `UnscheduledTray`; add `.onAppear { AtlasTips.DragToSchedule.hasUnscheduled = !<unscheduledTasks>.isEmpty }` and an `.onChange` on its count). Add `@State private var dragTip = AtlasTips.DragToSchedule()` and attach `.popoverTip(dragTip, arrowEdge: .leading)` to the `UnscheduledTray(...)` view (L46).

- [ ] **Tip #2 donation (Mac).** In `CalendarView.swift`, in `schedule(taskID:on:hour:)` on the SUCCESS branch (immediately after the `state.schedule(taskId:at:)` write, ~L578, before returning `true`) add:

```swift
            Task { await AtlasTipEvents.scheduledByDrag.donate() }
```

- [ ] **Tip #3 rule params.** In `SettingsView.swift` (or wherever connection state is known at app scope) set `AtlasTips.ConnectSource.hasConnection` on load: after `state.refreshGoogleConnections()` / `refreshCanvasConnection()` land, set it true when any connection exists. Simplest: in `AppGate`/`RootView` `.onAppear`, `AtlasTips.ConnectSource.hasConnection = state.hasAnyConnection` (add a computed `hasAnyConnection` on `AppState` if none exists: `!googleConnections.isEmpty || canvasConnected`). Attach the tip anchor to the Integrations "Add account" / Canvas connect row: `@State private var connectTip = AtlasTips.ConnectSource()` + `.popoverTip(connectTip)`.

- [ ] **Tip #3 donation — Google.** In `SettingsView.swift` `saveNewGoogleAccount()`, immediately after `await state.refreshGoogleConnections()` (~L1195) add:

```swift
                Task { await AtlasTipEvents.connectedSource.donate() }
                AtlasTips.ConnectSource.hasConnection = true
```

- [ ] **Tip #3 donation — Canvas.** In `SettingsView.swift`, right after the successful `try await canvas.connect(...)` (~L412) add the same two lines.

- [ ] **Tip #4 anchor.** In `SettingsView.swift`, the connection detail sheet auto-opens on first Google connect (`detailConnection = created`, ~L1202-1205). Inside that sheet's per-calendar checkbox list header, add `@State private var perCalTip = AtlasTips.PerCalendarPicker()` and `.popoverTip(perCalTip, arrowEdge: .top)` on the first calendar row / list header. No donation — it self-dismisses on ✕ or when the user toggles a calendar (add `perCalTip.invalidate(reason: .actionPerformed)` inside `toggleCalendar`, ~L1257).

- [ ] **Tip #5 anchor (Mac, beta-gated).** In `SidebarView.swift`, wrap the report-bug anchor: `@State private var bugTip = AtlasTips.ReportBug()`; on `reportBugRow` (L162) apply `.popoverTip(AtlasBuild.isBeta ? bugTip : nil)`. In `reportBugRow`'s button action add `Task { await AtlasTipEvents.reportedBug.donate() }` (this also serves as the donation).

- [ ] **Tip #6 anchor.** The Global-capture reminder has no persistent on-screen control to anchor to; anchor it to the sidebar logo/search area so it surfaces during normal use: add `@State private var globalCaptureTip = AtlasTips.GlobalCapture()` in `SidebarView.swift` and `.popoverTip(globalCaptureTip, arrowEdge: .trailing)` on `searchField` OR the `logo` (L182). Its donation is wired in Task 4/5 at the hotkey-fire site.

- [ ] **Tip #7 anchor (doc tabs).** In `NoteEditorView.swift`, at the doc-tabs switcher (`if !docTabs.isEmpty` block, L194-211) add `@State private var docTabsTip = AtlasTips.DocTabs()` and `.popoverTip(docTabsTip, arrowEdge: .bottom)` on the `AtlasSegmentedPicker`. Retire on `switchTab`: add `docTabsTip.invalidate(reason: .actionPerformed)` inside `switchTab(to:)`.

- [ ] **Tip #8 anchor (Drive sync).** In `NoteEditorView.swift`, gate at the anchor: only when `docReference != nil` (Drive-linked). Add `@State private var driveTip = AtlasTips.DriveSync()` and attach `.popoverTip(docReference != nil ? driveTip : nil)` to the sync-now button (`syncNowButton`, ~L382).

- [ ] **Tip #7/#8 donation — note open.** In `NoteEditorView.swift` `.onAppear` (L110-118) add:

```swift
            Task { await AtlasTipEvents.openedNote.donate() }
```

- [ ] **Tip #9 donation + anchor (frozen island).** In `NoteEditorView.swift` `frozenRow(display:)` (~L815) add a `.onAppear { Task { await AtlasTipEvents.sawFrozenIsland.donate() } }` to the row view, and attach `@State private var frozenTip = AtlasTips.FrozenIslands()` + `.popoverTip(frozenTip, arrowEdge: .leading)` to the FIRST frozen row (guard so it attaches once — e.g. only when `display` matches the first frozen segment, or simply attach to every frozen row; TipKit shows one at a time regardless).

- [ ] **Tip #10 anchor (invite).** In `SpaceDetailView.swift`, add `@State private var inviteTip = AtlasTips.InvitePeople()`. Gate on "only member": attach `.popoverTip(isOnlyMember ? inviteTip : nil, arrowEdge: .bottom)` to the "Invite people" button (L140-153), where `isOnlyMember` is derived from the space's member count (add a computed check against `state.spaceMembers`/`projectMembers` for this space == 1).

- [ ] **Tip #10 donation.** In `InviteToSpaceSheet.swift`, in the Send-invite button action right after `await state.inviteToSpace(...)` (~L52) add:

```swift
                        await AtlasTipEvents.invited.donate()
```

**Verify**
- [ ] `xcodegen generate` (no new files, safe) then Mac build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew), in a Debug build with `Tips.showAllTipsForTesting()` temporarily uncommented in `AtlasTips.configureOnce()` (revert before commit), confirm each popover renders at its anchor and dismisses on ✕:
  - ⌘K tip on the sidebar search field; disappears after opening search once.
  - Drag-to-schedule tip on the unscheduled tray (only when a task is unscheduled).
  - Connect tip in Integrations; gone after connecting.
  - Per-calendar tip inside the auto-opened Google connection sheet.
  - Report-a-bug tip on the sidebar row (beta only).
  - Doc-tabs tip in a multi-tab note; Drive-sync tip in a Drive-linked note; frozen-island tip when a shaded block shows.
  - Invite tip on a solo space page.
- [ ] Revert the `showAllTipsForTesting()` line before committing.

**Commit**
```
feat(tips): Mac anchors + event donations for all ten tips
```

---

## Task 3 — Mac `.help()` hover sweep

Add SwiftUI `.help("…")` to every icon-only button in the Mac app. Icon-only = an `Image(systemName:)` inside a `Button` with **no visible text label**. Buttons that already carry a text label (e.g. "Add event", "Invite people") are excluded.

**Files**
- Modify `Atlas/Views/Sidebar/SidebarView.swift`, `Atlas/Views/Calendar/CalendarView.swift`, `Atlas/Views/Notes/NoteEditorView.swift`, `Atlas/Views/Capture/CaptureOverlay.swift`, and any other Mac view the grep below surfaces.

**Interfaces** — none (pure view-modifier additions).

**Steps**

- [ ] Build the full inventory. Run this grep and review every hit; keep only `Image(systemName:)` that sit inside a `Button` with no adjacent `Text`:

```
grep -rn "Image(systemName:" Atlas/Views --include=*.swift | grep -v "Text("
```

- [ ] Apply `.help(...)` to each icon-only button using this starter list (verified anchors; sentence case, no period, one line). Add more from the grep as found — the copy voice: plain, active, tells what the button does:

| File:line (verified) | Button | `.help(...)` copy |
|---|---|---|
| `SidebarView.swift:196` | search field (magnifyingglass) | `Search notes, classes, and commands` |
| `SidebarView.swift:47` | add space/project (plus) | `Add a space` |
| `SidebarView.swift:149` | settings (gearshape) | `Open settings` |
| `SidebarView.swift:165` | report bug (ant) | `Report a bug` |
| `SidebarView.swift:284` | expand/collapse (chevron) | `Expand or collapse` |
| `SidebarView.swift:295` | add project (plus) | `Add a project` |
| `CalendarView.swift:161` | search icon in filter | `Search this calendar` |
| `CalendarView.swift:171` | clear (xmark.circle.fill) | `Clear the search` |
| `CalendarView.swift:253` | previous (chevron.left) | `Previous week` |
| `CalendarView.swift:273` | next (chevron.right) | `Next week` |
| `CaptureOverlay.swift:139` | AI sparkles | `Let Atlas sort this into the right space` |
| `CaptureOverlay.swift:232` | mic (mic.fill/stop.fill) | `Click to dictate; click again to stop` |
| `NoteEditorView.swift:382` | sync now (arrow.clockwise) | *(already has `.help`)* leave as-is |

> `CalendarView.swift:234` ("Add event") and `SpaceDetailView.swift` ("Invite people") already have visible labels / existing `.help` — do not touch. Some `NoteEditorView` icons at L400/425/456/475 are banner glyphs, not buttons — skip. Where a `.help` already exists (e.g. NoteEditorView reload/open-in-docs), leave the existing copy.

- [ ] Verify the exact chevron semantics before finalizing copy: read `CalendarView.shift(by:)` to confirm the grid steps by week vs day and adjust "Previous week"/"Next week" accordingly.

**Verify**
- [ ] Mac build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew): hover each icon-only button ~1s; confirm the gray native tooltip shows the right copy and reads as one clean line.

**Commit**
```
feat(help): .help() hover tooltips across Mac icon-only buttons
```

---

## Task 4 — Capture shortcut sync layer (single source of truth)

Eliminate the verified drift between `ShortcutStore` (SwiftUI `Character` + `EventModifiers` under `shortcut.capture.key`/`.mods`) and `HotkeyService` (Carbon `UInt32` keycode + mask under `captureHotkeyKeyCode`/`captureHotkeyModifiersRaw`). One writer translates and updates both; on launch the Carbon hotkey is derived from the `ShortcutStore` binding so they can never diverge from pre-existing stored values.

**Files**
- Create `Atlas/Services/CaptureShortcutSync.swift`
- Modify `Atlas/Services/HotkeyService.swift` (make `update`/`applyShortcut` return the `RegisterEventHotKey` `OSStatus` so callers can detect a failed registration)
- Modify `Atlas/App/AtlasApp.swift` (call `reconcileOnLaunch` in `GlobalHotkeyInstaller.onAppear` after `HotkeyService.shared.register`)

**Interfaces**
- Produces:
  - `enum CaptureShortcutSync` with:
    - `static func carbonKeyCode(for char: Character) -> UInt32?`
    - `static func carbonModifiers(from mods: EventModifiers) -> UInt32`
    - `static func apply(_ binding: ShortcutBinding, to shortcuts: ShortcutStore) -> OSStatus` — writes ShortcutStore(.capture) AND derives + registers the Carbon hotkey; returns the registration status (`noErr` on success).
    - `static func reconcileOnLaunch(_ shortcuts: ShortcutStore)` — derives the Carbon hotkey from the current `.capture` binding so global == in-app at every launch.
    - `static func systemConflict(_ binding: ShortcutBinding) -> String?` — matches a small table of well-known macOS system combos.
- Consumes: `HotkeyService.update(keyCode:modifiers:) -> OSStatus`, `ShortcutStore`.
- `HotkeyService.update` return type changes `Void → OSStatus`; `applyShortcut` returns the `RegisterEventHotKey` status.

**Steps**

- [ ] Modify `HotkeyService.swift` so `applyShortcut` captures and returns the registration status, and `update` propagates it:

```swift
    @discardableResult
    func update(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        let status = applyShortcut(keyCode: keyCode, modifiers: modifiers)
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: HotkeyDefaults.captureKeyCodeKey)
        defaults.set(Int(modifiers), forKey: HotkeyDefaults.captureModifiersKey)
        return status
    }

    @discardableResult
    private func applyShortcut(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        hotKeyRef = newRef
        currentKeyCode = keyCode
        currentModifiers = modifiers
        return status
    }
```

(The `register(...)` call site already ignores the return of `applyShortcut`; `@discardableResult` keeps it clean.)

- [ ] Create `Atlas/Services/CaptureShortcutSync.swift`:

```swift
import SwiftUI
import Carbon
import AtlasCore

/// Single sync point between the in-app capture shortcut (ShortcutStore, SwiftUI
/// Character + EventModifiers) and the system-wide Carbon hotkey (HotkeyService,
/// keycode + Carbon mask). ShortcutStore's `.capture` binding is the source of
/// truth; the Carbon hotkey is always derived from it, so the two can never drift.
enum CaptureShortcutSync {

    /// Reverse of HotkeyService.asciiCharFor — SwiftUI Character → Carbon virtual keycode.
    static func carbonKeyCode(for char: Character) -> UInt32? {
        let map: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            " ": kVK_Space
        ]
        let lower = Character(String(char).lowercased())
        return map[lower].map { UInt32($0) }
    }

    /// SwiftUI EventModifiers → Carbon modifier mask.
    static func carbonModifiers(from mods: EventModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if mods.contains(.command) { mask |= UInt32(cmdKey) }
        if mods.contains(.shift)   { mask |= UInt32(shiftKey) }
        if mods.contains(.option)  { mask |= UInt32(optionKey) }
        if mods.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// Persist a new capture binding to BOTH representations atomically and register
    /// the Carbon hotkey. Returns the registration OSStatus (`noErr` == success).
    /// If the character has no Carbon keycode, the in-app binding is still saved and
    /// `eventInternalErr` is returned so the caller can prompt for another combo.
    @discardableResult
    static func apply(_ binding: ShortcutBinding, to shortcuts: ShortcutStore) -> OSStatus {
        shortcuts.set(binding, for: .capture)
        guard let keyCode = carbonKeyCode(for: binding.key) else {
            return OSStatus(eventInternalErr)
        }
        let mask = carbonModifiers(from: binding.modifiers)
        return HotkeyService.shared.update(keyCode: keyCode, modifiers: mask)
    }

    /// At launch, derive the Carbon hotkey from the in-app `.capture` binding so the
    /// two never drift from previously-stored divergent values. Call AFTER
    /// HotkeyService.shared.register(...).
    static func reconcileOnLaunch(_ shortcuts: ShortcutStore) {
        let binding = shortcuts.binding(for: .capture)
        guard let keyCode = carbonKeyCode(for: binding.key) else { return }
        HotkeyService.shared.update(keyCode: keyCode, modifiers: carbonModifiers(from: binding.modifiers))
    }

    /// Best-effort match against well-known macOS system defaults. Returns a
    /// human-readable owner string, or nil. Not exhaustive — there is no API to
    /// enumerate other apps' custom binds (e.g. Raycast); Carbon registration
    /// failure in `apply` covers those.
    static func systemConflict(_ binding: ShortcutBinding) -> String? {
        let k = Character(String(binding.key).lowercased())
        let m = binding.modifiers
        if m == [.command] && k == " " { return "Spotlight" }
        if m == [.command] && k == "q" { return "Quit" }
        if m == [.command] && k == "w" { return "Close window" }
        if m == [.command] && k == "h" { return "Hide" }
        if m == [.command] && k == "m" { return "Minimize" }
        if m == [.command] && k == "," { return "Settings" }
        if m == [.command] && k == "\t" { return "App switcher" }
        if m == [.command, .shift] && k == "3" { return "Screenshot" }
        if m == [.command, .shift] && k == "4" { return "Screenshot" }
        if m == [.command, .shift] && k == "5" { return "Screenshot" }
        return nil
    }
}
```

- [ ] Wire `reconcileOnLaunch` in `AtlasApp.swift` `GlobalHotkeyInstaller.onAppear`, immediately after `HotkeyService.shared.register { ... }`. `GlobalHotkeyInstaller` must receive the `ShortcutStore`; add a `let shortcuts: ShortcutStore` stored property (mirroring `state`/`auth`) and pass `shortcuts` from `body` (`.background(GlobalHotkeyInstaller(state: state, auth: auth, shortcuts: shortcuts))`). Then:

```swift
                CaptureShortcutSync.reconcileOnLaunch(shortcuts)
```

- [ ] Donate the global-capture event (tip #6 retire) at the hotkey-fire site. In `AtlasApp.swift` `GlobalHotkeyInstaller`, inside the `HotkeyService.shared.register { ... }` closure, add before/after `CapturePanelController.shared.toggle()`:

```swift
                    Task { await AtlasTipEvents.usedGlobalCapture.donate() }
```

**Verify**
- [ ] `xcodegen generate` (new file `CaptureShortcutSync.swift` must be added to the Atlas target) then Mac build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew): with a fresh default (⌘⇧K), press ⌘⇧K from another app → capture panel appears (proves reconcile registered the derived hotkey). This task has no rebind UI yet (Task 5); the check is only that the default still fires after the reconcile path replaced the register-time value.

**Commit**
```
feat(shortcuts): single sync point between in-app capture binding and Carbon hotkey
```

---

## Task 5 — Global Capture Key first-run popup + permanent Settings rebind

New-account first-run sheet (new accounts only) that shows the capture key, lets the user keep or re-record it (via `CaptureShortcutSync.apply`), and a "Try it now" that opens the floating capture panel. Plus a permanent Settings section that replaces the "deferred (v2)" copy with a real global-capture rebind.

**Files**
- Modify `AtlasCore/Sources/AtlasCore/SupabaseAuth.swift` (add `createdAt: String?` to `SupabaseUser`)
- Create `Atlas/Views/Onboarding/CaptureKeyPopup.swift` (the first-run sheet + recorder)
- Modify `Atlas/App/AtlasApp.swift` (present the sheet on the signed-in route when new-account + unseen; add the new-account decision helper)
- Modify `Atlas/Views/Auth/SettingsView.swift` (replace `shortcutsSection`'s "deferred (v2)" line with a global-capture rebind row using `CaptureShortcutSync`)

**Interfaces**
- Produces: `struct CaptureKeyPopup: View` (sheet content); `enum CaptureKeyOnboarding { static func shouldShow(session:) -> Bool; static func markSeen() }`.
- Consumes: `CaptureShortcutSync.apply`, `ShortcutStore`, `HotkeyService.currentDisplayString()`, `CapturePanelController.shared.show()`.

**Steps**

- [ ] Add the creation timestamp to `SupabaseUser` (`SupabaseAuth.swift:5`). Decode as an **optional String** so a missing/odd value can never throw:

```swift
public struct SupabaseUser: Codable, Equatable {
    public let id: String
    public let email: String?
    public let userMetadata: [String: AnyCodable]?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case userMetadata = "user_metadata"
        case createdAt = "created_at"
    }
    // ... existing displayName computed var unchanged ...
```

- [ ] Add the new-account decision helper. Put it in `CaptureKeyPopup.swift` (Mac target) so it can reference `SupabaseSession`:

```swift
import SwiftUI
import AtlasCore

enum CaptureKeyOnboarding {
    private static let seenKey = "onboarding.captureKeyPopupSeen"

    /// New account = session user created within 7 days AND the popup never shown on
    /// this device. If GoTrue omits created_at (nil) we treat the user as NOT new
    /// (safe — tip #6 backstops). Existing users' accounts are older than 7 days.
    static func shouldShow(session: SupabaseSession?) -> Bool {
        guard !UserDefaults.standard.bool(forKey: seenKey),
              let iso = session?.user.createdAt,
              let created = parseISO(iso) else { return false }
        return Date().timeIntervalSince(created) < 7 * 24 * 60 * 60
    }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
```

- [ ] Build the sheet in `CaptureKeyPopup.swift`. It uses the SAME `NSEvent` recorder pattern as `SettingsView.startRecording` (verified L1679-1737) and writes through `CaptureShortcutSync.apply`. "Try it now" calls `CapturePanelController.shared.show()`. Full view:

```swift
struct CaptureKeyPopup: View {
    @EnvironmentObject private var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss

    @State private var recording = false
    @State private var recordMonitor: Any?
    @State private var warning: String?

    private var binding: ShortcutBinding { shortcuts.binding(for: .capture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").foregroundStyle(AtlasTheme.Colors.accent)
                Text("Your Global Capture Key")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Text("Press \(binding.displayString) from any app to capture — type a task or speak it. Change it here or anytime in Settings.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(recording ? "…" : binding.displayString)
                    .atlasMono(size: 14, weight: .semibold)
                    .foregroundStyle(recording ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))
                Button(recording ? "Cancel" : "Record a new key") {
                    recording ? stopRecording() : startRecording()
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }

            if let warning {
                Text(warning).atlasFont(size: 12, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.warning)
            }

            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button("Try it now") {
                    finish()
                    CapturePanelController.shared.show()
                }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(AtlasTheme.Colors.bgBase)
        .onDisappear { stopRecording() }
    }

    private func finish() {
        CaptureKeyOnboarding.markSeen()
        dismiss()
    }

    private func startRecording() {
        stopRecording()
        warning = nil
        recording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.lowercased().first, first != "\u{0}" else { return event }
            if event.keyCode == 53 { DispatchQueue.main.async { stopRecording() }; return nil }
            var mods = EventModifiers()
            let flags = event.modifierFlags
            if flags.contains(.command) { mods.insert(.command) }
            if flags.contains(.option)  { mods.insert(.option) }
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.shift)   { mods.insert(.shift) }
            DispatchQueue.main.async {
                guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
                    warning = "Add ⌘, ⌥, or ⌃"; stopRecording(); return
                }
                let candidate = ShortcutBinding(key: first, modifiers: mods)
                if let other = shortcuts.conflict(candidate, excluding: .capture) {
                    warning = "Conflicts with \(other.title) — not saved."; stopRecording(); return
                }
                if let owner = CaptureShortcutSync.systemConflict(candidate) {
                    warning = "macOS uses that for \(owner) — pick another."; stopRecording(); return
                }
                let status = CaptureShortcutSync.apply(candidate, to: shortcuts)
                if status != noErr {
                    warning = "Something else owns that combo — pick another."
                }
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        recording = false
    }
}
```

- [ ] Present the sheet from the signed-in route in `AtlasApp.swift`. In `AppGate`'s signed-in `Group` (the `RootView()` branch, ~L272), add `@State private var showCaptureKeyPopup = false`, a `.sheet(isPresented: $showCaptureKeyPopup) { CaptureKeyPopup().environmentObject(shortcuts) }`, and set it in the existing `.task` after `bootstrap` completes: `showCaptureKeyPopup = CaptureKeyOnboarding.shouldShow(session: auth.session)`. Inject `shortcuts` into `AppGate` (add `@EnvironmentObject private var shortcuts: ShortcutStore`). Add a one-line debug log to confirm the created_at signal on-device: `#if DEBUG print("[onboarding] session created_at = \(auth.session?.user.createdAt ?? "nil")") #endif`.

- [ ] Replace the "deferred (v2)" Settings copy with a real global-capture rebind. In `SettingsView.swift` `shortcutsSection` (L1572-1596), change the subtitle line (L1575) to:

```swift
            Text("Rebind the in-app and system-wide capture keys. The Global Capture Key works from any app.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
```

- [ ] Route the `.capture` rebind through the sync layer. In `SettingsView.startRecording` (L1721-1724), where a valid non-conflicting candidate is currently saved with `shortcuts.set(candidate, for: action)`, branch on the action so the capture action also updates the Carbon hotkey and checks system + Carbon conflicts:

```swift
                } else if action == .capture {
                    if let owner = CaptureShortcutSync.systemConflict(candidate) {
                        conflictWarning = "macOS uses that for \(owner)."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { conflictWarning = nil }
                    } else {
                        conflictWarning = nil
                        let status = CaptureShortcutSync.apply(candidate, to: shortcuts)
                        if status != noErr {
                            conflictWarning = "Something else owns that combo — pick another."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { conflictWarning = nil }
                        }
                    }
                } else {
                    conflictWarning = nil
                    shortcuts.set(candidate, for: action)
                }
```

(Keep the existing `.search` path as the plain `shortcuts.set`.)

**Verify**
- [ ] `xcodegen generate` (new file `CaptureKeyPopup.swift`), then `cd AtlasCore && swift build` (SupabaseUser change) → complete, then Mac build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew):
  - **New account:** create a brand-new account → after data loads, the popup appears once. Record a new combo → badge updates; press it from another app → capture panel opens. "Try it now" → floating panel appears with the mic button. Relaunch → popup does NOT reappear.
  - **Existing account:** sign in as yourself → popup NEVER appears. (Check the DEBUG console line prints a real `created_at`; if it prints `nil`, the created_at signal isn't coming through — report back before shipping.)
  - **Settings:** the SHORTCUTS section no longer says "deferred (v2)"; rebinding Quick Capture updates BOTH the in-app shortcut and the global hotkey (verify the global combo fires from another app after the change).

**Commit**
```
feat(capture): global capture key first-run popup + permanent Settings rebind
```

---

## Task 6 — iOS tips + event donations

The "both" tips on iOS (drag/schedule variant #2, connect #3, report bug #5) plus their donations. iOS has no search, notes, doc tabs, frozen islands, invite, or global hotkey — those tips are Mac-only (spec §2 footnotes).

**Files**
- Modify `AtlasMobile/Views/Schedule/ScheduleView.swift` (drag/schedule anchor + donation on `confirmPlace`; connect rule param)
- Modify `AtlasMobile/Views/Capture/CaptureView.swift` (capture donation in `commit`/`commitAll`)
- Modify `AtlasMobile/Views/Settings/SettingsView.swift` (connect anchor on the Integrations Canvas row; connect donation after `canvas.connect` ~L618; report-bug anchor on the "Report a bug" navRow L77)
- Modify `AtlasMobile/Data/MobileStore.swift` (set `AtlasTips.ConnectSource.hasConnection` when connections load, in `refresh`/`loadConnections`)

**Interfaces** — Consumes `AtlasTips.*`, `AtlasTipEvents.*`. Add `import TipKit` to iOS files using `.popoverTip`.

**Steps**

- [ ] **Tip #2 (iOS) anchor + rule + donation.** In `ScheduleView.swift`: set `AtlasTips.DragToSchedule.hasUnscheduled = !needsTime.isEmpty` in `.onAppear` (L90) and on `.onChange(of: needsTime.count)`. Add `@State private var dragTip = AtlasTips.DragToSchedule()` and attach `.popoverTip(dragTip)` to the `NeedsTimeSection` in `listBody`/`gridBody`. In `confirmPlace()` (L394-403), after the `store.updateTask` call add:

```swift
        Task { await AtlasTipEvents.scheduledOnCalendar.donate() }
```

- [ ] **Tip #3 (iOS) rule + anchor + donation.** In `MobileStore.swift` where connections load (`loadConnections` / after `refresh`), set `AtlasTips.ConnectSource.hasConnection` to whether any Google/Canvas connection exists. In `AtlasMobile/Views/Settings/SettingsView.swift`, add `@State private var connectTip = AtlasTips.ConnectSource()` and `.popoverTip(connectTip)` on the Canvas connect row in `integrationsPage`. After the successful `try await canvas.connect(...)` in `connectCanvas()` (~L618, before `await loadConnections()`), add:

```swift
                await AtlasTipEvents.connectedSource.donate()
                AtlasTips.ConnectSource.hasConnection = true
```

- [ ] **Tip #5 (iOS) anchor + donation.** In `AtlasMobile/Views/Settings/SettingsView.swift`, add `@State private var bugTip = AtlasTips.ReportBug()` and attach `.popoverTip(AtlasBuild.isBeta ? bugTip : nil)` to the "Report a bug" navRow (L77). In `ReportBugPage`'s submit action, donate `Task { await AtlasTipEvents.reportedBug.donate() }`.

- [ ] **Tip: capture donation.** In `CaptureView.swift` `commit(_:)` (L400) — after the task/event is added (`store.addTask`/`store.addEvent`, L411/L424) — add `Task { await AtlasTipEvents.captured.donate() }`. (There is no capture tip on iOS, but the `captured` event feeds the iOS checklist in Task 7; donate it here.)

**Verify**
- [ ] `xcodegen generate` then iOS build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew, on device with `showAllTipsForTesting()` temporarily on): the drag/schedule tip shows on the "Needs a time" section (copy matches the tap-to-place interaction), the connect tip on the Canvas row, the report-bug tip on the settings row (beta). Each dismisses on ✕ and after doing the action. Revert `showAllTipsForTesting()` before commit.

**Commit**
```
feat(tips): iOS anchors + donations for drag/schedule, connect, report-bug
```

---

## Task 7 — iOS getting-started checklist card

A dismissible "Get started" card on the Schedule home, `n of 4 done`, auto-checking from donated events, plus a soft "Add the Atlas widget" bonus that never blocks completion.

**Files**
- Create `AtlasMobile/Views/Schedule/GetStartedCard.swift`
- Modify `AtlasMobile/Views/Schedule/ScheduleView.swift` (host the card at the top of `listBody`/`gridBody` content)

**Interfaces**
- Produces: `struct GetStartedCard: View`. Persistence via **@AppStorage** (simpler than a TipKit tip here — the card is 4 heterogeneous items with a manual dismiss, not a single TipKit popover; @AppStorage booleans map cleanly to each item and to the dismissed flag). Each item's done-state is derived from the corresponding donated `Tips.Event` donation count (read via the event's datastore) OR from a mirrored @AppStorage bool flipped at the same donation sites. **Chosen: mirror to @AppStorage** at the donation sites, because reading a TipKit event's donation count for UI state is awkward and undocumented for synchronous SwiftUI reads.

**Steps**

- [ ] At each iOS donation site (Task 6), ALSO set a mirror flag so the card can read it synchronously. Add these one-liners next to the donations:
  - connect: `UserDefaults.standard.set(true, forKey: "checklist.connected")`
  - capture (`CaptureView.commit`): `UserDefaults.standard.set(true, forKey: "checklist.captured")`
  - schedule (`ScheduleView.confirmPlace` + `moveTask`): `UserDefaults.standard.set(true, forKey: "checklist.scheduled")`
  - month peek: in `ScheduleView`, when `showMonth` becomes true (the calendar glyph, L123-127), set `UserDefaults.standard.set(true, forKey: "checklist.month")` and donate `AtlasTipEvents.peekedMonth`.

- [ ] Create `AtlasMobile/Views/Schedule/GetStartedCard.swift`:

```swift
import SwiftUI
import WidgetKit

/// Dismissible "Get started" card on the Schedule home. Four core items auto-check
/// from the same actions the tips donate; a soft widget bonus never blocks 4/4.
struct GetStartedCard: View {
    @AppStorage("checklist.connected") private var connected = false
    @AppStorage("checklist.captured")  private var captured = false
    @AppStorage("checklist.scheduled") private var scheduled = false
    @AppStorage("checklist.month")     private var month = false
    @AppStorage("checklist.dismissed") private var dismissed = false

    @State private var widgetAdded = false

    private var doneCount: Int { [connected, captured, scheduled, month].filter { $0 }.count }
    private var complete: Bool { doneCount == 4 }

    var body: some View {
        if dismissed || complete {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Get started")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                    Spacer()
                    Text("\(doneCount) of 4")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MobileTheme.faint)
                    }.buttonStyle(.plain)
                }
                row(connected, "Connect Google or Canvas")
                row(captured, "Capture your first task")
                row(scheduled, "Put something on the calendar")
                row(month, "Peek at month view")
                row(widgetAdded, "Add the Atlas widget", soft: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.bg))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .task { await checkWidget() }
        }
    }

    private func row(_ done: Bool, _ title: String, soft: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? MobileTheme.ink : MobileTheme.faint)
            Text(title + (soft ? "  ·  optional" : ""))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(done ? MobileTheme.muted : MobileTheme.ink)
                .strikethrough(done, color: MobileTheme.muted)
            Spacer()
        }
    }

    /// Soft auto-check: WidgetCenter reports installed widget kinds. No signal if
    /// none added — stays a plain instruction row (never blocks completion).
    private func checkWidget() async {
        let atlasKinds: Set<String> = ["AtlasToday", "AtlasLockRect", "AtlasLockCircular"]
        let infos = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        widgetAdded = infos.contains { atlasKinds.contains($0.kind) }
    }
}
```

- [ ] Host the card at the top of the Schedule content. In `ScheduleView.swift` `listBody` (inside the `List`, above `NeedsTimeSection`) and `gridBody` (in the `VStack`, above `NeedsTimeSection`), add `GetStartedCard()`. In `List`, wrap it so it has no row chrome: `GetStartedCard().listRowSeparator(.hidden).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)`.

**Verify**
- [ ] `xcodegen generate` then iOS build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew, device): fresh account shows "Get started · 0 of 4". Doing each action (connect, capture, schedule, open month) ticks its row and increments the count; at 4/4 the card disappears. The ✕ dismisses it permanently. Adding the Atlas widget to the home screen and returning ticks the soft row without being required for completion.

**Commit**
```
feat(ios): getting-started checklist card on the Schedule home
```

---

## Task 8 — iOS 2-step calendar-views spotlight

A skippable dim+cutout spotlight on first Schedule visit: step 1 highlights the list/grid toggle (advance when tapped), step 2 highlights the calendar glyph (finish when month opens). Custom SwiftUI (TipKit has no spotlight). Shown once ever.

**Files**
- Create `AtlasMobile/Views/Schedule/CalendarSpotlight.swift` (overlay + coordinator)
- Modify `AtlasMobile/Views/Schedule/ScheduleView.swift` (report anchor frames; host the overlay; drive step advance)

**Interfaces**
- Produces: `struct CalendarSpotlightOverlay: View`; a `SpotlightAnchorKey: PreferenceKey` to collect the two anchor frames; `@AppStorage("spotlight.calendarViews.done")` persistence.
- Consumes: the `viewToggle` (L167) and calendar-glyph (L123-127) frames.

**Steps**

- [ ] Create `AtlasMobile/Views/Schedule/CalendarSpotlight.swift`:

```swift
import SwiftUI

/// Collects named anchor frames (toggle, calendar glyph) from the header so the
/// spotlight can cut a hole over the right control.
struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's frame in global space under `id`.
    func spotlightAnchor(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: SpotlightAnchorKey.self, value: [id: geo.frame(in: .global)])
        })
    }
}

/// The dim + cutout overlay. `step` 0 highlights the toggle, 1 the calendar glyph.
/// `onSkip` finishes immediately. Anchors come from the ScheduleView header.
struct CalendarSpotlightOverlay: View {
    let step: Int
    let anchors: [String: CGRect]
    let onSkip: () -> Void

    private var holeID: String { step == 0 ? "toggle" : "calendar" }
    private var caption: String {
        step == 0 ? "Switch between list and grid" : "Tap to jump to any day in month view"
    }

    var body: some View {
        GeometryReader { _ in
            let hole = (anchors[holeID] ?? .zero).insetBy(dx: -8, dy: -8)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.black.opacity(0.55))
                    .mask(
                        Rectangle()
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .frame(width: hole.width, height: hole.height)
                                .position(x: hole.midX, y: hole.midY)
                                .blendMode(.destinationOut))
                            .compositingGroup()
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)   // taps pass through to the real control

                Text(caption)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .position(x: hole.midX, y: hole.maxY + 28)

                Button("Skip", action: onSkip)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                    .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.maxY - 80)
            }
        }
    }
}
```

- [ ] In `ScheduleView.swift`, tag the two anchors: add `.spotlightAnchor("toggle")` on `viewToggle` (L167) and `.spotlightAnchor("calendar")` on the calendar-glyph Button (L123-127).

- [ ] Add spotlight state to `ScheduleView`: `@AppStorage("spotlight.calendarViews.done") private var spotlightDone = false`, `@State private var spotlightStep = 0`, `@State private var spotlightAnchors: [String: CGRect] = [:]`, `@State private var spotlightActive = false`.

- [ ] Host + drive it. On the outer `VStack` (body, L30) add:

```swift
        .onPreferenceChange(SpotlightAnchorKey.self) { spotlightAnchors = $0 }
        .onAppear { if !spotlightDone { spotlightActive = true } }
        .overlay {
            if spotlightActive {
                CalendarSpotlightOverlay(step: spotlightStep, anchors: spotlightAnchors) {
                    spotlightActive = false; spotlightDone = true
                }
            }
        }
        .onChange(of: viewMode) { _, _ in
            if spotlightActive && spotlightStep == 0 { spotlightStep = 1 }   // step 1 → advance on toggle tap
        }
        .onChange(of: showMonth) { _, opened in
            if spotlightActive && spotlightStep == 1 && opened {
                spotlightActive = false; spotlightDone = true                // step 2 → finish on month open
            }
        }
```

**Verify**
- [ ] iOS build command → **BUILD SUCCEEDED**.
- [ ] Manual (Drew, device): fresh install first Schedule visit dims the screen with a cutout over the list/grid toggle and a caption. Tapping the toggle (which works through the hole) advances to the calendar glyph. Tapping the glyph opens month and ends the spotlight. "Skip" ends it immediately. Relaunch → never shown again. (Reset by deleting the app or clearing `spotlight.calendarViews.done`.)

**Commit**
```
feat(ios): 2-step calendar-views spotlight on first schedule visit
```

---

## Task 9 — Final integration pass

Wire the dev testing flag behind DEBUG, build all three targets, and produce the consolidated QA checklist.

**Files**
- Modify `AtlasCore/Sources/AtlasCore/AtlasTips.swift` (ensure `showAllTipsForTesting()` sits behind a `#if DEBUG` toggle that is OFF by default and clearly documented)

**Steps**

- [ ] Confirm `AtlasTips.configureOnce()` leaves `Tips.showAllTipsForTesting()` commented/off for normal Debug runs (it should only be flipped on manually for QA). Add a short comment block pointing QA at it.

- [ ] Full builds:
  - [ ] `cd AtlasCore && swift build` → complete.
  - [ ] `xcodegen generate`
  - [ ] Mac: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**.
  - [ ] iOS: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**.

- [ ] **Consolidated manual QA checklist for Drew** (device, not simulator, per Drew's rule):

  **Mac tips** (with `showAllTipsForTesting()` on for the sweep, then a clean run for rule timing):
  - [ ] #1 ⌘K on sidebar search; retires after using search.
  - [ ] #2 drag-to-schedule on unscheduled tray; retires after a drag-drop.
  - [ ] #3 connect tip in Integrations; retires after connecting Google or Canvas.
  - [ ] #4 per-calendar tip inside the auto-opened connection sheet.
  - [ ] #5 report-a-bug tip on sidebar (beta only).
  - [ ] #6 global-capture tip; retires after pressing the global key.
  - [ ] #7 doc-tabs tip in a multi-tab note.
  - [ ] #8 Drive-sync tip in a Drive-linked note.
  - [ ] #9 frozen-island tip when a shaded block is visible.
  - [ ] #10 invite tip on a solo space page; retires after sending an invite.

  **Mac `.help()`:** hover each icon-only button → correct one-line tooltip.

  **Mac capture key:**
  - [ ] New account → popup once; record/keep/skip/try-it-now all work; never reappears.
  - [ ] Existing account → popup never appears (DEBUG log shows a real `created_at`).
  - [ ] Settings SHORTCUTS no longer says "deferred (v2)"; rebinding Quick Capture updates BOTH in-app and global; global fires from another app.

  **iOS tips:** #2 (tap-to-place copy), #3 (Canvas connect), #5 (report bug, beta) all show and retire.

  **iOS checklist:** 0→4 auto-ticks (connect, capture, schedule, month); disappears at 4/4; ✕ dismisses; widget row soft-ticks after adding the widget.

  **iOS spotlight:** first Schedule visit → step 1 toggle → step 2 calendar glyph → month; Skip works; never shown again.

- [ ] Confirm no `showAllTipsForTesting()` is left enabled in any committed file.

**Commit**
```
chore(tips): dev testing flag gating + final three-target build pass
```

---

## Coverage check against the spec

- §1 Mac `.help()` sweep → Task 3.
- §2 ten TipKit tips (defs in AtlasCore, per-platform copy, appear-on-anchor triggers, event donations, ✕ dismiss, one at a time, configure once, showAllTipsForTesting) → Tasks 1, 2, 6. Mac-only vs both vs footnoted-out (search/notes/tabs/islands/invite Mac-only; drag/connect/report both) all honored.
- §3 Global Capture Key (first-run popup new-accounts-only, permanent Settings rebind, best-effort conflict handling incl. Carbon failure + system table, single sync point across both UserDefaults encodings, new-account detection) → Tasks 4, 5.
- §4 iOS getting-started checklist (4 core auto-check items, month replaces note, soft widget bonus, dismiss/complete persistence) → Task 7.
- §5 iOS 2-step calendar spotlight (dim+cutout, skip, once-only, custom SwiftUI) → Task 8.
- Out-of-scope items (extra spotlights, welcome carousel, Mac checklist, iOS global capture, Gmail/monetization, list-scope tip) → none added.
