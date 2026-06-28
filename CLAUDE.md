# Atlas — Working Agreement

Atlas is a native **macOS SwiftUI** app (deployment target **macOS 14**, XcodeGen project `Atlas.xcodeproj`). This file captures how to work in it well. **User instructions always override anything here.** These guidelines bias toward caution over speed; for trivial tasks, use judgment.

## 1. Think before coding
- Research the actual code (and the reference prototype in `Dark Mac Calendar App Prototype/`) before proposing a fix. Don't throw code at a problem before understanding the root cause.
- State assumptions explicitly. If uncertain, ask. Don't hide confusion.
- If multiple interpretations exist, present them — don't silently pick one.
- If a simpler approach exists, say so. Push back when warranted.
- For non-trivial problems, divide and analyze with sub-agents first; converge on a solution, then implement.

## 2. Simplicity first
- Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked; no abstractions for single-use code; no config/flexibility nobody requested; no error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it. "Would a senior engineer call this overcomplicated?" If yes, simplify.

## 3. Surgical changes
- Touch only what the task requires. Match existing style even if you'd do it differently.
- Remove only the imports/vars/functions YOUR change orphaned. Mention pre-existing dead code; don't delete it unasked.
- Every changed line should trace directly to the request.

## 4. Goal-driven execution & verification
- Turn tasks into verifiable goals ("fix the bug" → "reproduce it, then make it pass"). Loop until verified.
- Build before claiming done:
  `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- **UI/behavior (drag, drop, window chrome) is NOT provable by a green build.** The user must confirm it visually. Never say a UI fix "works" before they confirm — say "applied, builds, needs your check."
- SourceKit "Cannot find AppState/AtlasTheme/CalendarLayout" diagnostics are single-file isolation noise. The real `xcodebuild` is the source of truth.

## 5. Data correctness — never mislabel a source
An event's **source** (Apple / Google / Canvas / Atlas-native) and its **read-only vs writable** status must reflect where it ACTUALLY came from. Never hardcode a source label or read-only flag. A Google event must never display "read-only from Apple Calendar." Attribution is set at ingest, per source — get it right there.

## macOS gotchas learned here (don't relearn the hard way)
- `.toolbar(.hidden, for: .windowToolbar)` strips the traffic-light buttons. For an edge-to-edge transparent title bar that KEEPS them, use `.windowStyle(.hiddenTitleBar)` (macOS 11+).
- Native `.draggable`/`.dropDestination` forces a green "+" copy badge and is unreliable inside scrolling grids. The calendar drag-to-schedule uses a custom `DragGesture` + coordinate math instead (mirrors the working prototype).
- Stale `build/` DerivedData can cause phantom entitlement errors — `rm -rf build` if that appears.
