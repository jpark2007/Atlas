# Multi-tab Google Docs write-back — options memo

**Date:** 2026-07-06 · **Status:** research only, nothing implemented · **Repo:** `/Users/drewkhalil/Documents/atlas life manager`

## Executive summary

Atlas's Doc-note sync is entirely **tab-blind**: pull exports Markdown, write-back re-uploads
Markdown, and Markdown has no tab concept. On a multi-tab Doc the write-back (`files.update` with
`mimeType: application/vnd.google-apps.document` + Markdown media) asks Drive to *reconvert the whole
file from Markdown* — which mangles the existing tab tree (Drew saw a top-level tab demoted to a
sub-tab). The good news: the app **already holds the `https://www.googleapis.com/auth/documents`
scope** (`Atlas/Services/GoogleAuthService.swift:26`), so the Google Docs API — which *does* expose
tabs and *can* target/create/delete them — is usable server-side with **no new scope and no
re-consent**. Recommendation: **detect tabs via the Docs API, and for tabbed Docs stop using the
Drive Markdown re-upload; write each tab through Docs API `batchUpdate` (option C), with option A —
detect-and-block — as the safe fallback / phase-1 ship.**

One premise in the brief needs empirical confirmation before building C (see
[§Open question: does export even return all tabs?](#open-question-does-export-actually-return-all-tabs)).

---

## 1. What happens today (code trace)

### Pull (Google → Atlas)
`supabase/functions/google-sync/index.ts`

- `driveExportMarkdown()` (`google-sync/index.ts:369-376`) does a **Drive** export:
  `GET /drive/v3/files/{id}/export?mimeType=text/markdown` (line 371). No `includeTabsContent`,
  no tab awareness — this is the Drive export endpoint, which has no tab parameter at all.
- `syncUserReferences()` doc-note branch (`google-sync/index.ts:443-467`): if Drive's
  `modifiedTime` is newer than the stored baseline, it overwrites `notes.body` with the exported
  Markdown wholesale and re-baselines `modified_time`.
- **Nothing in the pull path inspects, counts, or records tabs.** A grep for `tab`, `childTab`,
  `includeTabsContent` across `supabase/functions/` returns only unrelated hits ("close this tab",
  RFC-5545 TAB unfolding). The DB stores one flat Markdown blob per note.

### Write-back (Atlas → Google)
`supabase/functions/drive-writeback/index.ts`

- Staleness guard (`drive-writeback/index.ts:182-201`): `files.get?fields=modifiedTime` vs. the
  client/stored baseline; refuses on divergence unless `overwrite:true`. (Correct and unaffected by
  tabs — it only compares timestamps.)
- The actual write (`drive-writeback/index.ts:203-233`): a **multipart `PATCH`** to
  `…/upload/drive/v3/files/{id}?uploadType=multipart`, metadata part pinning
  `mimeType: application/vnd.google-apps.document` (constant at line 48), media part carrying the
  raw Markdown as `text/markdown`. The header comment (lines 204-208) states the contract plainly:
  *"this REWRITES the Doc from Markdown."*
- Client wrapper: `Atlas/Services/GoogleDocWriteBackClient.swift:19-69` just POSTs the note's
  Markdown to this edge function; `NoteEditorView` invokes it on save. No tab logic client-side
  either.

### What a round-trip does to a 2-tab Doc (mechanical reconstruction)
`files.update` with a Google-Doc target mimeType + Markdown media tells Drive to **convert the
Markdown into a Doc and replace the file's contents**. Markdown carries no tab structure, so the
conversion has no defined way to reproduce the two tabs. Google does **not document** any
Markdown↔tabs mapping (see §2), so what happens next is emergent/undefined — and matches Drew's
report: the re-import over an already-tabbed file restructures the tab tree (a top-level tab became
a sub-tab). **Bottom line: the current write-back is performing an undefined, structure-destroying
operation on any multi-tab Doc.** The only *defined* way to write a specific tab is the Docs API
(§2). Docs revision history is the sole safety net today.

### Not currently wired, but already in the tree
`Atlas/Services/GoogleDocsService.swift` is a **complete but orphaned Docs-API path**
(`documents.get` decode → `RichDoc`, `documents.batchUpdate` write; lines 58-70, 196-220, 408-417).
Its only external references are code comments — it is **not** on the live write-back path (that's
the Drive-Markdown edge function). Two caveats if reused as-is: (a) `decodeDocument` reads only
`doc.body.content` (lines 40, 64-70) — it never looks at `tabs[]`, so on a multi-tab Doc it too
would see only tab 1; (b) it maps to Atlas's RichDoc subset, not Markdown. Useful as a *starting
point* for option C, not a drop-in.

### Scopes the server token carries (decisive)
`Atlas/Services/GoogleAuthService.swift:24-27` — the desktop OAuth (whose refresh token the edge
functions reuse) requests **all three**:
```
calendar.events · documents · drive.file
```
`documents` is the **full read/write Docs API scope**. So `documents.get` (tab detection) and
`documents.batchUpdate` (per-tab writes, add/delete tabs) are already authorized server-side.
**No scope change, no re-consent needed** for any Docs-API option below. (`drive.file` is the
per-file Drive grant used for import/export; the broad `documents` scope is not per-file-limited,
so Docs-API access to a linked Doc does not depend on the Drive-Picker client-mismatch caveat noted
in `Atlas/Views/References/ReferencePreview.swift:11-17`.)

---

## 2. Google API capabilities (current, verified on the live web)

### Docs API — reading tabs
- `documents.get?includeTabsContent=true` populates `document.tabs[]`; the legacy content fields
  (`document.body`, …) are then empty. When `includeTabsContent` is **false/unspecified (the
  default), only the *first tab's* content populates `document.body` and `tabs` stays empty** —
  quote: *"The content of the document's first tab populates the content fields in Document
  excluding Document.tabs. If a document has only one tab, then that tab is used to populate the
  document content."*
  → [documents.get reference](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get),
  [Work with tabs](https://developers.google.com/workspace/docs/api/how-tos/tabs)
- Tab shape: `Tab { tabProperties{ tabId, title, index }, childTabs[], documentTab{ body, … } }`.
  Nested tabs are a tree traversed via `childTabs` (e.g.
  `document.tabs[2].childTabs[0].childTabs[1].documentTab.body`).
  → [Work with tabs](https://developers.google.com/workspace/docs/api/how-tos/tabs),
  [Structure of a document](https://developers.google.com/workspace/docs/api/concepts/structure)

### Docs API — writing to a specific tab, and managing tabs
- Every `Location` / `Range` / `EndOfSegmentLocation` accepts a **`tabId`**; omitting it targets the
  first tab. `ReplaceAllText` accepts **`tabsCriteria { tabIds[] }`** to scope replacement to chosen
  tabs. So a "replace tab N's content" = `deleteContentRange` + `insertText`, both with that tab's
  `tabId`.
  → [Work with tabs](https://developers.google.com/workspace/docs/api/how-tos/tabs),
  [batchUpdate reference](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate)
- **Tabs can be created and deleted via the API** (confirmed against three sources incl. the Go
  client library): `AddDocumentTabRequest` (*"Adds a document tab. When a tab is added at a given
  index, all subsequent tabs' indexes are incremented"*), `DeleteTabRequest` (*"Deletes a tab. If
  the tab has child tabs, they are deleted as well"*), and `UpdateDocumentTabPropertiesRequest`
  (title/index). No explicit "reorder" request — ordering is via the add index.
  → [batchUpdate reference](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate),
  [google.golang.org/api/docs/v1](https://pkg.go.dev/google.golang.org/api/docs/v1)
  (Note: the "Work with tabs" *how-to* guide omits these request types; the *REST reference* and Go
  library list them. Recommend a quick live `batchUpdate` smoke test before relying on
  `AddDocumentTab`, since tab-management requests are newer than the read side.)

### Drive Markdown import/export ↔ tabs (the undocumented gap)
- Markdown import/export shipped for Docs in **July 2024**
  ([Workspace blog](https://workspaceupdates.googleblog.com/2024/07/import-and-export-markdown-in-google-docs.html),
  [support](https://support.google.com/docs/answer/12014036)). The docs cover headings↔`#`, lists,
  bold/italic — and are **completely silent on tabs**. There is **no documented mapping between
  Markdown `#` headings and Docs tabs/sub-tabs** in either direction.
- Multiple current sources report that **native/Drive Markdown export handles only the *current /
  first* tab**, not all tabs; `includeTabsContent` is a **Docs-API** parameter and is **not**
  available on Drive `files.export`. Per-tab export is only possible via an *undocumented*
  `…/export?format=…&tab={tabId}` URL.
  → [files.export reference](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/export),
  [Exporting individual tabs (Google Workspace DEV)](https://dev.to/googleworkspace/exporting-individual-tabs-from-google-docs-as-pdfs-2903)

**Conclusion:** Markdown is the wrong transport for tab structure in *both* directions. The Docs API
is the only supported way to read or write specific tabs. Any "make Markdown round-trip tabs
correctly" option (brief's 4d) is a dead end — Google exposes no such mapping.

---

## Open question: does export actually return all tabs?

The brief states pull "exports ALL tabs, each tab title as an `# H1`… Verified working." The web
evidence above says Drive Markdown export returns **only the first/current tab**. These conflict. It
matters a lot:

- **If export returns only tab 1:** pull is *also* lossy (tabs 2+ never reach Atlas), and the
  current whole-file write-back is doubly destructive. This pushes hard toward **A (block)** or a
  Docs-API-based pull+write, because Atlas simply doesn't have the other tabs' content to preserve.
- **If export really returns all tabs as `# H1` blocks:** the brief's premise holds and option C
  (split note by `#` → write per tab) is directly buildable.

What Drew observed in-app ("# Tab N" sections) could be genuine multi-tab export **or** ordinary H1
headings inside tab 1 being read as "tabs." **Verify empirically before building C** (one line:
`curl` the export of a known 2-tab Doc via the server token, or `documents.get?includeTabsContent=true`
and compare). This is the single highest-value next step.

---

## 3. Detection options (how Atlas learns a Doc is multi-tab)

| Approach | How | Cost | Reliability |
|---|---|---|---|
| **Docs API `documents.get?includeTabsContent=true&fields=tabs.tabProperties,tabs.childTabs`** | Count `tabs[]` (+ recurse `childTabs`); >1 (or any child) ⇒ multi-tab | 1 extra Docs call per changed Doc; scope already granted | **Authoritative.** Also yields `tabId`+`title` needed for per-tab writes |
| Heuristic on exported Markdown (count `# ` H1s) | Cheap, no extra call | ~0 | **Unreliable** — can't tell a real tab from an ordinary H1; fails exactly on the docs that matter |

**Use the Docs API for detection.** It's one call on an already-authorized scope, it's exact, and
the same response supplies the `tabId`s and per-tab `endIndex`es you need to write. The Markdown
heuristic should not gate anything destructive.

---

## 4. Options for safe write-back on tabbed Docs

| # | Option | Effort | Risk | UX | Notes |
|---|---|---|---|---|---|
| **A** | **Detect tabs → mark note read-only / block write-back with a clear warning** | **Low** (½–1 day) | **Very low** | Honest but limited: edits to tabbed Docs don't push back | Baseline safety. Detection = 1 Docs call in `drive-writeback` before the upload; on `tabs.length>1` return e.g. `409 {error:"multitab_unsupported"}`, surface a banner. **Stops the data loss immediately.** |
| **B** | **Write-back scoped to the FIRST tab only, via Docs API `batchUpdate`** | **Medium** (2–4 days) | **Medium** | Tab 1 stays two-way; other tabs read-only | Replace tab-1 content (`deleteContentRange`+`insertText` with `tabId`), never touch tabs 2+. Needs Markdown→Docs-request conversion for tab 1 only. Silently ignores edits the user makes in the app to tab-2 content — must be paired with detection so the note reflects only tab 1, or UX gets confusing. |
| **C** | **Full fidelity: split note by `#` H1 → write each tab via Docs API `batchUpdate`** | **High** (1–2 wks) | **Med-High** | True two-way on tabbed Docs | Requires: reliable tab-aware **pull** (Docs API `includeTabsContent`, not Drive export) so the note is stored *with* tab boundaries; Markdown⇄Docs-requests conversion per tab; add/delete tabs when the user adds/removes an H1 section (`AddDocumentTabRequest`/`DeleteTabRequest`). Order/nesting mapping (H1=tab, H2=sub-tab?) is a product decision — Google defines none. |
| **D** | Markdown that round-trips tabs | — | — | — | **Not possible.** Google documents no Markdown↔tabs mapping and Drive export drops tabs (§2). Rejected. |

---

## 5. Recommendation

**Ship A now; build toward C. Skip B and D.**

**Phase 1 (recommended immediate fix) — Option A, detect-and-block.**
Stops the structure-destroying write-back today, cheaply, on an already-granted scope.

- In `drive-writeback/index.ts`, **before** the multipart upload (after the staleness guard,
  ~line 202), call
  `GET https://docs.googleapis.com/v1/documents/{fileId}?includeTabsContent=true&fields=tabs.tabProperties.tabId,tabs.childTabs`
  with the same `accessToken`.
- If `tabs.length > 1` (or any `childTabs`), **do not upload**; return
  `409 {error:"multitab_unsupported", tabCount}`.
- Map that in `GoogleDocWriteBackClient.swift` (alongside the existing `stale` case at line 65) to a
  new outcome, and show a non-destructive banner in `NoteEditorView`: *"This Doc has multiple tabs —
  Atlas can't safely write it back yet. Edit in Google Docs."* Keep the local Markdown copy.
- Optional: persist a `multi_tab` flag on `project_references` at pull time so the editor can show
  read-only state before the user even tries to save.
- **Verify** the export-vs-tabs question (§Open question) as part of this phase — it determines
  whether pull is also lossy and whether C is worth building.

**Phase 2 (if two-way tabbed editing is wanted) — Option C, Docs-API per-tab.**

- **Pull:** replace the Drive Markdown export for multi-tab Docs with
  `documents.get?includeTabsContent=true`; store the note with explicit tab boundaries (e.g. the
  existing `# <tab title>` convention **plus** a persisted `tabId`→section map on the reference, so
  writes target the right `tabId` rather than guessing by position/title).
- **Write-back:** for each tab, `documents.batchUpdate` with `deleteContentRange` +
  `insertText`/style requests scoped by `tabId`; use `AddDocumentTabRequest`/`DeleteTabRequest` when
  the user adds/removes a top-level section. Reuse the mapping logic in the orphaned
  `GoogleDocsService.swift` as a starting point (it already builds `batchUpdate` bodies), extended to
  set `tabId` on every `Location`/`Range`.
- **Scope:** none added — `documents` already granted (`GoogleAuthService.swift:26`).
- **Smoke-test** `AddDocumentTabRequest` live first (the how-to guide omits it; only the REST
  reference/Go lib list it).

**Fallback if C proves too heavy:** stay on **A** permanently for tabbed Docs (they remain
edit-in-Google-only) and keep the current Markdown round-trip for single-tab Docs — which, once A
gates multi-tab Docs out, is safe because single-tab conversion has no tab tree to corrupt.

**Why not B:** it's most of C's engineering (Docs-API path, Markdown⇄requests) for a confusing
half-product where tab-2 edits silently vanish. If you're paying for the Docs API path, go to C.

---

## Sources

Code (this repo):
- `supabase/functions/drive-writeback/index.ts:48,182-233` — Markdown multipart write-back + guard
- `supabase/functions/google-sync/index.ts:369-376,443-467` — Markdown export pull, doc-note branch
- `Atlas/Services/GoogleAuthService.swift:24-27` — OAuth scopes (`documents` already granted)
- `Atlas/Services/GoogleDocWriteBackClient.swift:19-69` — client write-back wrapper
- `Atlas/Services/GoogleDocsService.swift:40,58-70,196-220,408-417` — orphaned Docs-API path (body-only, no tabs)
- `Atlas/Views/References/ReferencePreview.swift:11-17` — `drive.file` per-client caveat

Google (verified live, 2026-07-06):
- documents.get: https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get
- Work with tabs: https://developers.google.com/workspace/docs/api/how-tos/tabs
- batchUpdate (Request types incl. AddDocumentTab/DeleteTab/UpdateDocumentTabProperties): https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate
- Go client type list (corroboration): https://pkg.go.dev/google.golang.org/api/docs/v1
- Document structure: https://developers.google.com/workspace/docs/api/concepts/structure
- Drive files.export (no tab param): https://developers.google.com/workspace/drive/api/reference/rest/v3/files/export
- Markdown import/export launch: https://workspaceupdates.googleblog.com/2024/07/import-and-export-markdown-in-google-docs.html
- Markdown in Docs (support): https://support.google.com/docs/answer/12014036
- Per-tab export is undocumented/URL-only: https://dev.to/googleworkspace/exporting-individual-tabs-from-google-docs-as-pdfs-2903
