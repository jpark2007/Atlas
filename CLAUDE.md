# Atlas — Working Agreement

> ## ⚠️ PENDING DEPLOY — tell the user before they test capture (as of 2026-09-02)
>
> Repeating events + six sync fixes merged to `main` in PR #5 (`f371b84`), but **two
> deploy steps have NOT been run**:
>
> 1. **The `capture` edge function is not deployed.** The live function still serves the
>    OLD prompt, so a repeating capture ("yoga every Tuesday until Dec 12") against the
>    live backend gives the OLD behavior — the code in the repo is not what answered the
>    request. Deploy with `supabase functions deploy capture`, but **only after** a build
>    containing this code has shipped: the new prompt returns one item with a
>    `recurrence` field instead of enumerated sessions, so older installed builds would
>    create a single event where they used to create several.
> 2. **Migration `0046_event_recurrence.sql` is not applied** (`supabase db push`).
>    Safe to run any time — additive, nullable, no backfill. Until it is, a repeating
>    capture won't persist its `series_id`/`recurrence_rule`, so scope editing breaks
>    after a reload.
>
> Full context, including what still needs a visual pass and what was deliberately left
> open: `docs/handoff-2026-09-02-recurrence-and-sync.md`.
>
> **Delete this block once both steps are done.**

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

## Debug builds are a separate app — keep them out of Spotlight
- Debug builds are named **"Atlas Dev.app"** with a DEV-ribbon icon (`AppIcon-Dev`, regenerate with `swift scripts/make-dev-icon.swift`). Same bundle id, entitlements and data as Release — only the name and icon differ, so you can always tell which app you're looking at.
- Always build with `-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData.noindex/<name>"`. Spotlight skips `.noindex` paths, so build products never pile up in search results.
- Never copy a Debug build into `/Applications` — that is the installed release's slot.

## Releasing a Mac update (Sparkle flow)
Direct-download DMG is the primary channel; updates ship via **Sparkle** — never tell users to redownload manually.
1. Verify first: full gates green (Mac + iOS builds, AtlasCore `swift test`) AND Drew's visual pass on anything UI. Nothing ships untested.
2. Bump `MARKETING_VERSION` in project.yml → `scripts/release-dmg.sh` (archives, signs, notarizes, Sparkle-signs, updates `landing/appcast.xml`).
3. Copy the versioned DMG into `landing/downloads/`, deploy landing (`vercel --prod` in landing/). Existing users auto-update via the appcast; the site serves new downloads.
Sparkle private key lives in Drew's login keychain (never in the repo); public key in project.yml.

## Disk hygiene — agent worktrees
- Each worktree in `.claude/worktrees/` gets its own `AtlasCore/.build`. SwiftPM does NOT share build artifacts between worktrees, so N worktrees = N × ~770 MB of duplicated Swift build output.
- `.build/` and `.claude/worktrees/` are gitignored, so this NEVER shows up in `git status`. It is invisible until the disk is full. (Aug 2026: 30 worktrees = 19 GB.)
- When finishing work in a worktree, clean its build output:
  `rm -rf .claude/worktrees/*/AtlasCore/.build`
  Safe anytime no build is running — it only forces a recompile. Branches and uncommitted work are untouched.
- Prefer reusing an existing worktree over creating a new one. Remove worktrees whose branch is merged:
  `git worktree remove .claude/worktrees/<name>`
