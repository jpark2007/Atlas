# Atlas v2 — Foundation (Task Dates + Live Capture Pipeline) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give tasks a real `dueDate`, wire the AI's parsed dates into tasks, make capture failures visible instead of silent, and deploy the `capture` edge function so OpenRouter actually runs.

**Architecture:** `TaskItem` gains structured `dueDate`/`durationMin` (the DB row + Postgres column already exist and were hardwired to `nil`). A shared `CaptureDateParser` turns the edge function's ISO strings into `Date`s for both tasks and events (DRY). A `CaptureOutcome` enum centralizes confirmation copy and makes the "AI offline → saved as plain task" degraded path explicit. Finally the `capture` Deno function is deployed with the OpenRouter secret.

**Tech Stack:** Swift 5 / SwiftUI, macOS 14, XcodeGen (`project.yml`), XCTest, Supabase Edge Functions (Deno), OpenRouter (gpt-4o-mini).

**Phase 0 finding (already verified):** `POST .../functions/v1/capture` returns **HTTP 404** — the function is not deployed. Every parse silently falls back to a plain task via `CaptureOverlay.swift:239`. This plan fixes the data-loss-of-meaning, not just the deploy.

## Global Constraints

- **Deployment target:** macOS 14.0. **Swift:** 5.0. UI is SwiftUI.
- **Project generation:** sources are folder-based in `project.yml` (`Atlas`, `AtlasTests`). After creating ANY new file, run `xcodegen generate` before building so Xcode picks it up. If `xcodegen` is missing: `brew install xcodegen`.
- **Build/test command:** `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`. Single test: append `-only-testing:AtlasTests/<Class>/<method>`.
- **Tests:** XCTest, `@testable import Atlas`. Compare formatter output to formatter output (never hardcode locale-specific strings).
- **Capture must never lose data.** Keep the data-preserving fallback to a plain task on any error — but the user must SEE that AI was unavailable (no silent identical confirmation).
- **Never commit secrets.** Google creds live in gitignored `.env.local`; OpenRouter key is a Supabase function secret, never in the repo.
- DRY, YAGNI, TDD, frequent commits.

---

## File Structure

- **Modify** `Atlas/Models/Models.swift` — add `dueDate`/`durationMin` to `TaskItem`; add `TaskItem.dueLabel(for:now:)` formatter.
- **Modify** `Atlas/Services/AtlasDB.swift` — carry `dueDate` through `TaskRow.init(domain:)` and `toDomain()`.
- **Modify** `Atlas/Data/AppState.swift` — `addTask(title:dueDate:durationMin:)`.
- **Create** `Atlas/Services/CaptureDateParser.swift` — shared ISO→Date parser.
- **Create** `Atlas/Views/Capture/CaptureOutcome.swift` — confirmation copy + degraded state.
- **Modify** `Atlas/Views/Capture/CaptureOverlay.swift` — parse `dueISO` into tasks, use `CaptureDateParser` for events, surface degraded state.
- **Tests:** `AtlasTests/TaskItemDueDateTests.swift`, `AtlasTests/CaptureDateParserTests.swift`, `AtlasTests/CaptureOutcomeTests.swift`, `AtlasTests/AppStateCaptureTests.swift`; extend `AtlasTests/AtlasDBMappingTests.swift`.
- **Manual:** deploy `supabase/functions/capture/index.ts` + set `OPENROUTER_API_KEY` secret.

---

### Task 1: TaskItem structured dates + due-label formatter

**Files:**
- Modify: `Atlas/Models/Models.swift:64-73`
- Test: `AtlasTests/TaskItemDueDateTests.swift`

**Interfaces:**
- Produces: `TaskItem.dueDate: Date?`, `TaskItem.durationMin: Int?`, and `static func TaskItem.dueLabel(for date: Date?, now: Date = Date()) -> String`.

- [ ] **Step 1: Write the failing test** — create `AtlasTests/TaskItemDueDateTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Atlas

final class TaskItemDueDateTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func plus(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }

    func testNilDateIsEmptyLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: nil, now: now), "")
    }
    func testTodayLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: now, now: now), "Today")
    }
    func testTomorrowLabel() {
        XCTAssertEqual(TaskItem.dueLabel(for: plus(1), now: now), "Tomorrow")
    }
    func testWithinWeekUsesWeekday() {
        let d = plus(3)
        let f = DateFormatter(); f.dateFormat = "EEE"
        XCTAssertEqual(TaskItem.dueLabel(for: d, now: now), f.string(from: d))
    }
    func testBeyondWeekUsesMonthDay() {
        let d = plus(20)
        let f = DateFormatter(); f.dateFormat = "MMM d"
        XCTAssertEqual(TaskItem.dueLabel(for: d, now: now), f.string(from: d))
    }
    func testTaskItemCarriesDueDateAndDuration() {
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t = TaskItem(title: "Essay", dueLabel: "", dueDate: due, durationMin: 90)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 90)
    }
}
```

- [ ] **Step 2: Run it; verify it fails to compile** — `dueDate`/`durationMin`/`dueLabel(for:now:)` don't exist yet.

Run: `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/TaskItemDueDateTests`
Expected: build failure — "type 'TaskItem' has no member 'dueDate'".

- [ ] **Step 3: Add the fields + formatter** — in `Atlas/Models/Models.swift`, change the `TaskItem` struct (lines 64-73) to:

```swift
/// A task / to-do. `scheduledAt` is nil until it's dragged onto the calendar.
struct TaskItem: Identifiable {
    var id = UUID()
    var title: String
    var dueLabel: String
    var status: TaskStatus = .open
    var done: Bool = false
    var scheduledAt: Date? = nil
    var dueDate: Date? = nil
    var durationMin: Int? = nil
    var spaceColor: Color = AtlasTheme.Colors.accent
    var spaceName: String = ""
}

extension TaskItem {
    /// Short, human due label derived from a date. Deterministic given `now`.
    /// "" for nil; "Today"/"Tomorrow"; weekday ("Thu") within a week; else "MMM d".
    static func dueLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: date)).day ?? 0
        let f = DateFormatter()
        f.dateFormat = (days > 1 && days < 7) ? "EEE" : "MMM d"
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: Run the test; verify PASS.**

Run: same command as Step 2.
Expected: PASS (6 tests).

- [ ] **Step 5: Commit.**

```bash
git add Atlas/Models/Models.swift AtlasTests/TaskItemDueDateTests.swift
git commit -m "feat(model): TaskItem gains dueDate/durationMin + due-label formatter"
```

---

### Task 2: Persist dueDate through TaskRow

**Files:**
- Modify: `Atlas/Services/AtlasDB.swift:196-216`
- Test: `AtlasTests/AtlasDBMappingTests.swift` (add one test)

**Interfaces:**
- Consumes: `TaskItem.dueDate` (Task 1), `TaskItem.dueLabel(for:)` (Task 1).
- Produces: `TaskRow` round-trips `dueDate`; `toDomain()` populates both `dueDate` and a derived `dueLabel`.

- [ ] **Step 1: Write the failing test** — add to `AtlasTests/AtlasDBMappingTests.swift` inside the `// MARK: - TaskRow` group:

```swift
func testTaskRowDueDateRoundTrip() throws {
    let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let task = TaskItem(title: "Essay", dueLabel: "", dueDate: due)
    let row = TaskRow(domain: task)
    let decoded = try decoder.decode(TaskRow.self, from: try encoder.encode(row))
    XCTAssertEqual(decoded.dueDate, due, "due_date must survive encode/decode")
    XCTAssertEqual(decoded.toDomain().dueDate, due, "toDomain must restore dueDate")
}
```

- [ ] **Step 2: Run it; verify it fails** — `TaskRow(domain:)` currently sets `dueDate = nil`.

Run: `xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/AtlasDBMappingTests/testTaskRowDueDateRoundTrip`
Expected: FAIL — `XCTAssertEqual` nil vs date.

- [ ] **Step 3: Carry dueDate through the row** — in `Atlas/Services/AtlasDB.swift`, change `TaskRow.init(domain:)` line 201 and `toDomain()` (lines 207-216):

```swift
    init(domain t: TaskItem) {
        self.id          = t.id
        self.projectId   = nil // no projectId on TaskItem yet; map to nil
        self.spaceName   = t.spaceName
        self.title       = t.title
        self.dueDate     = t.dueDate
        self.status      = TaskRow.encode(status: t.status)
        self.done        = t.done
        self.scheduledAt = t.scheduledAt
    }

    func toDomain() -> TaskItem {
        TaskItem(id: id,
                 title: title,
                 dueLabel: TaskItem.dueLabel(for: dueDate),
                 status: TaskRow.decode(status: status),
                 done: done,
                 scheduledAt: scheduledAt,
                 dueDate: dueDate,
                 spaceName: spaceName)
    }
```

- [ ] **Step 4: Run it; verify PASS. Then run the full mapping suite to confirm no regression.**

Run: `xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/AtlasDBMappingTests`
Expected: PASS (all TaskRow/EventRow/etc. tests green).

- [ ] **Step 5: Commit.**

```bash
git add Atlas/Services/AtlasDB.swift AtlasTests/AtlasDBMappingTests.swift
git commit -m "feat(db): persist TaskItem.dueDate through TaskRow round-trip"
```

---

### Task 3: AppState.addTask carries dueDate + durationMin

**Files:**
- Modify: `Atlas/Data/AppState.swift:178-185`
- Test: `AtlasTests/AppStateCaptureTests.swift`

**Interfaces:**
- Consumes: `TaskItem.dueDate`/`durationMin`/`dueLabel(for:)` (Task 1).
- Produces: `@discardableResult func addTask(title: String, dueDate: Date? = nil, durationMin: Int? = nil) -> TaskItem`. Existing `addTask(title:)` callers keep working via defaults.

- [ ] **Step 1: Write the failing test** — create `AtlasTests/AppStateCaptureTests.swift`:

```swift
import XCTest
@testable import Atlas

@MainActor
final class AppStateCaptureTests: XCTestCase {
    func testAddTaskWithDueDateSetsDateAndLabel() {
        let state = AppState()
        let due = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let before = state.tasks.count
        let t = state.addTask(title: "Finish pset", dueDate: due, durationMin: 45)
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertEqual(t.dueDate, due)
        XCTAssertEqual(t.durationMin, 45)
        XCTAssertEqual(t.dueLabel, TaskItem.dueLabel(for: due))
        XCTAssertEqual(state.tasks.last?.dueDate, due)
    }

    func testAddTaskTitleOnlyStillWorks() {
        let state = AppState()
        let t = state.addTask(title: "Loose task")
        XCTAssertNil(t.dueDate)
        XCTAssertEqual(t.dueLabel, "")
    }
}
```

- [ ] **Step 2: Run it; verify it fails** — `addTask` has no `dueDate:` parameter yet.

Run: `xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/AppStateCaptureTests`
Expected: build failure — "extra argument 'dueDate' in call".

- [ ] **Step 3: Extend addTask** — in `Atlas/Data/AppState.swift`, replace `addTask` (lines 178-185):

```swift
    /// Quick-capture entry point. Appends a task with an optional structured due date.
    @discardableResult
    func addTask(title: String, dueDate: Date? = nil, durationMin: Int? = nil) -> TaskItem {
        let task = TaskItem(title: title,
                            dueLabel: TaskItem.dueLabel(for: dueDate),
                            dueDate: dueDate,
                            durationMin: durationMin)
        tasks.append(task)
        Task { try? await self.db?.upsertTask(task) }
        return task
    }
```

- [ ] **Step 4: Run it; verify PASS.**

Run: same command as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add Atlas/Data/AppState.swift AtlasTests/AppStateCaptureTests.swift
git commit -m "feat(state): addTask carries optional dueDate + durationMin"
```

---

### Task 4: Shared CaptureDateParser + wire dueISO into tasks

**Files:**
- Create: `Atlas/Services/CaptureDateParser.swift`
- Modify: `Atlas/Views/Capture/CaptureOverlay.swift:231-233` (task branch) and `:251-260` (handleEvent, switch to the shared parser)
- Test: `AtlasTests/CaptureDateParserTests.swift`

**Interfaces:**
- Consumes: `AppState.addTask(title:dueDate:durationMin:)` (Task 3), `CaptureResult.dueISO`/`startISO`/`durationMin` (existing in `AtlasAI.swift`).
- Produces: `enum CaptureDateParser { static func date(from iso: String?) -> Date? }`.

- [ ] **Step 1: Write the failing test** — create `AtlasTests/CaptureDateParserTests.swift`:

```swift
import XCTest
@testable import Atlas

final class CaptureDateParserTests: XCTestCase {
    func testNilReturnsNil() { XCTAssertNil(CaptureDateParser.date(from: nil)) }
    func testWholeSecondsParses() {
        XCTAssertNotNil(CaptureDateParser.date(from: "2026-06-27T20:00:00Z"))
    }
    func testFractionalSecondsParses() {
        XCTAssertNotNil(CaptureDateParser.date(from: "2026-06-27T20:00:00.000Z"))
    }
    func testGarbageReturnsNil() { XCTAssertNil(CaptureDateParser.date(from: "not a date")) }
}
```

- [ ] **Step 2: Run it; verify it fails to compile** — `CaptureDateParser` doesn't exist.

Run: `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/CaptureDateParserTests`
Expected: build failure — "cannot find 'CaptureDateParser' in scope".

- [ ] **Step 3: Create the parser** — `Atlas/Services/CaptureDateParser.swift`:

```swift
import Foundation

/// Parses ISO-8601 date strings returned by the `capture` edge function,
/// tolerating both fractional and whole-second formats. Shared by task and
/// event capture so the two paths never drift.
enum CaptureDateParser {
    static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}
```

- [ ] **Step 4: Run the parser test; verify PASS.**

Run: same command as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Wire dueISO into the task branch** — in `Atlas/Views/Capture/CaptureOverlay.swift`, replace the `case "task":` block (lines 231-233):

```swift
                case "task":
                    let due = CaptureDateParser.date(from: result.dueISO)
                    state.addTask(title: result.title,
                                  dueDate: due,
                                  durationMin: result.durationMin)
                    await showConfirmation(CaptureOutcome.task(hasDate: due != nil).confirmation)
```

(`CaptureOutcome` lands in Task 5; if implementing strictly in order, temporarily use `await showConfirmation(due != nil ? "✓ Added task · due set" : "✓ Added task")` and switch to `CaptureOutcome` in Task 5.)

- [ ] **Step 6: DRY the event path onto the shared parser** — in `handleEvent`, replace lines 252-260 with:

```swift
        let eventStart = CaptureDateParser.date(from: result.startISO)
        guard let eventStart else {
            // Can't place this on the calendar without a time — save as task.
            state.addTask(title: rawText)
            await showConfirmation(CaptureOutcome.degraded.confirmation)
            return
        }
```

(Same note: until Task 5, use the literal `"✓ Saved as task"` string; delete the now-unused `formatter`/`start` locals.)

- [ ] **Step 7: Build the app target to confirm it compiles.**

Run: `xcodebuild build -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit.**

```bash
git add Atlas/Services/CaptureDateParser.swift Atlas/Views/Capture/CaptureOverlay.swift AtlasTests/CaptureDateParserTests.swift
git commit -m "feat(capture): parse dueISO into tasks via shared CaptureDateParser"
```

---

### Task 5: Surface AI failures (CaptureOutcome) instead of silent fallback

**Files:**
- Create: `Atlas/Views/Capture/CaptureOutcome.swift`
- Modify: `Atlas/Views/Capture/CaptureOverlay.swift` — offline guard (line 212-213), note branch (224-230), default branch (234-237), catch (239-244) to use `CaptureOutcome`.
- Test: `AtlasTests/CaptureOutcomeTests.swift`

**Interfaces:**
- Produces: `enum CaptureOutcome { case task(hasDate: Bool), event, note, degraded; var confirmation: String }`.
- Consumes: used by `CaptureOverlay` (Task 4 already references `.task`/`.degraded`).

- [ ] **Step 1: Write the failing test** — create `AtlasTests/CaptureOutcomeTests.swift`:

```swift
import XCTest
@testable import Atlas

final class CaptureOutcomeTests: XCTestCase {
    func testDegradedIsDistinctFromPlainTask() {
        XCTAssertNotEqual(CaptureOutcome.degraded.confirmation,
                          CaptureOutcome.task(hasDate: false).confirmation)
    }
    func testTaskWithDateMentionsDue() {
        XCTAssertTrue(CaptureOutcome.task(hasDate: true).confirmation.lowercased().contains("due"))
    }
    func testDegradedMentionsOffline() {
        XCTAssertTrue(CaptureOutcome.degraded.confirmation.lowercased().contains("offline"))
    }
    func testEventAndNoteHaveCopy() {
        XCTAssertFalse(CaptureOutcome.event.confirmation.isEmpty)
        XCTAssertFalse(CaptureOutcome.note.confirmation.isEmpty)
    }
}
```

- [ ] **Step 2: Run it; verify it fails to compile** — `CaptureOutcome` doesn't exist.

Run: `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build -only-testing:AtlasTests/CaptureOutcomeTests`
Expected: build failure — "cannot find 'CaptureOutcome' in scope".

- [ ] **Step 3: Create the enum** — `Atlas/Views/Capture/CaptureOutcome.swift`:

```swift
import Foundation

/// User-facing result of a quick-capture, with its confirmation string.
/// Centralizes copy and makes the "AI unavailable → saved as plain task"
/// degraded path explicit, so a down backend is never silently identical
/// to a healthy task save.
enum CaptureOutcome: Equatable {
    case task(hasDate: Bool)
    case event
    case note
    case degraded   // AI unreachable / unparseable → saved as a plain task

    var confirmation: String {
        switch self {
        case .task(let hasDate): return hasDate ? "✓ Added task · due set" : "✓ Added task"
        case .event:             return "✓ Added event"
        case .note:              return "✓ Added note"
        case .degraded:          return "⚠︎ AI offline — saved as plain task"
        }
    }
}
```

- [ ] **Step 4: Run the enum test; verify PASS.**

Run: same command as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Route every capture path through CaptureOutcome** — in `Atlas/Views/Capture/CaptureOverlay.swift`:
  - Offline guard (line 213): `await showConfirmation(CaptureOutcome.degraded.confirmation)`
  - Note branch (line 230): `await showConfirmation(CaptureOutcome.note.confirmation)`
  - Event branch inside `handleEvent` success (line 282): `await showConfirmation(CaptureOutcome.event.confirmation)`
  - Default/unrecognized branch (line 237): `await showConfirmation(CaptureOutcome.degraded.confirmation)`
  - Catch (line 243): `await showConfirmation(CaptureOutcome.degraded.confirmation)`
  - Confirm the Task 4 task branch already uses `CaptureOutcome.task(hasDate:)`.

- [ ] **Step 6: Run the full test suite + build.**

Run: `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
Expected: BUILD SUCCEEDED, all tests pass (including pre-existing 45).

- [ ] **Step 7: Commit.**

```bash
git add Atlas/Views/Capture/CaptureOutcome.swift Atlas/Views/Capture/CaptureOverlay.swift AtlasTests/CaptureOutcomeTests.swift
git commit -m "feat(capture): surface AI-offline degraded state via CaptureOutcome"
```

---

### Task 6: Deploy the capture edge function (manual — user-run)

**Files:** none (deploys existing `supabase/functions/capture/index.ts`).

This step needs interactive Supabase auth, so the **user runs it** (suggest typing each with the `!` prefix in-session so output is captured). The OpenRouter key must NOT be pasted into the repo.

- [ ] **Step 1: Confirm the function is currently down.**

Run: `curl -s -o /dev/null -w "%{http_code}\n" -X POST "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/capture" -H "Content-Type: application/json" -d '{"text":"ping"}'`
Expected: `404` (not deployed — the problem).

- [ ] **Step 2: Log in + link the project (user, interactive).**

```bash
supabase login
supabase link --project-ref jxrmozhgsebwtbdleyxp
```

- [ ] **Step 3: Set the OpenRouter secret (user — paste real key, never commit).**

```bash
supabase secrets set OPENROUTER_API_KEY=<your-openrouter-key>
```

- [ ] **Step 4: Deploy.**

```bash
supabase functions deploy capture
```

- [ ] **Step 5: Verify it's live.**

Run: `curl -s -o /dev/null -w "%{http_code}\n" -X POST "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/capture" -H "Content-Type: application/json" -d '{"text":"ping"}'`
Expected: `401` (now reachable — it rejects the missing Bearer token instead of 404). With a valid Supabase Bearer token it returns `200` and JSON.

- [ ] **Step 6: End-to-end check in the app.** Launch the built app, sign in, press ⌘⇧K, type `essay due friday 8pm`. Expected: it becomes a **task with a due label** (not raw text), and the confirmation is "✓ Added task · due set". If the backend is down you now see "⚠︎ AI offline" instead of a silent plain-task save.

---

## Self-Review

**Spec coverage (Foundation slice of `2026-06-27-atlas-daily-driver-v2-design.md` §3):**
- TaskItem structured dates → Task 1 ✅
- Persist dueDate (DB) → Task 2 ✅ (column already existed)
- Wire AI `dueISO` into tasks (stop discarding) → Task 4 ✅
- Surface failures instead of silent fallback → Task 5 ✅
- Deploy `capture` → Task 6 ✅
- `addTask` plumbing for date/duration → Task 3 ✅

**Out of scope here (later workstream plans):** auto-find-time & revert-after-slot (WS-3), multi-item array + space-context prompt (WS-2), manual date picker UI (WS-3). Foundation deliberately stays to model + pipeline so parallel workstreams can rebase on a stable core.

**Placeholder scan:** none — every code step shows full code; the only literal-vs-enum note (Tasks 4↔5 ordering) is explicit.

**Type consistency:** `dueDate: Date?`, `durationMin: Int?`, `dueLabel(for:now:)`, `addTask(title:dueDate:durationMin:)`, `CaptureDateParser.date(from:)`, `CaptureOutcome.task(hasDate:)/.degraded/.confirmation` are used identically across tasks.
