# 06 — Notes & Linking

## Notes

- Free-form notes and checklists/lists.
- **Attachable to anything:** a project, a class, an event, a task — or standalone within a space.
- Example: attach a note to a class; attach a checklist to an event.
- Events and tasks also carry rich **descriptions** (lighter-weight than a full note).

## Linking / referencing (simplified Obsidian)

The unifying idea: **every item is a node, and nodes reference each other like tags.**

- Reference any item from any other with a lightweight `[[mention]]` / tag — **not** a heavy graph engine.
- Each node shows its **backlinks**: "what references this." Open a class → see all notes/tasks/events that reference it.
- Think "tagging items to each other," kept simple.

## Storage options for note bodies

- **Default:** notes stored in Atlas (Postgres) so linking/backlinks work natively.
- **External notes:** ability to link out to **Google Docs** or **Apple Notes** as a note's content/source.
- **iPad / Apple Notes sync:** marked **explore-later** — uncertain, low priority. Revisit after core notes work.

## Why this matters

This is what makes Atlas feel like a connected life manager instead of separate lists: a task can point to the note that explains it, which points to the class it's for, which shows every related event.

## Open questions

- Exact `[[ ]]` UX (autocomplete picker of items).
- How external (Google Docs / Apple Notes) note bodies render inside Atlas vs. just deep-link out.
