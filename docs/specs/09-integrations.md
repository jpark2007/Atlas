# 09 — Integrations & Extras

## Google Drive (in projects)

- A project can have a linked **Google Drive folder**.
- Create folders right inside a project; attach files.
- Drive access via backend OAuth (secrets server-side).

## Media URLs (Spotify / podcasts) — simplified

- **No deep Spotify integration.** Instead, **paste a URL** (Spotify playlist, podcast, song, any link) onto a task / event / project.
- Same paste-a-link pattern works for any external resource.

## Pomodoro / Focus pill

- A focus-session timer shown as a compact floating **pill**, tied to a task or class.
- **Ported from the old Atlas prototype** (see below), then restyled cleaner ("liquid glass").

## Global pill hotkey

- A system-wide hotkey (macOS) that summons a floating **command pill** for quick capture/actions.
- **Ported from the old Atlas prototype**, then restyled.

## Carryover from the old prototype

Two features are being lifted from the previous Atlas Swift project at
`~/Documents/Personal project/Atlas` and then that project is deleted:

1. **Global pill hotkey** — system-wide shortcut → floating pill.
2. **Focus-mode pill timer** — compact floating Pomodoro/focus timer.

Harvested code is staged in [`../carryover/`](../carryover/) until integrated. Both get a visual refresh to match Atlas's "liquid glass" direction. macOS-specific bits (floating panels, global hotkeys) won't carry to iOS as-is and will need iOS equivalents.

## Notes storage integrations

- Link notes out to **Google Docs** / **Apple Notes** (see [06](./06-notes-and-linking.md)).

## Open questions

- Drive folder permissions for shared projects.
- iOS equivalent for the global pill hotkey (no system-wide hotkeys on iOS — likely a widget/share-sheet/Shortcuts entry instead).
