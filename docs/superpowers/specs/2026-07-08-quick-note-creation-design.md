# Quick Note Creation — Design

## Goal
Let the user create a new note faster: a keyboard shortcut while in the Notes view, and a visible quick-create affordance on the Dashboard.

## Changes

### 1. ⌘N shortcut in Notes view
`Atlas/Views/Notes/NotesListView.swift` — add `.keyboardShortcut("n", modifiers: .command)` to the existing "New" button (line 22). It already calls `newNote()`, which opens an unsaved draft `Note(title: "", body: "")`. No behavior change beyond adding the shortcut trigger.

### 2. "New note" affordance on Dashboard
`Atlas/Views/Dashboard/DashboardView.swift` — add a plain-text button near the "RECENT NOTES" header (around line 249), styled like the existing `addTaskAffordance` (small "+" icon, muted text, no border/box, `.buttonStyle(.plain)`). Tapping it sets `editingNote = Note(title: "", body: "")`, which is the same `@State` binding the dashboard already uses to open notes in the `NoteCardOverlay` corner card. No new state or navigation plumbing.

## Out of scope
- No global (app-wide) keyboard shortcut/overlay outside the Notes view.
- No changes to the `Note` data model.
- No changes to `NoteEditorView` or `NoteCardOverlay` internals.

## Testing
- Build via `xcodebuild` per project convention.
- Manually verify in-app: ⌘N while Notes view is focused opens a new draft note; Dashboard "New note" button opens the corner-card editor.
