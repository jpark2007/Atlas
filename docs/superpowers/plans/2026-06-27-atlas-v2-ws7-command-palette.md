# WS-7 — Command Palette Create-on-the-Fly

**Spec:** §4 WS-7. File: `Atlas/Views/Search/CommandPalette.swift` (⌘K).

## Goal
- ⌘K keeps searching projects/tasks/notes, but a persistent leading row
  **Create "<query>" as task** appears for any non-empty query (even when there
  ARE matches, and especially when there are none). It runs
  `state.addTask(title: query)` and dismisses.
- Empty query still shows quick-actions only.
- Disambiguate ⌘K (find/create) vs ⌘⇧K (braindump) in UI copy.

## Approach
1. **New pure model** `Atlas/Views/Search/CommandPaletteModel.swift`:
   - `PaletteSection { title; items: [CommandResult]; id = title }`.
   - `enum CommandPaletteModel`:
     - `createActionID = "create-task"` (stable id for the Create row).
     - `matchingProjects/Tasks/Notes(query:…)` — substring filters (empty query → []).
     - `results(query:projects:tasks:notes:quickActions:createAction:) -> [PaletteSection]`:
       - empty query → single "Quick actions" section.
       - non-empty → leading "Create" section (the injected createAction),
         then non-empty Projects / Tasks / Notes sections.
   - Pure (no SwiftUI/AppState) so it's unit-testable; the view injects the
     query-bound `createAction` and the `quickActions`.
2. **Refactor `CommandPaletteOverlay`** to drive its list from
   `CommandPaletteModel.results(...)`:
   - add `createAction` (id `createActionID`, title `Create "<q>" as task`,
     run: `state.addTask(title: q)`; `activate()` already dismisses actions).
   - `sections` / `flat` / `sectionSlices` derived from the model; remove the
     now-duplicated `projects`/`tasks`/`notes`/`trimmedQuery` computed vars.
   - render sections with running base offsets for keyboard-selection indexing.
3. **UI copy:** search-field placeholder → find-or-create; add a footer row
   showing `⌘K find or create` · `⌘⇧K braindump`.
4. **Tests** `AtlasTests/CommandPaletteTests.swift`:
   - empty query → exactly one "Quick actions" section, no create row.
   - non-empty query (no matches) → leading item is the create action (id check).
   - non-empty query WITH a matching task → create row still leads; task present.
   - `matchingTasks` finds tasks by title substring (tasks are searchable).

## Verify
`xcodegen generate && xcodebuild test -scheme Atlas -destination 'platform=macOS' -derivedDataPath build`
(single: `-only-testing:AtlasTests/CommandPaletteTests`). Leave the tree green.
