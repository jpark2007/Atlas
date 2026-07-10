# Mobile Wave 3 — Fix + UX Wave Implementation Plan

> **For agentic workers:** executed via subagent-driven development, one Opus implementer per task. Drew has waived spec review; he device-tests via TestFlight. NO simulator pass this wave — verification is code review + `swift test` + both xcodebuild targets.

**Goal:** Drew's TestFlight feedback + gap-audit fixes: shell layout, capture ergonomics, truthful colors, an editable detail sheet, a real hour-grid day view with drag-to-place scheduling, month dots, trust/feedback surfaces, widget fixes, offline cache.

**Architecture:** All iOS (AtlasMobile) + small AtlasCore additions + one edge-function prompt line. Tasks grouped by disjoint file ownership so they can run in parallel worktrees; two Schedule-owning tasks run sequentially in the main tree.

## Global Constraints

- Repo: `/Users/drewkhalil/Documents/atlas life manager` (paths contain spaces — always quote).
- Editorial Minimal LIGHT: bg #fbfaf7, ink #1a191d, clay accent #d97757 = live/NOW/brand ONLY (never a button fill); controls transparent w/ 1.5pt ink outlines; SF Pro Rounded; space color = meaning. Use `MobileTheme.spring`/`heroSpring`/`Haptic` — never invent curves/haptics.
- iOS build: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` (default signing — CODE_SIGNING_ALLOWED=NO breaks launch, harmless for build; keep default). Mac build must stay green when AtlasCore changes: scheme `Atlas`, `-destination 'platform=macOS'`.
- AtlasCore tests: `cd AtlasCore && swift test` (currently 26/26 — must not regress).
- New files under `AtlasMobile/` require `xcodegen generate` before building. NEVER `git add` Atlas.xcodeproj (gitignored).
- NEVER stage Drew's uncommitted files: `AtlasMobile/AtlasMobile.entitlements`, `AtlasMobileWidgets/AtlasMobileWidgets.entitlements`, `AtlasMobileWidgets/SharedSnapshot.swift`, `project.yml`, `AtlasMobile/Assets.xcassets/`. Do not EDIT SharedSnapshot.swift at all — reference `SharedSnapshot.appGroup` from other files.
- UI feel is not provable by a green build — reports say "applied, builds; Drew verifies on device."
- One commit per task with the message given; stage only files you created/edited for the task.

---

### Task 1: Trust pack — forgot password, sign-out reason (worktree)

**Files:** Modify `AtlasCore/Sources/AtlasCore/SupabaseAuth.swift`, `AtlasMobile/Views/SignInView.swift`, `AtlasMobile/Data/MobileStore.swift` (auth-notice only), Test `AtlasCore/Tests/AtlasCoreTests/` (request-shape test only if a pure seam exists; otherwise none).

**Interfaces produced:**
- `SupabaseAuth.resetPassword(email: String) async throws` — POST `{SupabaseConfig.url}/auth/v1/recover` with `{"email": ...}`, apikey header, same `request(...)` pattern as signIn. Fire-and-forget semantics (2xx = ok).
- `MobileStore.authNotice: String?` `@Published` — set to "Your session expired — please sign in again." inside the forced-sign-out path in `refresh()` (the `signOut()` call at the 401-refresh-failure branch ONLY, not user-initiated `signOut()`); cleared on successful `signIn`.
- SignInView: under the Sign in button add a plain caps-label "Forgot password?" button → prompts for/uses the typed email → calls resetPassword → shows calm inline note "Check your email for a reset link." (error → "Couldn't send the reset email."). At top, if `store.authNotice != nil`, show it as a muted line; do not block sign-in.

Behavior only — match SignInView's existing field/label styling exactly. Build iOS + Mac, run swift test.
Commit: `feat(mobile): forgot password + session-expired notice`

---

### Task 2: Shell pack — inline gear, insets, error banner, loading, notification honesty (main tree)

**Files:** Modify `AtlasMobile/Views/RootTabView.swift`, `AtlasMobile/Views/Schedule/ScheduleView.swift` (header only), `AtlasMobile/Views/Tasks/TasksView.swift` (header/empty only), `AtlasMobile/Views/Capture/CaptureView.swift` (title row only), `AtlasMobile/Views/Settings/SettingsView.swift`.

1. **Kill the nav-bar tax:** RootTabView drops the per-tab `NavigationStack` + toolbar gear entirely. Each of the three screens gets the gear inline: a 17pt `gearshape` ink button trailing in its existing title/header row (Schedule: in the `HStack` with the day label, after the chevrons/Spacer; Tasks + Capture: `HStack { Text(title).edScreenTitle(); Spacer(); gear }`). Gear presents `SettingsView` in a `.sheet` — wrap SettingsView in a `NavigationStack` INSIDE the sheet with title "Settings" + a Done button (`.topBarTrailing`) that dismisses. Keep tab items unchanged.
2. **Tab-bar inset:** every `List`/`ScrollView` on the three tabs gets `.contentMargins(.bottom, 72, for: .scrollContent)` so the last row clears the floating tab bar.
3. **Error banner:** RootTabView overlays top: when `store.lastError != nil` show a capsule banner (bg, ink text 13 rounded, hairline border) with the message; auto-clear `store.lastError = nil` after 4s (debounced Task); tap to dismiss. `.transition(.move(edge: .top).combined(with: .opacity))`, `MobileTheme.spring`.
4. **Loading state:** in TasksView's empty branch and DayTimelineView's "Nothing scheduled" row, when `store.loading` is true show `ProgressView().tint(MobileTheme.muted)` instead of the empty-copy (pass loading into DayTimelineView or read the environment store there — prefer reading `@EnvironmentObject` in ScheduleView and passing a `Bool`).
5. **Notification honesty:** SettingsView loads `UNUserNotificationCenter.current().notificationSettings()` in `.task` into `@State private var osAuthorized: Bool?`. When explicitly denied: replace the toggles block with a labeledRow("Notifications", value: "Off — enable in Settings") + the existing Open Settings button pattern (copy the Voice section's approach). When authorized/undetermined: current UI.

Build iOS. Commit: `feat(mobile): inline settings gear, error banner, loading + notification honesty, tab-bar insets`

---

### Task 3: Capture pack — keyboard exit, visible times, sheet cancels (worktree)

**Files:** Modify `AtlasMobile/Views/Capture/CaptureView.swift`, `AtlasMobile/Views/Capture/CaptureResultCard.swift`, `AtlasMobile/Views/Capture/ManualAddSheet.swift`.

1. **Keyboard exit:** while `editorFocused`, show a 40pt circular outlined `chevron.down` button (ink, bg fill) floating bottom-trailing above the controls column; tap → `editorFocused = false` + `Haptic.selection()`. Keep the existing keyboard Done toolbar (harmless if it renders). Animate with `MobileTheme.spring`.
2. **Times visible before commit (stated times are sacred):** in `CaptureResultCard.row` meta line — for `kind == "event"`: show `start` as "Jul 3 · 5:30 PM" (+ "· 60 min" when durationMin != nil) as the tappable chip instead of the due chip; for tasks the existing `dueLabel` chip already carries times. The due editor sheet gains a "Set a time" toggle + wheel `.hourAndMinute` picker (copy ManualAddSheet's `dueSection` pattern): for tasks it writes the time into `due`; for events it edits `start`'s time. Add a "Done"/"Cancel" pair (Cancel restores the entry value).
3. **ManualAddSheet:** add a Cancel caps-label button (top-trailing of the title row) that dismisses; zero-spaces case: under the disabled Add button show muted 13pt note "Create a space on your Mac first — tasks need a home."
4. **SetTimeSheet is Task 6's file — do not touch it.**

Build iOS. Commit: `feat(mobile): capture keyboard exit, event times visible pre-commit, sheet cancels`

---

### Task 4: Edge function title hygiene (worktree)

**Files:** Modify `supabase/functions/capture/index.ts` (prompt rules block only).

Add one rule bullet: titles must NOT contain the date/time words that were parsed into dueISO/startISO — "essay due next friday" → title "Essay"; "pick up Sam at 5:30" → title "Pick up Sam". Keep the title a clean noun/verb phrase. Deploy `supabase functions deploy capture --project-ref jxrmozhgsebwtbdleyxp`; curl once (creds from `AtlasCore/Sources/AtlasCore/SupabaseConfig.swift`, body `{"text":"math exam on friday","timezone":"America/New_York"}`) and confirm the returned title drops "on friday" and dueISO is the coming Friday local-midnight UTC. Commit: `fix(capture-fn): strip parsed date words from titles`

---

### Task 5: Data + detail pack — task recolor, detail sheet, event mutations (main tree, after Task 2)

**Files:** Modify `AtlasMobile/Data/MobileStore.swift`, `AtlasMobile/Views/Tasks/TasksView.swift` (rows), `AtlasMobile/Views/Schedule/DayTimelineView.swift` (rows + swipe), `AtlasMobile/Views/Schedule/NeedsTimeSection.swift` (row tap). Create `AtlasMobile/Views/Components/ItemDetailSheet.swift`.

1. **Recolor tasks (the orange-circles bug):** in `MobileStore.recolored(_:)`, also map `s.tasks` — set `task.spaceColor` from the space whose name case-insensitively matches `task.spaceName` (leave unmatched as-is). THE most visible fix of the wave.
2. **Event mutations:** add `MobileStore.updateEvent(_ e: CalendarEvent)` and `deleteEvent(id: UUID)` mirroring updateTask/deleteTask exactly (optimistic + `persist` + rollback; `db.upsertEvent`/`db.deleteEvent` both exist).
3. **ItemDetailSheet:** one sheet, `enum Detail { case task(TaskItem), event(CalendarEvent) }`. Editorial field style (copy ManualAddSheet's `field` helper). Task fields: title (TextField), space (Menu w/ color dot), project (TextField), due day+optional time (ManualAdd's dueSection pattern), notes (TextEditor 100pt). Event fields: title, space, start day+time, duration minutes (Menu: 15/30/45/60/90/120), notes. Editable when task OR `event.source == .atlas`; for `.google`/`.apple` events render values as read-only labeledRows plus a caps label "FROM GOOGLE CALENDAR — read-only" (true source name). Footer: Save (outline control; calls store.updateTask/updateEvent, dismiss, `Haptic.success()`) + Delete (destructive red text; tasks always, events only when `.atlas`; confirmationDialog) + Cancel caps-label. Presentation detents [.medium, .large].
4. **Wire taps:** TasksView row — content (title/due area) gets `onTapGesture` → present detail (CheckCircle keeps check-off exclusively). DayTimelineView rows — same (whole row minus the CheckCircle). NeedsTimeSection rows — row tap now opens DETAIL; keep the "set time" trailing chip as its own tap target calling `onSetTime`. Timeline swipe: allow Delete on `kind == .event` rows whose resolved event `source == .atlas` (calls a new `onDeleteEvent` closure passed from ScheduleView → `store.deleteEvent`).
5. **Overdue = red:** task rows (Tasks + timeline trailing due text if shown): when `task.dueDate` < now and !done, render the due text in `Color(hex: "c23b22")`-style red — check AtlasCore `AtlasTheme` for an existing warning/danger token first (`grep -rn "warning\|danger" AtlasCore/Sources/AtlasCore/Theme.swift`) and reuse it; only hardcode if none exists.

`xcodegen generate` (new file). Build iOS + Mac. Commit: `feat(mobile): item detail sheet, event edit/delete, task space colors, overdue red`

---

### Task 6: Day grid + placement pack (main tree, after Task 5)

**Files:** Create `AtlasMobile/Views/Schedule/DayGridView.swift`, `AtlasMobile/Views/Schedule/PlaceTaskSheet.swift`. Modify `ScheduleView.swift`, `DayTimelineView.swift` (deadline language), `MonthPageView.swift`, `SetTimeSheet.swift`.

1. **DayGridView** — a real hour grid for one day:
   - `ScrollView` containing a ZStack canvas: height = 24 × `hourHeight` (56). Left rail 66pt: hour labels ("8 AM") at each hour line, hairline horizontal rules across.
   - Blocks: events (start/end) + scheduled tasks (scheduledAt + durationMin ?? 60). y = minutesFromMidnight × 56/60, height = max(duration × 56/60, 26). Fill: `space color at 0.14 opacity`, 3pt leading bar solid space color, 13pt rounded-semibold ink title, time caps-label. Tasks get a small CheckCircle inline. Tap → same detail sheet (reuse closures from Task 5's ScheduleView wiring).
   - Overlaps: greedy cluster/column assignment — sort by start; overlapping items share the horizontal width equally (columns), 4pt gutters. Keep the algorithm simple and commented.
   - Deadlines (dueDate has a time, unscheduled or not): 1.5pt horizontal RED line at the due minute + tiny flag glyph + 11pt caps title right-aligned above the line. Red: same token as Task 5.
   - All-day items: chip row pinned above the scroll.
   - NOW: clay 2pt line + dot at current minute (today only), auto-scroll on appear to (now − 2h) today, else first item.
2. **Toggle:** `@AppStorage("scheduleViewMode")` "list"|"grid". In ScheduleView header next to the calendar glyph: two 15pt glyph buttons (`list.bullet` / `calendar.day.timeline.left`), active one ink, inactive faint, `Haptic.selection()`. Body swaps DayTimelineView-List ↔ DayGridView (keep NeedsTimeSection visible above BOTH — in grid mode render it as a compact section above the scroll).
3. **Placement flow:** "Needs a time" section header gains a trailing caps-label button "PLACE". Tap → `PlaceTaskSheet` (medium detent): a List of open, unscheduled tasks (space-filter respected; needsTime first, then no-date), rows = space dot + title + dueLabel. Pick one → sheet dismisses → ScheduleView flips to grid mode with `placing: TaskItem?` set → a floating chip (space-color 3pt bar, title, live time caps-label, slight shadow) rides the grid; vertical drag moves it, time = y→minutes snapped to 15, clamped 00:00–23:45; chip time label updates live. Confirm ✓ (44pt outlined circle, bottom-trailing) → `store.updateTask` with `scheduledAt` = selected day+time → `Haptic.success()` → exit placement. ✕ cancels. Day chevrons stay usable while placing (chip persists across day change; time keeps). Initial chip time: next 15-min slot after now (today) else 9:00 AM.
4. **Timeline (list) deadline language:** in DayTimelineView, deadline rows (task with dueDate at a clock time but no scheduledAt that day — mirror how AgendaBuilder marks them; inspect `AgendaBuilder`/`AgendaItem` for an isDeadline flag before inventing one) render: flag glyph instead of dot, "DUE" trailing tag, red time when overdue. Events keep dot + source tag; scheduled tasks keep CheckCircle.
5. **Month dots:** MonthPageView gains `@EnvironmentObject store`; each day cell shows up to 3 4pt dots (distinct space colors of that day's events by start + tasks by scheduledAt/dueDate), 4th "+" dot faint if more. Below the day number, 2pt spacing.
6. **SetTimeSheet:** add a compact date picker row (defaults to current `day`), a "Clear time" caps button (sets `scheduledAt = nil` via onSave with cleared field — extend the callback contract as needed at call sites), and a Cancel caps button.

`xcodegen generate`. Build iOS. Commit: `feat(mobile): hour-grid day view, drag-to-place scheduling, month dots, deadline language, set-time day+clear`

---

### Task 7: Widgets pack — lock rect redesign, honest gauge, offline snapshot cache (worktree)

**Files:** Modify `AtlasMobileWidgets/LockWidgets.swift`, `AtlasMobile/Data/WidgetSnapshotWriter.swift`. (MobileStore cache READ is delivered by coordination note below — implement it here ONLY in WidgetSnapshotWriter + a tiny static loader, NOT by editing MobileStore.) Create nothing unless needed.

1. **Rect lock widget:** compose Drew's wish inside ONE widget — leading column: big rounded-bold count + "LEFT" caps under it; thin divider; trailing: next item time + title (existing content). Uses only existing SharedSnapshot fields (read LockWidgets/SharedSnapshot first; do NOT edit SharedSnapshot.swift).
2. **Circular gauge honesty:** the current `total = max(leftCount + today.count, 1)` fill is meaningless. Replace with a count-only design: full ring stroke (no progress fill) + count centered + "LEFT" label — honest and legible.
3. **Offline snapshot cache (G1):** in `WidgetSnapshotWriter.write(_:)`, ALSO serialize the full snapshot to `snapshot-cache.json` in the same app-group container (`SharedSnapshot.appGroup`): encode `spaces/projects/tasks/events` via the existing Codable row types' `init(domain:)` (`SpaceRow`/`ProjectRow`/`TaskRow`/`EventRow` — verify each exists in AtlasDB.swift; if one lacks `init(domain:)`, add a minimal one to AtlasCore and keep the Mac build green). Add `WidgetSnapshotWriter.loadCache() -> AtlasSnapshot?` decoding rows → `toDomain()`. Expose it; **Task 8 wires the one-line MobileStore call** (`if let cached = WidgetSnapshotWriter.loadCache() { snapshot = recolored-equivalent }`) to avoid file conflicts — document the exact call in your report.

Build iOS + Mac + swift test (if AtlasCore touched). Commit: `feat(mobile): lock widget redesign + honest gauge, offline snapshot cache`

---

### Task 8: Integration — cache wire-up, final review, builds, push (controller)

1. Cherry-pick all worktree commits onto feat/mobile-phase1; wire the MobileStore cache-load line from Task 7's report into `MobileStore.init` (before the network bootstrap; only when a session exists) + commit `feat(mobile): load cached snapshot on launch`.
2. `cd AtlasCore && swift test` (≥26 pass, no regressions); iOS + Mac builds green.
3. Whole-wave Opus review (diff vs wave base); fix wave for Critical/Important.
4. `git push -u origin feat/mobile-phase1` (Drew authorized push after this wave).
5. Report to Drew: what shipped, what needs his device eyes, TestFlight next steps.
