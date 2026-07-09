# Table editing in Doc tabs — roadmap (decided 2026-07-08)

## Context

Per the v2 fidelity contract (`supabase/functions/_shared/doc_tabs.ts`), a save
rewrites the ENTIRE tab from Atlas's markdown dialect (clearing delete →
re-insert). The dialect has no table vocabulary, so any tab containing a table
is locked whole — including plain text above/below the table. The table itself
already renders fine (read-only grid preview).

Decision (Drew, 2026-07-08): ship **Stage 1 now**; **Stage 2 is the committed
future update**; Stage 3 is possible (the Docs API supports it) but deferred
indefinitely — "Open in Google Docs" covers it.

## Stage 1 — NOW: editable text around a frozen table

Text blocks in a table-bearing tab become editable; the table renders exactly
as today but stays untouchable.

- **Pull** (`doc_tabs.ts`): a table no longer flags the tab read-only. Emit a
  placeholder line (`![table:<n>]`, same pattern as `![image:id]`) plus the
  existing markdown grid preview for display. Other lock reasons (nested lists,
  smart chips, styled runs, TOC, positioned images…) still lock as before.
- **Write-back** (`drive-writeback` + `renderRequests`): instead of one
  clearing delete of the whole tab, splice — locate each table's live
  start/end indices from the `documents.get` JSON the function already
  fetches, then delete/re-insert only the text ranges BETWEEN tables,
  bottom-up so indices stay valid. The table is never inside any deleted
  range → zero fidelity risk.
- **Guard**: table count in the stored markdown placeholders must equal the
  live Doc's table count, else `409 stale` (someone added/removed a table on
  Google's side since the last pull → client must re-pull).
- **Mac editor** (`NoteEditorView`): stop gating on `reason == table`; the
  table preview block itself stays non-editable (per-TextField lock
  infrastructure from the v2 build already supports mixed tabs).
- **Proof**: live E2E — edit text above AND below a real table, save, verify
  the table (cells, styling) is byte-identical in the Doc and both text edits
  landed.

## Stage 2 — FUTURE UPDATE (committed): editable cell text, frozen structure

Edit the text inside table cells from Atlas (fix a typo, update a value).
No adding/removing rows or columns.

- **Pull**: harvest per-cell plain text into the tab payload (cell grid with
  row/col addressing), alongside the placeholder. Cells whose content exceeds
  the dialect (styled runs, lists, images inside cells, merged cells) mark the
  TABLE read-only-cells; the surrounding text stays editable via Stage 1.
- **Editor**: render the grid with per-cell TextFields (same visual grid as
  today's preview); dirty-cell tracking joins the existing tab-dirty state.
- **Write-back**: surgical per-cell replace — from the live `documents.get`
  JSON, resolve each dirty cell's paragraph range inside the table, apply
  `deleteContentRange` + `insertText` per cell, bottom-up across all dirty
  cells so earlier indices stay valid. Structure requests (insertTableRow etc.)
  explicitly out of scope.
- **Guards**: row/col dimensions must match live Doc (else 409 stale); merged
  cells (`rowSpan`/`columnSpan` > 1 anywhere) → cells read-only; staleness
  baseline check unchanged.
- **Effort estimate**: ~2–3 days on top of Stage 1 (index math + cell UI +
  E2E proofs). Prereq: Stage 1's splice machinery.

## Stage 3 — POSSIBLE, deferred: full table editing

Add/remove rows/columns, create tables from Atlas. The API supports it
(`insertTable`, `insertTableRow`, `insertTableColumn`, `deleteTableRow`…), so
this is feasible — the cost is a real grid-editing UI plus fidelity limits:
merged cells, per-cell styling, and column widths don't round-trip a
recreate, so complex tables would still lock or silently lose formatting.
Revisit only if cell-text editing (Stage 2) proves insufficient in practice.

## Interaction with storage efficiency (capacity audit 2026-07-08)

Stage 1 turns some of today's read-only tabs writable. If/when we downscale
"read-only forever" images to save Storage, classify AFTER Stage 1's rules —
images in table tabs may need full fidelity again (writable tab → re-insert
on save uses stored bytes).
