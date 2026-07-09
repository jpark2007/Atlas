# Google Integration v2 — Planning

> ⚠️ **OPEN DECISION — read this first, then ask the user.**
> The Drive **scope & storage model** for Notes↔Drive is **unresolved** (pending partner review,
> 2026-06-29). Do **not** build or re-plan the Notes↔Drive layer until it's settled — the choice
> changes the architecture. Full findings (live test results, audit costs, the partner's Workspace
> model, options) are in **[notes-drive-architecture-decision.md](./notes-drive-architecture-decision.md)**.
> **Next session: surface that doc and ask which path — A `drive.file` / B `drive.readonly` /
> C per-org Workspace — before proceeding.** Current leaning: `drive.file`-first.

A fresh planning surface for the next phase of Atlas's Google integration:
**Notes ↔ Google Drive** and **Gmail capture**. Concept-first — this is where the
plan gets shaped, not a record of past work.

> Calendar write-back is handled separately ([calendar-writeback-plan.md](./calendar-writeback-plan.md)) and is done.

---

## Foundation (settled — so we don't re-litigate)

- **Interactive Google work runs in the app** (client-side OAuth, tokens in Keychain).
- **Background work runs on trigger.dev** (already used elsewhere; free at this scale) —
  needed only for things that must happen while the app is closed (i.e. Gmail).
- **Drive scope = `drive.file`.** Non-sensitive: no security audit, publishable, no
  weekly re-login. The trade: Atlas works with files **it** creates or that you
  **explicitly pick** — it doesn't auto-read your entire pre-existing Drive.
- **Per-feature consent.** Connecting Google asks only for what a feature needs, when
  you turn that feature on (toggles under one "Google" section in Settings).

---

## Concept 1 — Notes ↔ Google Drive

**The idea:** your notes live in Drive as real Google Docs, organized by class/project,
editable from either side.

- Each **project/class → a Drive folder** Atlas creates and manages
  (e.g. `Atlas / School / CS101 /`). Nesting works fully (Atlas owns the tree).
- Each **note → a Google Doc** inside that folder.
- **Two-way editing:** write in Atlas *or* in Google Docs (e.g. during class) — both
  stay in sync. Interchange is **Markdown** (Drive supports markdown import/export);
  newest edit wins.
- **Search your notes** from inside Atlas — fast and local, because Atlas keeps each
  note's text in its own index (no broad Drive permission needed).
- **Adopt an existing Doc:** pick it via the Google Picker (file-by-file, multi-select
  for a batch) → it becomes editable + synced.

**Reliable in v1:** headings, bold/italic, links, lists, code, quotes.
**Skip in v1:** images (links only), tables, comments/suggestions, deep nesting.

## Concept 2 — Gmail capture

**The idea:** Atlas turns actionable emails into tasks you confirm.

- Connect Gmail (its own toggle). A **scheduled trigger.dev job** scans *new, relevant*
  mail (filtered — not the whole inbox), batches it to the AI, and the AI drafts
  candidate **tasks tagged "from email."**
- **Nothing is created silently** — suggestions surface in Atlas for you to confirm.
- Runs while the app is closed, so the Google refresh token is stored **server-side**
  (Supabase, encrypted) for the job to use. This is the one piece that needs a token
  beyond the Mac Keychain.

---

## To plan (open questions)

**Notes**
- Sync trigger: on note open/save (interactive) vs a background poll — start with which?
- Conflict UX when both sides changed (last-write-wins + a "synced ✓ / conflict" badge?).
- Where the Atlas "root" folder lives (let the user pick a parent once?).

**Gmail**
- "Relevant" = labels you choose vs the AI scoring everything?
- Scan frequency vs cost.
- Privacy posture for AI reading mail content.
- Narrowest Gmail scope that works (stay out of restricted-scope territory if possible).
- Token storage + refresh design for the trigger.dev job.

**Sequencing**
- Notes (client-side, no server) is the natural next build; Gmail (needs trigger.dev +
  server token) follows once Notes proves the pattern.
