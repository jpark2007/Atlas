# Mobile Polish v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Mobile Polish v2 spec (`docs/superpowers/specs/2026-07-02-mobile-polish-v2-design.md`): client freshness, truthful event sources, timezone-correct capture times, space-color system, motion/haptics vocabulary, capture hero redesign (Direction A), jump-to-today.

**Architecture:** Shared logic changes land in the `AtlasCore` Swift package (unit-tested via `swift test`). iOS UI changes land in the `AtlasMobile` target (verified by simulator build; feel/visuals confirmed by Drew on device). The AI prompt fix lands in the Supabase Edge Function `supabase/functions/capture/index.ts` (verified by deploy + curl).

**Tech Stack:** SwiftUI (iOS 17+), XcodeGen project, Swift Package (AtlasCore, XCTest), Deno Edge Function (no local deno — integration-verified).

## Global Constraints

- Working dir: `/Users/drewkhalil/Documents/atlas life manager` (note the spaces — always quote paths).
- iOS build: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO`
- Mac build (AtlasCore is shared — must stay green): `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- AtlasCore tests: `cd AtlasCore && swift test`
- After CREATING any new file under `AtlasMobile/`, run `xcodegen generate` before building (the .xcodeproj is generated from project.yml).
- Design rules (MobileTheme.swift header): accent = live/NOW/brand only, never a button fill; controls are transparent with 1.5 pt ink outlines; SF Pro Rounded everywhere. Match this in all new UI.
- UI feel (springs, haptics, pull-to-refresh) is NOT provable by a green build — final claim is "applied, builds, needs Drew's check."
- Commit after every task with the exact message given.

---

### Task 1: EventRow derives source from googleEventId (AtlasCore)

**Files:**
- Test: Create `AtlasCore/Tests/AtlasCoreTests/EventRowSourceTests.swift`
- Modify: `AtlasCore/Sources/AtlasCore/AtlasDB.swift:313-328` (`EventRow.toDomain()`)

**Interfaces:**
- Consumes: `EventRow(domain:)`, `CalendarEvent` memberwise init (has `source: EventSource = .atlas`, `googleEventId: String? = nil` defaults), `EventSource` enum (`.atlas`/`.apple`/`.google`, auto-Equatable).
- Produces: `EventRow.toDomain().source` is `.google` iff `googleEventId != nil`. Task 2's `googleConnected` check depends on this.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import AtlasCore

/// Spec §2: source is derived at ingest — a row carrying a googleEventId came
/// from Google; everything else is Atlas-native. Never a hardcoded label.
final class EventRowSourceTests: XCTestCase {

    private func event(googleEventId: String?) -> CalendarEvent {
        CalendarEvent(title: "Standup", subtitle: "",
                      start: Date(), end: Date().addingTimeInterval(3600),
                      color: .red, spaceName: "Work",
                      googleEventId: googleEventId)
    }

    func test_toDomain_withGoogleEventId_derivesGoogleSource() {
        let row = EventRow(domain: event(googleEventId: "abc123"))
        XCTAssertEqual(row.toDomain().source, .google)
    }

    func test_toDomain_withoutGoogleEventId_staysAtlas() {
        let row = EventRow(domain: event(googleEventId: nil))
        XCTAssertEqual(row.toDomain().source, .atlas)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "AtlasCore" && swift test --filter EventRowSourceTests`
Expected: `test_toDomain_withGoogleEventId_derivesGoogleSource` FAILS (source is `.atlas`); the other passes.

- [ ] **Step 3: Implement the derivation**

In `AtlasDB.swift`, `EventRow.toDomain()`, insert one argument (init order: …`noteID`, `isReadOnly`, `source`, `googleEventId`…):

```swift
    public func toDomain() -> CalendarEvent {
        // CalendarEvent has `var id: UUID = UUID()` — memberwise init exposes `id`
        // as an overridable parameter, so the DB UUID IS preserved here.
        CalendarEvent(id: id,
                      title: title,
                      subtitle: subtitle,
                      start: startAt,
                      end: endAt,
                      color: AtlasTheme.Colors.accent, // Task 2 re-derives from spaceName
                      spaceName: spaceName,
                      notes: notes,
                      isAllDay: isAllDay,
                      projectID: projectId,
                      noteID: noteId,
                      // A row carrying a Google id came from Google — derive, never default.
                      source: googleEventId != nil ? .google : .atlas,
                      googleEventId: googleEventId)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "AtlasCore" && swift test --filter EventRowSourceTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Verify the Mac app still builds (shared code)**

Run: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`. (The Mac re-stamps sources during its own Google sync; this only corrects labels on Supabase loads.)

- [ ] **Step 6: Commit**

```bash
git add AtlasCore/Tests/AtlasCoreTests/EventRowSourceTests.swift AtlasCore/Sources/AtlasCore/AtlasDB.swift
git commit -m "fix(core): derive event source from googleEventId on Supabase load"
```

---

### Task 2: Settings connections row tells the truth (AtlasMobile)

**Files:**
- Modify: `AtlasMobile/Views/Settings/SettingsView.swift:153-159` (`connectionsSection`)

**Interfaces:**
- Consumes: `googleConnected` (`SettingsView.swift:195`, `store.snapshot.events.contains { $0.source == .google }`) — meaningful only after Task 1.
- Produces: copy change only; nothing downstream.

- [ ] **Step 1: Replace the Connected/Not-connected binary with honest copy**

```swift
    private var connectionsSection: some View {
        Section {
            // Derived from the snapshot — Google events appear only once the Mac
            // has synced them into Supabase. The phone never connects to Google
            // itself, so the honest states are syncing / not syncing.
            labeledRow("Google Calendar", value: googleConnected ? "Syncs via your Mac" : "Not syncing")
        } header: { header("Connections") }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AtlasMobile/Views/Settings/SettingsView.swift
git commit -m "fix(mobile): Settings Google row says syncs-via-Mac, not a fake connected state"
```

---

### Task 3: dueLabel shows the clock time when one exists (AtlasCore)

**Files:**
- Test: Create `AtlasCore/Tests/AtlasCoreTests/DueLabelTests.swift`
- Modify: `AtlasCore/Sources/AtlasCore/Models.swift:200-212` (`TaskItem.dueLabel(for:now:)`)

**Interfaces:**
- Consumes: existing `dueLabel(for: Date?, now: Date = Date()) -> String`.
- Produces: same signature; local-midnight dates render unchanged ("Today"), any other time appends a clock: `"Today 5:30 PM"`, on-the-hour drops minutes: `"Today 5 PM"`. All call sites (TasksView row, CaptureResultCard due chip, ManualAddSheet, widgets) pick this up automatically.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AtlasCore

/// Spec §3: stated times are sacred — the label shows them. Local midnight means
/// date-only, so no time is shown. (Literals assume an en-US 12-hour device
/// locale, matching the existing formatter usage in dueLabel.)
final class DueLabelTests: XCTestCase {

    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! }

    func test_todayWithTime_showsClock() {
        let due = cal.date(bySettingHour: 17, minute: 30, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today 5:30 PM")
    }

    func test_todayOnTheHour_dropsMinutes() {
        let due = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today 5 PM")
    }

    func test_localMidnight_isDateOnly() {
        let due = cal.startOfDay(for: now)
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Today")
    }

    func test_tomorrowWithTime_showsClock() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let due = cal.date(bySettingHour: 9, minute: 15, second: 0, of: tomorrow)!
        XCTAssertEqual(TaskItem.dueLabel(for: due, now: now), "Tomorrow 9:15 AM")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "AtlasCore" && swift test --filter DueLabelTests`
Expected: `test_todayWithTime_showsClock`, `test_todayOnTheHour_dropsMinutes`, `test_tomorrowWithTime_showsClock` FAIL (no time appended); `test_localMidnight_isDateOnly` passes.

- [ ] **Step 3: Implement**

Replace `dueLabel(for:now:)` in `Models.swift`:

```swift
    /// Short, human due label derived from a date. Deterministic given `now`.
    /// "" for nil; "Today"/"Tomorrow"; weekday ("Thu") within a week; else "MMM d".
    /// A non-midnight time is appended ("Today 5:30 PM") — local midnight means
    /// the deadline is date-only, so no time is shown.
    public static func dueLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        let day: String
        if cal.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
                cal.isDate(date, inSameDayAs: tomorrow) { day = "Tomorrow" }
        else {
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: date)).day ?? 0
            let f = DateFormatter()
            f.dateFormat = (days > 1 && days < 7) ? "EEE" : "MMM d"
            day = f.string(from: date)
        }
        let c = cal.dateComponents([.hour, .minute], from: date)
        guard c.hour != 0 || c.minute != 0 else { return day }
        let t = DateFormatter()
        t.dateFormat = c.minute == 0 ? "h a" : "h:mm a"
        return "\(day) \(t.string(from: date))"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "AtlasCore" && swift test`
Expected: all tests PASS (including pre-existing NotificationPlannerTests).

- [ ] **Step 5: Commit**

```bash
git add AtlasCore/Tests/AtlasCoreTests/DueLabelTests.swift AtlasCore/Sources/AtlasCore/Models.swift
git commit -m "feat(core): dueLabel shows the clock time when a deadline has one"
```

---

### Task 4: Date-only capture dates parse as LOCAL days (AtlasCore)

**Files:**
- Test: Create `AtlasCore/Tests/AtlasCoreTests/CaptureDateParserTests.swift`
- Modify: `AtlasCore/Sources/AtlasCore/CaptureDateParser.swift`

**Interfaces:**
- Consumes: `CaptureDateParser.date(from: String?) -> Date?`.
- Produces: same signature; `"2026-06-30"` now parses as local midnight June 30 (today it parses as midnight UTC = the previous evening in US timezones).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AtlasCore

/// Spec §3: a date-only string from the model means the user's LOCAL calendar
/// day — parsing it as UTC midnight shifts "due Friday" to Thursday evening
/// in US timezones.
final class CaptureDateParserTests: XCTestCase {

    func test_dateOnly_parsesAsLocalMidnight() {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 30
        XCTAssertEqual(CaptureDateParser.date(from: "2026-06-30"),
                       Calendar.current.date(from: c))
    }

    func test_fullISO_stillParses() {
        XCTAssertEqual(CaptureDateParser.date(from: "2026-06-30T17:30:00Z"),
                       Date(timeIntervalSince1970: 1_782_840_600))
    }
}
```

- [ ] **Step 2: Run tests to verify the date-only one fails**

Run: `cd "AtlasCore" && swift test --filter CaptureDateParserTests`
Expected: `test_dateOnly_parsesAsLocalMidnight` FAILS unless the machine is in UTC; `test_fullISO_stillParses` passes.

- [ ] **Step 3: Implement**

In `CaptureDateParser.swift`, change the date-only fallback:

```swift
        // Model sometimes returns date-only: "2026-06-30" — the user's LOCAL day.
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f.date(from: iso)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "AtlasCore" && swift test --filter CaptureDateParserTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AtlasCore/Tests/AtlasCoreTests/CaptureDateParserTests.swift AtlasCore/Sources/AtlasCore/CaptureDateParser.swift
git commit -m "fix(core): date-only capture dates parse in the user's local timezone"
```

---

### Task 5: Capture request carries the user's timezone (AtlasCore)

**Files:**
- Test: Create `AtlasCore/Tests/AtlasCoreTests/CaptureRequestTests.swift`
- Modify: `AtlasCore/Sources/AtlasCore/AtlasAI.swift` (`CaptureRequest`, `requestBody`, `parse`)

**Interfaces:**
- Consumes: `CaptureRequest`, `AtlasAI.requestBody(text:spaces:)`, `AtlasAI.parse(_:spaces:)`.
- Produces: `requestBody(text:spaces:timezone: String? = nil)` — nil omits the key (old deploys unaffected). `parse` sends `TimeZone.current.identifier`. Task 6's edge function reads `body.timezone`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AtlasCore

/// Spec §3: the phone sends its IANA timezone so the model can resolve "5:30"
/// and "next Friday" in the user's local time. Optional → old clients/deploys
/// keep working (synthesized Codable omits nil).
final class CaptureRequestTests: XCTestCase {

    func test_requestBody_includesTimezone() throws {
        let data = try AtlasAI.requestBody(text: "x", spaces: [],
                                           timezone: "America/Los_Angeles")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["timezone"] as? String, "America/Los_Angeles")
    }

    func test_requestBody_omitsNilTimezone() throws {
        let data = try AtlasAI.requestBody(text: "x", spaces: [])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["timezone"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `cd "AtlasCore" && swift test --filter CaptureRequestTests`
Expected: BUILD FAILURE — `extra argument 'timezone' in call`.

- [ ] **Step 3: Implement**

In `AtlasAI.swift` — extend the request struct:

```swift
/// Request body for the `capture` function. `spaces` is omitted entirely when
/// the caller has no context to share, keeping old/default routing intact.
/// `timezone` (IANA identifier) lets the model resolve times in the user's
/// local day; omitted when nil so old deploys keep working.
/// `Codable` (not just `Encodable`) so tests can round-trip the produced body.
public struct CaptureRequest: Codable {
    public let text: String
    public let spaces: [CaptureContextSpace]?
    public let timezone: String?
}
```

Extend `requestBody` (keep the default so existing callers/tests compile):

```swift
    /// Encode the POST body. `spaces` is dropped when empty and `timezone` when
    /// nil, so callers without context produce `{ "text": ... }` exactly as before.
    public static func requestBody(text: String,
                                   spaces: [CaptureContextSpace],
                                   timezone: String? = nil) throws -> Data {
        let payload = CaptureRequest(text: text,
                                     spaces: spaces.isEmpty ? nil : spaces,
                                     timezone: timezone)
        return try JSONEncoder().encode(payload)
    }
```

In `parse(_:spaces:)`, change the body line:

```swift
        request.httpBody = try AtlasAI.requestBody(text: text, spaces: spaces,
                                                   timezone: TimeZone.current.identifier)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "AtlasCore" && swift test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add AtlasCore/Tests/AtlasCoreTests/CaptureRequestTests.swift AtlasCore/Sources/AtlasCore/AtlasAI.swift
git commit -m "feat(core): capture request sends the user's IANA timezone"
```

---

### Task 6: Edge function — timezone-aware prompt, stated times are sacred

**Files:**
- Modify: `supabase/functions/capture/index.ts`

**Interfaces:**
- Consumes: `body.timezone` (optional string, from Task 5).
- Produces: prompt resolves relative dates in the user's local day; ISO outputs carry stated times. No response-shape change.

- [ ] **Step 1: Accept `timezone` from the body**

In the body-parsing block (after `spaces` is read), add:

```ts
  let timezone = "UTC";
  // (inside the try after spaces:)
    if (typeof body.timezone === "string" && body.timezone.trim()) {
      timezone = body.timezone.trim();
    }
```

- [ ] **Step 2: Render "now" in the user's local time**

Add above `buildSystemPrompt`:

```ts
/**
 * "Now" rendered in the user's timezone for the prompt, e.g.
 * "Thursday, July 2, 2026, 3:41 PM". Falls back to UTC on a bad identifier
 * (Intl throws RangeError) so a malformed client can't 500 the function.
 */
function localNow(timezone: string): { tz: string; text: string } {
  try {
    const text = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      weekday: "long", year: "numeric", month: "long", day: "numeric",
      hour: "numeric", minute: "2-digit", hour12: true,
    }).format(new Date());
    return { tz: timezone, text };
  } catch {
    return { tz: "UTC", text: new Date().toISOString() };
  }
}
```

- [ ] **Step 3: Rebuild the system prompt**

Change the signature to `buildSystemPrompt(spaces: ContextSpace[] | undefined, timezone: string)` and replace the date preamble, the two ISO schema lines, and add the time rules. The full updated function:

```ts
function buildSystemPrompt(spaces: ContextSpace[] | undefined, timezone: string): string {
  const now = localNow(timezone);
  return `You are Atlas, a personal life-management AI. \
The user's timezone is ${now.tz}. Right now, the user's LOCAL date and time is: ${now.text}. \
Resolve ALL dates and times ("tomorrow", "next Friday", "tonight", "at 5:30") in the \
user's LOCAL time first, then convert to UTC for output. \
Given a user's free-text capture, classify it and split it into one or more items. \
A single paragraph can contain MULTIPLE items (e.g. "essay due thursday, gym 3x this \
week, dinner with mom sunday" → three items). Return ONLY a JSON object of the form \
{ "items": [ ... ] } — no markdown, no explanation, just the raw JSON. \
Each element of "items" matches this schema:

{
  "kind": "task" | "event" | "note",
  "title": string,            // concise, actionable title
  "spaceName": string,        // see routing rules below
  "projectName"?: string,     // if the item belongs to a specific project/class
  "dueISO"?: string,          // Full ISO 8601 UTC instant converted from the user's local time,
                              // e.g. a 5:30 PM PDT deadline → "2026-07-03T00:30:00Z" (tasks)
  "startISO"?: string,        // Full ISO 8601 UTC instant, converted the same way (events)
  "durationMin"?: number,     // duration in minutes (events, default 60 if not specified)
  "notes"?: string            // extra detail / body text (notes, or longer event notes)
}

Routing:
${spacesBlock(spaces)}

Rules:
- Split distinct to-dos / events / notes into SEPARATE items. A single self-contained
  capture is a one-element array.
- "task"  = something to do (verb phrase, deadline, assignment, chore)
- "event" = a meeting, appointment, session, or time-bound activity
- "note"  = a thought, idea, reference, or piece of information to remember
- If an item is ambiguous, prefer "task".
- STATED TIMES ARE SACRED. If the user states a clock time ("at 5:30", "by noon",
  "8pm"), it MUST appear in dueISO (tasks) or startISO (events), converted from the
  user's LOCAL time to UTC. NEVER return a date-only/midnight value when a time was stated.
- A time-bound errand or commitment ("pick him up at 5:30", "call mom at 8") is an
  "event" starting at that local time — not a floating task with no deadline.
- A deadline WITHOUT a stated time ("due Friday") = that LOCAL day at 00:00 user-local,
  converted to UTC.
- Always populate kind, title, and spaceName. All other fields are optional.`;
}
```

And update the call site:

```ts
          { role: "system", content: buildSystemPrompt(spaces, timezone) },
```

- [ ] **Step 4: Deploy**

Run: `cd "/Users/drewkhalil/Documents/atlas life manager" && supabase functions deploy capture`
Expected: deploy succeeds. If the CLI isn't authenticated, STOP and ask Drew to run `supabase login` (or deploy himself) — do not skip verification.

- [ ] **Step 5: Integration-verify with curl**

Read the project URL + anon key from `AtlasCore/Sources/AtlasCore/SupabaseConfig.swift`, then:

```bash
curl -s -X POST "<functionsBase>/capture" \
  -H "Authorization: Bearer <anonKey>" -H "apikey: <anonKey>" \
  -H "Content-Type: application/json" \
  -d '{"text":"hard deadline at 5:30 today, and I need to pick Sam up at 7","timezone":"America/Los_Angeles"}'
```

Expected: two items — a task whose `dueISO` is today 17:30 America/Los_Angeles expressed in UTC (ends in `T00:30:00Z` or `T01:30:00Z` depending on DST), and an **event** with `startISO` at 19:00 local in UTC. Neither is midnight. Also send `{"text":"essay due next friday","timezone":"America/Los_Angeles"}` — expected `dueISO` = the correct local Friday at `07:00:00Z`/`08:00:00Z` (local midnight in UTC).

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/capture/index.ts
git commit -m "fix(capture-fn): timezone-aware prompt — stated times are sacred, local-day relative dates"
```

---

### Task 7: Client freshness — refresh on foreground + pull-to-refresh

**Files:**
- Modify: `AtlasMobile/AtlasMobileApp.swift:33-35` (scenePhase handler)
- Modify: `AtlasMobile/Views/Tasks/TasksView.swift` (empty state + list)
- Modify: `AtlasMobile/Views/Schedule/ScheduleView.swift:99-124` (list)

**Interfaces:**
- Consumes: `MobileStore.refresh()` (async; already guards `mutationsInFlight`, retries 401, keeps old snapshot on error). `onChange(of: store.loading)` already re-plans notifications + rewrites widgets after refresh — no extra wiring needed.
- Produces: nothing new downstream.

- [ ] **Step 1: Refresh on foreground**

In `AtlasMobileApp.swift`, replace the scenePhase handler:

```swift
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { Task { await store.refresh() } }
                            if phase == .active || phase == .background { reschedule() }
                        }
```

- [ ] **Step 2: Pull-to-refresh on Tasks**

In `TasksView.swift`, attach to the list (after `.scrollContentBackground(.hidden)`):

```swift
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refresh() }
```

And make the empty state pullable — replace the `Text("all clear")` branch in `body`:

```swift
            if groups.isEmpty {
                ScrollView {
                    Text("all clear")
                        .edCapsLabel()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
                .refreshable { await store.refresh() }
            } else {
                list
            }
```

- [ ] **Step 3: Pull-to-refresh on Schedule**

In `ScheduleView.swift`, attach to the `List` inside the `TimelineView` (after `.scrollContentBackground(.hidden)`, before `.simultaneousGesture`):

```swift
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.refresh() }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add AtlasMobile/AtlasMobileApp.swift AtlasMobile/Views/Tasks/TasksView.swift AtlasMobile/Views/Schedule/ScheduleView.swift
git commit -m "feat(mobile): pull-to-refresh + auto-refresh on foreground"
```

---

### Task 8: Motion & haptics vocabulary in MobileTheme

**Files:**
- Modify: `AtlasMobile/Theme/MobileTheme.swift`

**Interfaces:**
- Produces: `MobileTheme.spring` / `MobileTheme.heroSpring` (`Animation`), `MobileTheme.Haptic.tap()` / `.success()` / `.selection()`. Tasks 9–14 consume these; views never define their own curves or haptics.

- [ ] **Step 1: Add the vocabulary**

Add `import UIKit` under the existing imports, and inside `enum MobileTheme` (after the `rule` constant):

```swift
    // MARK: Motion — ONE vocabulary, used everywhere (spec §5)
    /// Standard spring — "satisfying but quiet". Every state change animates with this.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Hero spring — livelier. CAPTURE ONLY: the app's one expressive moment.
    static let heroSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)

    /// The haptic map: tap = check-off and light actions, success = capture commit,
    /// selection = toggles/filters. Views use these — never their own generators.
    enum Haptic {
        static func tap()       { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AtlasMobile/Theme/MobileTheme.swift
git commit -m "feat(mobile): motion + haptic vocabulary in MobileTheme"
```

---

### Task 9: Check-off flagship — CheckCircle + linger-then-leave

**Files:**
- Create: `AtlasMobile/Views/Components/CheckCircle.swift`
- Modify: `AtlasMobile/Views/Tasks/TasksView.swift` (row, openTasks, toggle)
- Modify: `AtlasMobile/Views/Schedule/DayTimelineView.swift:91-99` (checkCircle)

**Interfaces:**
- Consumes: `MobileTheme.spring`, `MobileTheme.Haptic.tap()` (Task 8).
- Produces: `CheckCircle(done: Bool, color: Color, action: () -> Void)` — the only check-off control; both task lists use it.

- [ ] **Step 1: Create the component**

`AtlasMobile/Views/Components/CheckCircle.swift`:

```swift
import SwiftUI

/// The flagship check-off control (spec §5): a space-tinted ring that springs
/// full with the space color and draws a checkmark when done. Fires the standard
/// tap haptic. Color = the task's space — informative, never decorative.
struct CheckCircle: View {
    let done: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            MobileTheme.Haptic.tap()
            withAnimation(MobileTheme.spring) { action() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(done ? color : color.opacity(0.5), lineWidth: MobileTheme.rule)
                Circle()
                    .fill(color)
                    .scaleEffect(done ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(done ? 1 : 0.001)
            }
            .frame(width: 20, height: 20)
            .animation(MobileTheme.spring, value: done)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Regenerate the project (new file)**

Run: `cd "/Users/drewkhalil/Documents/atlas life manager" && xcodegen generate`
Expected: `Created project at .../Atlas.xcodeproj`

- [ ] **Step 3: Adopt in TasksView with linger-then-leave**

Add state under `@State private var timing: TaskItem?`:

```swift
    /// Rows checked off in this session linger ~0.9 s (strikethrough + filled
    /// check) before sliding out, so completion is felt, not a blink.
    @State private var justCompleted: Set<UUID> = []
```

Replace `openTasks`:

```swift
    private var openTasks: [TaskItem] {
        store.snapshot.tasks.filter {
            (!$0.done || justCompleted.contains($0.id)) && inFilter($0.spaceName)
        }
    }
```

Replace `row(_:)`'s button and title (keep the due-label trailing part unchanged):

```swift
    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            CheckCircle(done: task.done, color: task.spaceColor) { toggle(task) }

            Text(task.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(task.done ? MobileTheme.faint : MobileTheme.ink)
                .strikethrough(task.done, color: MobileTheme.faint)

            Spacer(minLength: 8)

            let due = TaskItem.dueLabel(for: task.dueDate)
            if !due.isEmpty {
                Text(due)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }
```

Replace `toggle(_:)`:

```swift
    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        if updated.done {
            justCompleted.insert(task.id)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                _ = withAnimation(MobileTheme.spring) { justCompleted.remove(task.id) }
            }
        }
        Task { await store.updateTask(updated) }
    }
```

- [ ] **Step 4: Adopt in DayTimelineView**

Replace `checkCircle(_:)`:

```swift
    private func checkCircle(_ task: TaskItem) -> some View {
        CheckCircle(done: task.done, color: task.spaceColor) { onToggle(task) }
            .padding(.top, 1)
    }
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add AtlasMobile/Views/Components/CheckCircle.swift AtlasMobile/Views/Tasks/TasksView.swift AtlasMobile/Views/Schedule/DayTimelineView.swift
git commit -m "feat(mobile): check-off flagship — space-tinted CheckCircle, haptic, linger-then-leave"
```

---

### Task 10: Space-color edge on capture result rows

**Files:**
- Modify: `AtlasMobile/Views/Capture/CaptureResultCard.swift:107-125` (`row`)

**Interfaces:**
- Consumes: existing `color(for: String) -> Color` helper in the same file.
- Produces: visual only. (The due chip already gains times automatically via Task 3's `dueLabel`.)

- [ ] **Step 1: Add the leading space-color tab**

Replace `row(_:)`:

```swift
    private func row(_ draft: Binding<DraftItem>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Space-color edge (spec §4): routing is visible at a glance.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color(for: draft.wrappedValue.spaceName))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(draft.wrappedValue.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)

                HStack(spacing: 10) {
                    spaceMenu(draft)
                    dot
                    Text(draft.wrappedValue.kind)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(0.84).textCase(.uppercase)
                        .foregroundStyle(MobileTheme.muted)
                    dot
                    Button { editingDueID = draft.wrappedValue.id } label: { dueLabel(draft.wrappedValue) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AtlasMobile/Views/Capture/CaptureResultCard.swift
git commit -m "feat(mobile): space-color edge on capture result rows"
```

---

### Task 11: Capture empty state — the page IS the input

**Files:**
- Modify: `AtlasMobile/Views/Capture/CaptureView.swift` (`emptyState`, `dumpBox`, `micButton`, `orDivider`)

**Interfaces:**
- Consumes: `MobileTheme.spring` (Task 8), existing `sortItOut`, `startListening`, `pending`, `note`, `trimmedText`, `editorFocused`.
- Produces: `dumpBox` and `orDivider` are DELETED (orphaned by this change). `micButton` is restyled larger. Everything else keeps its name.

- [ ] **Step 1: Replace emptyState, delete dumpBox + orDivider, restyle micButton**

Replace `emptyState` (keep the `.toolbar { ... }` keyboard Done button exactly as-is at the end):

```swift
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Capture").edScreenTitle()
                .padding(.horizontal, 28)
                .padding(.top, 24)

            // The page IS the input (spec §6, Direction A) — no box, no chrome.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .tint(MobileTheme.accent)          // caret = brand accent, not a fill
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                if text.isEmpty {
                    Text("What’s on your mind?")
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .padding(.horizontal, 27)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 18) {
                if let note {
                    Text(note).edCapsLabel()
                } else if !pending.items.isEmpty {
                    Text("Saved offline · \(pending.items.count) waiting").edCapsLabel()
                }

                if trimmedText.isEmpty {
                    micButton
                } else {
                    Button { sortItOut(text) } label: {
                        Text("Sort it out")
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .frame(maxWidth: .infinity)
                            .edOutlineControl()
                    }
                    .buttonStyle(.plain)
                }

                Button { showManualAdd = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add a task manually")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 10)
            .animation(MobileTheme.spring, value: trimmedText.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
            }
        }
    }
```

DELETE the `dumpBox` and `orDivider` properties entirely (nothing else uses them), and replace `micButton` with the prominent version:

```swift
    /// The prominent voice entry — outlined, never a fill (mic 64 pt, thumb reach).
    private var micButton: some View {
        Button(action: startListening) {
            Image(systemName: "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(MobileTheme.ink)
                .frame(width: 64, height: 64)
                .overlay(Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AtlasMobile/Views/Capture/CaptureView.swift
git commit -m "feat(mobile): capture empty state — full-screen input, prominent mic"
```

---

### Task 12: Capture thinking state — the breathing orb

**Files:**
- Modify: `AtlasMobile/Views/Capture/CaptureView.swift` (`thinkingState`, `sortItOut`, replace `PulsingCore` with `HeroOrb`, phase transition animation)

**Interfaces:**
- Consumes: `MobileTheme.heroSpring`, `MobileTheme.accent`.
- Produces: `PulsingCore` is DELETED (replaced by `HeroOrb`, private to this file). New `@State thinkingText`/`dissolve` are private.

- [ ] **Step 1: Keep the dumped text for the dissolve**

Add state under `@State private var isDraining = false`:

```swift
    @State private var thinkingText = ""
    @State private var dissolve = false
```

In `sortItOut`, right before `phase = .thinking`, add:

```swift
        thinkingText = raw
        dissolve = false
```

- [ ] **Step 2: Animate the phase switch**

On the `ZStack` in `body`, after the `switch` block's closing brace, add:

```swift
        .animation(MobileTheme.heroSpring, value: phase)
```

- [ ] **Step 3: Replace thinkingState**

```swift
    // MARK: - Thinking state (spec §6: the hero moment — breathing orb, words dissolve)

    private var thinkingState: some View {
        VStack(spacing: 44) {
            Spacer()
            HeroOrb()
            Text(thinkingText)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 44)
                .blur(radius: dissolve ? 6 : 0)
                .opacity(dissolve ? 0.15 : 1)
                .offset(y: dissolve ? -28 : 0)
                .animation(.easeIn(duration: 1.6), value: dissolve)
            Text("Sorting it out…").edCapsLabel()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dissolve = true }
    }
```

- [ ] **Step 4: Replace PulsingCore with HeroOrb**

Delete the `PulsingCore` struct and add in its place:

```swift
/// The capture hero (spec §6): a breathing clay orb with expanding ripples — the
/// app's ONE expressive animation moment. Accent = live/brand, allowed here.
private struct HeroOrb: View {
    @State private var breathe = false
    @State private var ripple = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(MobileTheme.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .scaleEffect(ripple ? 2.6 : 1)
                    .opacity(ripple ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.9),
                        value: ripple)
            }
            Circle()
                .fill(MobileTheme.accent)
                .frame(width: 72, height: 72)
                .scaleEffect(breathe ? 1.12 : 0.88)
                .shadow(color: MobileTheme.accent.opacity(0.45), radius: breathe ? 34 : 14)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
        }
        .frame(height: 100)
        .onAppear { breathe = true; ripple = true }
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add AtlasMobile/Views/Capture/CaptureView.swift
git commit -m "feat(mobile): capture thinking state — breathing hero orb, dissolving words"
```

---

### Task 13: Capture results — staggered entrance, success haptic, summary

**Files:**
- Modify: `AtlasMobile/Views/Capture/CaptureResultCard.swift` (staggered rows)
- Modify: `AtlasMobile/Views/Capture/CaptureView.swift` (`commitAll`)

**Interfaces:**
- Consumes: `MobileTheme.heroSpring`, `MobileTheme.Haptic.success()` (Task 8), existing `note` display in `emptyState` (Task 11), `resolveSpace`.
- Produces: `commitSummary(_:) -> String` (private to CaptureView).

- [ ] **Step 1: Staggered row entrance in CaptureResultCard**

Add state under `@State private var editingDueID: UUID?`:

```swift
    @State private var appeared = false
```

In `body`, replace the `ForEach` inside the `List`:

```swift
                ForEach($drafts) { $draft in
                    let index = drafts.firstIndex { $0.id == draft.id } ?? 0
                    row($draft)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(MobileTheme.heroSpring.delay(Double(index) * 0.07),
                                   value: appeared)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { remove(draft.id) } label: {
                                Label("Remove", systemImage: "xmark")
                            }
                        }
                }
```

And on the outer `VStack` (after `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`), add:

```swift
        .onAppear { appeared = true }
```

- [ ] **Step 2: Success haptic + summary in CaptureView**

Replace `commitAll` and add the helper:

```swift
    private func commitAll() {
        MobileTheme.Haptic.success()
        note = commitSummary(drafts)
        for draft in drafts { commit(draft) }
        drafts = []
        phase = .empty
    }

    /// "Added 3 · 2 School, 1 Personal" — the calm confirmation shown back on
    /// the empty screen after a commit. Spaces resolved the same way commit() does.
    private func commitSummary(_ drafts: [DraftItem]) -> String {
        let bySpace = Dictionary(grouping: drafts) {
            resolveSpace($0.spaceName)?.name ?? $0.spaceName
        }
        let parts = bySpace
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count) \($0.key)" }
            .joined(separator: ", ")
        return "Added \(drafts.count) · \(parts)"
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add AtlasMobile/Views/Capture/CaptureResultCard.swift AtlasMobile/Views/Capture/CaptureView.swift
git commit -m "feat(mobile): staggered capture results, success haptic + commit summary"
```

---

### Task 14: Jump-to-today pill

**Files:**
- Modify: `AtlasMobile/Views/Schedule/ScheduleView.swift` (overlay on body)
- Modify: `AtlasMobile/Views/Schedule/MonthPageView.swift:54-59` (stepper)

**Interfaces:**
- Consumes: `MobileTheme.spring`, `MobileTheme.Haptic.selection()` (Task 8), existing `selectedDay`/`cal`.
- Produces: nothing downstream.

- [ ] **Step 1: Today pill on Schedule**

In `ScheduleView.swift` `body`, after `.background(MobileTheme.bg.ignoresSafeArea())`, add:

```swift
        .overlay(alignment: .bottom) {
            if !cal.isDateInToday(selectedDay) {
                Button {
                    MobileTheme.Haptic.selection()
                    withAnimation(MobileTheme.spring) {
                        selectedDay = cal.startOfDay(for: Date())
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(0.96).textCase(.uppercase)
                        .foregroundStyle(MobileTheme.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(MobileTheme.bg))
                        .overlay(Capsule().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(MobileTheme.spring, value: cal.isDateInToday(selectedDay))
```

- [ ] **Step 2: Today button on the month page**

In `MonthPageView.swift`, replace `stepper`:

```swift
    private var stepper: some View {
        HStack(spacing: 22) {
            Button { month = Date() } label: {
                Text("Today")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
            }
            .buttonStyle(.plain)
            Button { shift(-1) } label: { chevron("chevron.left") }
            Button { shift(1) } label: { chevron("chevron.right") }
        }
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add AtlasMobile/Views/Schedule/ScheduleView.swift AtlasMobile/Views/Schedule/MonthPageView.swift
git commit -m "feat(mobile): jump-to-today pill on schedule + month page"
```

---

### Task 15: Final verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Full AtlasCore test suite**

Run: `cd "AtlasCore" && swift test`
Expected: all tests PASS (NotificationPlanner + the 4 new test files).

- [ ] **Step 2: Both app builds**

Run:
```bash
xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED` twice.

- [ ] **Step 3: Simulator smoke pass**

Boot the iPhone 17 Pro simulator, install and launch AtlasMobile. Walk: check a task off (linger + slide-out), pull-to-refresh on Tasks and Schedule, type a capture → orb → staggered results → commit summary, day-swipe away from today → Today pill appears and snaps back, Settings shows the new Google copy. Screenshot each for Drew.

- [ ] **Step 4: Report honestly**

Feel (haptics, spring character) and TestFlight behavior are device-territory: the final report says "applied, builds green, sim-verified flows, needs Drew's device pass." List the capture curl results from Task 6 explicitly.
