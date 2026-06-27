# Atlas v2 — follow-up refinements (apply AFTER the all-workstreams workflow)

Captured 2026-06-27 from live user feedback while the workflow ran. These layer on top of the workstreams; don't lose them.

## 1. Add a SPACE (top-level bucket), not just projects
WS-8 builds "add a Project under a Space." The user also wants to add a whole new **Space** (e.g. a new top-level bucket beyond School/Personal/Side Project). Add:
- Sidebar affordance to create a new Space (name + color).
- `AppState.addSpace(name:color:)` + persistence via `SpaceRow`/`upsertSpace`.
- New spaces immediately selectable as AI routing buckets.

## 2. Empty states = editable template data, never blank
User: "I don't want a bucket if it's empty — it should just have template data I can go in and edit."
- A new/empty **Project** detail page should NOT render blank. Seed it with an **editable starter template**: a placeholder overview ("What is this project about?") plus a few template sections/sample tasks (e.g. "Syllabus / key dates / resources" for a class) that the user can edit or delete.
- Same principle for other blank surfaces (dashboard task groups, notes): show an editable starter, not emptiness.
- Distinguish "seeded MockData that's blank" from real onboarding — replace blank seeds with editable templates.

## 3. Richer AI routing context (promised to user)
When finalizing the `capture` edge function + `AtlasAI.parse` client context, include each project's **overview/description** (not just name + code) so the AI routes ambiguous captures confidently. The more a project is described (via #2's editable templates), the better routing gets. Ties WS-8 → WS-2.

## Status
- `capture` edge function: DEPLOYED + `OPENROUTER_API_KEY` secret set (verified HTTP 401 live 2026-06-27). Will need ONE re-paste of the final multi-item version after the workflow's WS-2 rewrite.
