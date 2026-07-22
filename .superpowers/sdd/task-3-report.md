# Task 3 — Mac `.help()` hover sweep — Report

**Status:** COMPLETE
**Commit:** `9c70734` — feat(help): .help() hover tooltips across Mac icon-only buttons
**Build:** `xcodebuild … build CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**
**Files changed:** 14 · **New `.help()` button call sites:** 16

## Method
Ran the brief's grep across `Atlas/Views` (98 `Image(systemName:)` hits), then read each host file to classify every hit as: genuine icon-only `Button` (add help), decorative `Image` (skip), button-with-visible-text-label (skip), already-has-`.help` (leave), or `Menu`/hidden control (skip). Two commits since the plan had reshaped SidebarView/CalendarView/NoteEditorView/CaptureOverlay, so I anchored on button behavior, not line numbers.

Verified `CalendarView.shift(by:)`: it steps by **day** in day mode, **week** in week/list mode, **month** in month mode — the nav chevrons are view-relative, so the brief's "Previous week"/"Next week" would be inaccurate. Used mode-agnostic copy.

## Inventory — `.help()` added

| File | Button | Copy |
|---|---|---|
| SidebarView.swift | space expand/collapse chevron | `Expand or collapse` |
| CalendarView.swift | clear search (xmark.circle.fill) | `Clear the search` |
| CalendarView.swift | nav chevron.left (shift −1) | `Previous day, week, or month` |
| CalendarView.swift | nav chevron.right (shift +1) | `Next day, week, or month` |
| CalendarEventDetailView.swift | clear linked note (xmark.circle.fill) | `Clear the linked note` |
| NoteEditorView.swift | style-bar mark button | `Bold` / `Italic` / `Underline` (via `markHelp(mark)`) |
| NoteEditorView.swift | style-bar list button | `Bulleted list` / `Numbered list` |
| TimeGridView.swift | DeadlineRailMarker (flag.fill) | `See what's due` |
| GraphView.swift | close graph (xmark) | `Close the graph` |
| ProjectDetailView.swift | live-task checkbox | `Mark done` / `Mark not done` (dynamic on `task.done`) |
| TaskDetailView.swift | header checkbox | `Mark done` / `Mark not done` (dynamic on `live.done`) |
| TaskDetailView.swift | description edit (pencil) | `Edit description` |
| TaskDetailView.swift | unlink note (xmark.circle.fill) | `Clear the linked note` |
| DashboardView.swift | focus-list checkbox | `Mark done` / `Mark not done` (dynamic) |
| SpaceDetailView.swift | task-row checkbox | `Mark done` / `Mark not done` (dynamic) |
| CompletedView.swift | reopen checkbox (always done) | `Mark not done` |
| MiniMonthAgenda.swift | month prev chevron.left | `Previous month` |
| MiniMonthAgenda.swift | month next chevron.right | `Next month` |
| AttachReferencePicker.swift | ReferenceListRow remove (xmark.circle.fill) | `Remove this reference` |
| AtlasColorPicker.swift | apply hex (arrow.right.circle.fill) | `Apply this hex color` |

The two style-bar buttons and two MiniMonth chevrons collapse to 16 distinct `.help()` call sites (the mark/list buttons each carry per-glyph copy).

## Already had `.help` — left as-is (per brief)
CaptureOverlay mic (`Stop dictation` / `Click to talk`); NoteEditorView & ReferenceRowView syncNow (`Sync now — …`); UnscheduledTray checkbox (`Mark done`); ProjectDetailView add-project, starter-task trash, overview pencil, color dot, Import/Add-link, Add Task, Invite people; SpaceDetailView color dot / Invite people; FocusView reset + corner buttons; GraphView re-run layout; SettingsView graph / reset-shortcut / read-only glyph; NoteCardOverlay expand/close/resize.

## Not buttons — correctly skipped
- **CaptureOverlay `sparkles`** — the brief listed it, but the recent commit changed it: it is now a decorative status glyph that swaps with a ProgressView spinner, NOT a `Button`. Skipped.
- SettingsView `eye.fill` (plain Image, already `.help`), all row/badge glyphs.
- Sidebar search / settings / report-bug / space buttons now carry visible text labels → excluded.
- CommandPalette hidden ⌘K host button (opacity 0, accessibilityHidden).
- All decorative `Image(systemName:)` in banners, headers, list rows, event tiles, deadline pills.

## Deliberately skipped — icon-only `Menu`s (outside the `Button` definition), flagged for judgment
The brief scoped the task to `Image(systemName:)` inside a `Button`. These are icon-only `Menu`s, so they were left alone:
- ReferenceRowView ellipsis (`…`) row menu
- TaskDetailView note-picker chevron.down menu (secondary re-tag)

If a follow-up wants tooltips on these, `Menu` accepts `.help()` too (e.g. "More actions" / "Change the linked note").

## Skipped for unclear purpose
None — every genuine icon-only Button's purpose was resolvable from code.

## Verification
Build is green. Per CLAUDE.md, hover tooltips are UI a green build can't prove — Drew should hover each icon ~1s to confirm the copy shows and reads as one clean line. Pre-existing uncommitted files (project.yml, supabase functions, PrivacyInfo, landing/) were not staged or touched.
