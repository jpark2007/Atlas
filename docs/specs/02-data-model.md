# 02 — Data Model: Spaces, Projects, Items

## Hierarchy

```
Space (School / Personal / Business …)
  ├── private or shared
  └── Project  (in School → = Class)
        ├── solo or group/shared
        ├── linked Google Drive folder
        └── Tasks · Events · Notes
```

## Entities

### Space
- Top-level bucket / "scene." Has name, color/icon, owner, and members (if shared).
- App ships with **School** + **Personal** templates; user can add more (Business, etc.).
- Visibility: **private** (just owner) or **shared** (multiple members).

### Project
- Lives inside exactly one space. Bundles tasks, events, notes, and an optional **Google Drive folder**.
- In the **School** space, projects represent **Classes** and are auto-created from Canvas (see [05](./05-canvas.md)).
- Visibility: solo or **group/shared** (shared tasks, scheduling, meetings).

### Task
- **Must belong to a space.** *May* belong to a project, or sit loose in the space.
- Fields: title, **description**, due date, scheduled time (when dragged onto calendar), status, space, optional project, tags/links.
- Source tag: where it came from (manual, AI capture, Canvas, email).

### Event
- A timed entry on the calendar. Sources: Apple, Google, Canvas (class meetings, assignment deadlines), or Atlas-created.
- Fields: title, description, start/end, space, optional project, source, tags/links.
- A **Class** is a project that also owns a recurring meeting event (e.g. "CS 101, MWF 10am").

### Note / List
- Free-form note or checklist. Attachable to a project, event, task, or standalone (within a space).
- Detail in [06](./06-notes-and-linking.md).

## Linking / referencing (simplified Obsidian)

- Every item (note, task, event, project, class) is a **node**.
- Items reference each other **like tagging** — a lightweight `[[mention]]`/tag, not a heavy graph engine.
- Each node shows **backlinks**: "what references this." (e.g. open a class → see every note/task/event linked to it.)
- Detail in [06](./06-notes-and-linking.md).

## Rules summary

- A task without a space is **invalid**.
- A task without a project is **fine**.
- An item can belong to only one space, at most one project.
- Links/tags are many-to-many and cross every item type.

## Sketch schema (Postgres, to refine)

```
spaces(id, owner_id, name, color, is_shared, template_type)
space_members(space_id, user_id, role)
projects(id, space_id, name, kind[normal|class], drive_folder_id, is_shared)
project_members(project_id, user_id, role)
tasks(id, space_id, project_id?, title, description, due_at?, scheduled_at?, status, source)
events(id, space_id, project_id?, title, description, start_at, end_at, source, external_id?)
notes(id, space_id, project_id?, title, body, attached_to_type?, attached_to_id?)
links(id, from_type, from_id, to_type, to_id)   -- the tag/reference graph
```
