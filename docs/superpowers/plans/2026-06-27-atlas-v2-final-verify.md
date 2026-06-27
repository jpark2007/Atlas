# Atlas v2 — Final Verification Pass

**Date:** 2026-06-27
**Workstream:** Final verify (Phase 3)

## Goal
Confirm the whole Atlas v2 tree (Foundation + WS-2..WS-10) builds and the full
XCTest suite passes green. Do NOT add features.

## Steps
1. `xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`.
2. Capture the exact final `Executed N tests, with M failures` line and whether
   `** TEST SUCCEEDED **` / `** TEST FAILED **` is printed.
3. If red:
   - Triage compile errors vs. test failures.
   - Fix the MINIMAL thing to get green.
   - If a single workstream left the tree broken, revert that workstream's last
     breaking commit and note it.
4. `git log --oneline 87c3d69..HEAD` — enumerate every commit added by the
   workstreams since Foundation.

## Done when
- `xcodebuild test` prints `** TEST SUCCEEDED **`.
- Report carries the exact executed line + the full commit list.
