# Per-tab Google Docs Sync (Option C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-tab Google Docs sync per-tab in both directions — tab-aware pull via Docs API, per-tab write-back via `batchUpdate` scoped by `tabId` — so tab structure can never be corrupted, with rich-content tabs (tables/images/exotic formatting) read-only in Atlas.

**Architecture:** A shared TypeScript module (`supabase/functions/_shared/doc_tabs.ts`) converts Docs-API JSON ⇄ Atlas Markdown per tab and classifies each tab writable/read-only. `google-sync` forks its doc-note branch: multi-tab Docs pull via `documents.get?includeTabsContent=true` into a new `doc_note_tabs` table (plus a concatenated preview in `notes.body`); single-tab Docs keep the existing Drive-Markdown path untouched. `drive-writeback` gains a `tabId` branch that writes ONE tab via Docs `batchUpdate` (delete range + insert + style requests, all `tabId`-scoped) and a safety guard that refuses the legacy whole-file rewrite when a Doc has >1 tab. The Mac editor gains a tab switcher (`AtlasSegmentedPicker`), per-tab read-only mode, and saves per tab — gated by `@AppStorage("notes.perTabDocsSync.enabled")`.

**Tech Stack:** Deno/TypeScript edge functions (Supabase), Postgres migration 0020, Swift/SwiftUI (macOS 14, XcodeGen), Google Docs API v1, Drive API v3.

## Global Constraints

- Build check: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` (run `xcodegen generate` first when files were added).
- Deno tests (install once: `brew install deno`): `deno test supabase/functions/_shared/`.
- All work on branch `feat/doc-tabs`. UI behavior is NOT provable by a green build — Drew confirms visually (CLAUDE.md §4).
- Never mislabel a source (CLAUDE.md §5): writability is computed from actual Doc structure at pull time AND re-verified server-side at write time. Never hardcode it.
- The Markdown dialect is `RichDocMarkdown.swift`'s dialect (`# `, `## `, `- `, `N. `, `**bold**`, `*italic*`, `<u>underline</u>`) plus `[text](url)` links. The TS module MUST mirror `RichDocMarkdown.swift`'s exact escaping rules — read that file before writing the TS (Task 2, Step 1).
- Docs API indices are UTF-16 code units. JS `string.length` is UTF-16 — use it directly; do NOT use code-point counting.
- Edge function style: module consts, `throw new Error(\`x ${res.status}: ${text.slice(0, 200)}\`)`, `{ data, error }` destructuring with labeled throws, `dryRun` gating on writes, no console.log (google-sync) / `json()` helper responses (drive-writeback).
- v1 scope cut: NO tab creation/deletion from Atlas — existing tabs only. Google-side tab adds/removes flow in on the next pull. (AddDocumentTab/DeleteTab were probe-verified working; deferred as YAGNI.)
- Feature flag: `notes.perTabDocsSync.enabled` (`@AppStorage`, default `false`). The SERVER guard (multi-tab 409 on legacy write) is NOT flagged — it protects all clients unconditionally.

**Verified inputs this plan is built on** (probe, 2026-07-08, real API): `documents.get?includeTabsContent=true` returns the full tab tree; default get returns ONLY tab 1 (current pull is lossy); per-tab `insertText`/`deleteContentRange`/`updateTextStyle`/`updateParagraphStyle`/`createParagraphBullets` with `tabId` work and don't disturb sibling tabs; `Location.tabId` and `TabProperties.parentTabId` exist in the live discovery doc. Research maps: notes/`project_references` schema (migrations 0001/0002/0013/0018), `google-sync` doc-note branch at `index.ts:443-473` (fork point 448-449), `drive-writeback` guard at 182-201 / upload at 203-233, orphaned `GoogleDocsMapper.batchUpdateBody` at `GoogleDocsService.swift:203-266` (request-shape reference), editor at `Atlas/Views/Notes/NoteEditorView.swift`, segmented control `Atlas/Views/Components/AtlasSegmentedPicker.swift`.

---

### Task 1: Migration 0020 — `doc_note_tabs`

**Files:**
- Create: `supabase/migrations/0020_doc_note_tabs.sql`

**Interfaces:**
- Produces: table `doc_note_tabs` with columns `id, user_id, reference_id, tab_id, parent_tab_id, title, ord, body_md, writable, readonly_reason, updated_at`, unique `(reference_id, tab_id)`, RLS owner-select. Consumed by Tasks 4, 5 (service-role upserts) and Task 6 (client select).

- [ ] **Step 1: Write the migration**

```sql
-- 0020_doc_note_tabs.sql
-- Per-tab storage for multi-tab Google Doc notes (Option C).
-- One row per Docs tab, keyed by the stable Docs tabId. body_md is the tab's
-- content in the RichDocMarkdown dialect. `writable` is computed at pull time
-- from the tab's ACTUAL structure (tables/images/exotic formatting => false)
-- and re-verified server-side at write time — never hardcoded.

create table if not exists doc_note_tabs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  reference_id  uuid not null references project_references(id) on delete cascade,
  tab_id        text not null,
  parent_tab_id text,
  title         text not null default '',
  ord           integer not null default 0,
  body_md       text not null default '',
  writable      boolean not null default true,
  readonly_reason text,
  updated_at    timestamptz not null default now(),
  unique (reference_id, tab_id)
);

create index if not exists doc_note_tabs_reference_idx on doc_note_tabs (reference_id);

alter table doc_note_tabs enable row level security;

-- Clients only ever READ tabs; all writes flow through service-role edge functions.
drop policy if exists "doc_note_tabs: owner reads" on doc_note_tabs;
create policy "doc_note_tabs: owner reads" on doc_note_tabs
  for select using (user_id = auth.uid());
```

- [ ] **Step 2: Sanity-check the SQL statically**

Run: `grep -c "create table\|create policy\|create index" supabase/migrations/0020_doc_note_tabs.sql`
Expected: `3`. (No local Postgres on this machine — the migration is applied and verified against prod in Task 10.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0020_doc_note_tabs.sql
git commit -m "feat(db): doc_note_tabs — per-tab storage for multi-tab Doc notes (0020)"
```

---

### Task 2: Shared TS module — reader (Docs JSON → tabs + Markdown + writability)

**Files:**
- Create: `supabase/functions/_shared/doc_tabs.ts`
- Test: `supabase/functions/_shared/doc_tabs_test.ts`

**Interfaces:**
- Produces (consumed by Tasks 3, 4, 5):
  - `interface DocTab { tabId: string; parentTabId: string | null; title: string; ord: number; markdown: string; writable: boolean; readonlyReason: string | null }`
  - `function readTabs(doc: unknown): DocTab[]` — depth-first over `doc.tabs[]`/`childTabs[]`.
  - `function countTabs(doc: unknown): number` — total tabs incl. nested (cheap guard helper).
  - `function tabsPreviewMarkdown(tabs: DocTab[]): string` — concatenated `# <title>` + body preview for `notes.body`.
  - `interface Span { text: string; bold?: boolean; italic?: boolean; underline?: boolean; link?: string }` and `function parseInline(src: string): Span[]` (shared with Task 3's renderer).

- [ ] **Step 1: Read `AtlasCore/Sources/AtlasCore/RichDocMarkdown.swift` end-to-end.** Record its exact serializer escape rules and parser tolerances (how `*`, `#`, `-`, `N.`, `<u>` are escaped/recognized). The TS `esc()`/`parseInline()` below MUST match them — adjust the code in Steps 2/4 if the Swift file differs from what's written here, and add a fixture test per divergence found.

- [ ] **Step 2: Write the failing tests**

```ts
// supabase/functions/_shared/doc_tabs_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { readTabs, countTabs, tabsPreviewMarkdown, parseInline } from "./doc_tabs.ts";

// Minimal fixture mirroring the real documents.get?includeTabsContent=true shape
// (verified live 2026-07-08 against a 6-tab Doc).
const FIXTURE = {
  title: "Fixture Doc",
  tabs: [
    {
      tabProperties: { tabId: "t.0", title: "Simple", index: 0 },
      documentTab: {
        body: { content: [
          { sectionBreak: {} },
          { paragraph: { paragraphStyle: { namedStyleType: "HEADING_1" },
              elements: [{ textRun: { content: "Head\n", textStyle: {} } }] } },
          { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
              elements: [
                { textRun: { content: "plain ", textStyle: {} } },
                { textRun: { content: "bold", textStyle: { bold: true } } },
                { textRun: { content: " and ", textStyle: {} } },
                { textRun: { content: "site", textStyle: { link: { url: "https://x.com" },
                    underline: true, foregroundColor: { color: { rgbColor: { blue: 1 } } } } } },
                { textRun: { content: "\n", textStyle: {} } },
              ] } },
          { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, bullet: { listId: "kix.l1" },
              elements: [{ textRun: { content: "item\n", textStyle: {} } }] } },
        ] },
        lists: { "kix.l1": { listProperties: { nestingLevels: [{ glyphType: "GLYPH_TYPE_UNSPECIFIED" }] } } },
      },
      childTabs: [
        {
          tabProperties: { tabId: "t.child", title: "Rich", index: 0 },
          documentTab: { body: { content: [
            { sectionBreak: {} },
            { table: { rows: 2, columns: 2, tableRows: [
              { tableCells: [
                { content: [{ paragraph: { elements: [{ textRun: { content: "a\n" } }] } }] },
                { content: [{ paragraph: { elements: [{ textRun: { content: "b\n" } }] } }] },
              ] },
              { tableCells: [
                { content: [{ paragraph: { elements: [{ textRun: { content: "c\n" } }] } }] },
                { content: [{ paragraph: { elements: [{ textRun: { content: "d\n" } }] } }] },
              ] },
            ] } },
          ] }, lists: {} },
          childTabs: [],
        },
      ],
    },
  ],
};

Deno.test("readTabs walks the tree depth-first with parent links", () => {
  const tabs = readTabs(FIXTURE);
  assertEquals(tabs.length, 2);
  assertEquals(tabs[0].tabId, "t.0");
  assertEquals(tabs[0].parentTabId, null);
  assertEquals(tabs[1].tabId, "t.child");
  assertEquals(tabs[1].parentTabId, "t.0");
  assertEquals(countTabs(FIXTURE), 2);
});

Deno.test("simple tab renders markdown and stays writable", () => {
  const t = readTabs(FIXTURE)[0];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.markdown, "# Head\nplain **bold** and [site](https://x.com)\n- item\n");
});

Deno.test("link auto-styling (underline/color on a linked run) does NOT flag read-only", () => {
  assertEquals(readTabs(FIXTURE)[0].writable, true);
});

Deno.test("table tab is read-only with a reason and a lossy-but-readable preview", () => {
  const t = readTabs(FIXTURE)[1];
  assertEquals(t.writable, false);
  assertEquals(t.readonlyReason, "table");
  assertEquals(t.markdown.includes("| a | b |"), true);
});

Deno.test("preview concatenation", () => {
  const md = tabsPreviewMarkdown(readTabs(FIXTURE));
  assertEquals(md.startsWith("# Simple\n"), true);
  assertEquals(md.includes("# Rich\n"), true);
});

Deno.test("parseInline round-trips the vocabulary", () => {
  assertEquals(parseInline("plain **bold** *it* <u>u</u> [t](https://x.com)"), [
    { text: "plain ", bold: false, italic: false, underline: false },
    { text: "bold", bold: true, italic: false, underline: false },
    { text: " ", bold: false, italic: false, underline: false },
    { text: "it", bold: false, italic: true, underline: false },
    { text: " ", bold: false, italic: false, underline: false },
    { text: "u", bold: false, italic: false, underline: true },
    { text: " ", bold: false, italic: false, underline: false },
    { text: "t", bold: false, italic: false, underline: false, link: "https://x.com" },
  ]);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `deno test supabase/functions/_shared/`
Expected: FAIL — `Module not found "./doc_tabs.ts"`.

- [ ] **Step 4: Implement the reader**

```ts
// supabase/functions/_shared/doc_tabs.ts
/**
 * Atlas — Google Docs tab helpers, shared by google-sync (pull) and
 * drive-writeback (push). Converts Docs-API JSON ⇄ the RichDocMarkdown
 * dialect PER TAB and classifies each tab writable/read-only.
 *
 * Fidelity contract (2026-07-08 decision): a tab is WRITABLE only when its
 * entire content is expressible in the dialect — paragraphs styled
 * NORMAL_TEXT/HEADING_1/TITLE (→ #) / HEADING_2/SUBTITLE/HEADING_3 (→ ##),
 * flat lists, and runs styled only bold/italic/underline/link. Anything else
 * (tables, images, nested lists, unknown styles, smart chips…) ⇒ read-only,
 * with a lossy-but-readable markdown preview. Link runs are exempt from
 * strictness on underline/foregroundColor (Google auto-styles links).
 */

export interface DocTab {
  tabId: string;
  parentTabId: string | null;
  title: string;
  ord: number;
  markdown: string;
  writable: boolean;
  readonlyReason: string | null;
}

export interface Span {
  text: string;
  bold?: boolean;
  italic?: boolean;
  underline?: boolean;
  link?: string;
}

const H1_STYLES = new Set(["HEADING_1", "TITLE"]);
const H2_STYLES = new Set(["HEADING_2", "SUBTITLE", "HEADING_3"]);
const KNOWN_STYLES = new Set(["NORMAL_TEXT", ...H1_STYLES, ...H2_STYLES]);
// Mirrors GoogleDocsMapper.orderedGlyphTypes plus upper-case variants.
const ORDERED_GLYPHS = new Set(["DECIMAL", "ZERO_DECIMAL", "ALPHA", "UPPER_ALPHA", "ROMAN", "UPPER_ROMAN"]);

// ── Public API ──────────────────────────────────────────────────────────────

export function readTabs(doc: unknown): DocTab[] {
  const acc: DocTab[] = [];
  walk(((doc as Record<string, unknown>)?.tabs as unknown[]) ?? [], null, acc);
  return acc;
}

export function countTabs(doc: unknown): number {
  return readTabs(doc).length;
}

/** Concatenated read-only preview stored in notes.body for multi-tab Docs.
 *  Display/search only — NEVER parsed back or written to Google. */
export function tabsPreviewMarkdown(tabs: DocTab[]): string {
  return tabs
    .map((t) => `# ${t.title}\n\n${t.markdown}`.trimEnd())
    .join("\n\n") + "\n";
}

// ── Tab tree walk ───────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
function walk(tabs: any[], parent: string | null, acc: DocTab[]) {
  for (const t of tabs) {
    const tp = t?.tabProperties ?? {};
    const conv = tabToMarkdown(t?.documentTab ?? {});
    acc.push({
      tabId: tp.tabId as string,
      parentTabId: parent,
      title: (tp.title as string) ?? "",
      ord: acc.length,
      markdown: conv.markdown,
      writable: conv.reason === null,
      readonlyReason: conv.reason,
    });
    if (Array.isArray(t?.childTabs) && t.childTabs.length) {
      walk(t.childTabs, tp.tabId as string, acc);
    }
  }
}

// ── Docs JSON → markdown (one tab) ──────────────────────────────────────────

// deno-lint-ignore no-explicit-any
function tabToMarkdown(documentTab: any): { markdown: string; reason: string | null } {
  const content: any[] = documentTab?.body?.content ?? [];
  const lists: any = documentTab?.lists ?? {};
  let reason: string | null = null;
  const flag = (r: string) => { if (reason === null) reason = r; };
  const lines: string[] = [];
  let orderedCounter = 0;

  content.forEach((el, i) => {
    if (el.sectionBreak !== undefined) {
      if (i !== 0) flag("section break"); // leading sectionBreak is normal Docs structure
      return;
    }
    if (el.table !== undefined) {
      flag("table");
      lines.push(...tablePreview(el.table));
      return;
    }
    if (el.tableOfContents !== undefined) {
      flag("table of contents");
      return;
    }
    if (el.paragraph === undefined) {
      flag("unsupported element");
      return;
    }

    const p = el.paragraph;
    const style = p.paragraphStyle?.namedStyleType ?? "NORMAL_TEXT";
    if (!KNOWN_STYLES.has(style)) flag(`style ${style}`);

    let prefix = "";
    if (p.bullet !== undefined) {
      if ((p.bullet.nestingLevel ?? 0) > 0) flag("nested list");
      const glyph = lists[p.bullet.listId]?.listProperties?.nestingLevels?.[0]?.glyphType ?? "";
      if (ORDERED_GLYPHS.has(glyph)) {
        orderedCounter += 1;
        prefix = `${orderedCounter}. `;
      } else {
        prefix = "- ";
      }
    } else {
      orderedCounter = 0;
      if (H1_STYLES.has(style)) prefix = "# ";
      else if (H2_STYLES.has(style)) prefix = "## ";
    }

    let line = "";
    for (const e of p.elements ?? []) {
      if (e.textRun !== undefined) {
        const runReason = runToMarkdown(e.textRun);
        line += runReason.md;
        if (runReason.reason) flag(runReason.reason);
      } else if (e.inlineObjectElement !== undefined) {
        flag("image");
        line += "![image]";
      } else if (e.person !== undefined || e.richLink !== undefined) {
        flag("smart chip");
      } else if (e.pageBreak !== undefined || e.columnBreak !== undefined ||
                 e.footnoteReference !== undefined || e.horizontalRule !== undefined ||
                 e.equation !== undefined) {
        flag("unsupported inline element");
      }
    }
    lines.push(prefix + line);
  });

  const markdown = lines.join("\n") + (lines.length ? "\n" : "");
  return { markdown, reason };
}

// deno-lint-ignore no-explicit-any
function runToMarkdown(run: any): { md: string; reason: string | null } {
  const raw = (run.content as string ?? "").replace(/\n$/, "");
  const ts = run.textStyle ?? {};
  const link: string | undefined = ts.link?.url;
  let reason: string | null = null;

  // Strictness: any styling beyond the dialect flags the tab read-only.
  // Linked runs are exempt on underline + foregroundColor (Google's auto link style).
  if (ts.strikethrough === true) reason = "strikethrough";
  else if (ts.smallCaps === true) reason = "small caps";
  else if (ts.baselineOffset === "SUPERSCRIPT" || ts.baselineOffset === "SUBSCRIPT") reason = "super/subscript";
  else if (ts.backgroundColor?.color !== undefined) reason = "highlight color";
  else if (ts.foregroundColor?.color !== undefined && link === undefined) reason = "text color";

  if (link !== undefined) {
    // Marks inside links are dropped (dialect has no styled links).
    return { md: `[${esc(raw)}](${link})`, reason };
  }
  let md = esc(raw);
  if (ts.underline === true) md = `<u>${md}</u>`;
  if (ts.bold === true && ts.italic === true) md = `***${md}***`;
  else if (ts.bold === true) md = `**${md}**`;
  else if (ts.italic === true) md = `*${md}*`;
  return { md, reason };
}

/** Escape dialect-significant characters. MUST match RichDocMarkdown.swift's
 *  escape table (Task 2 Step 1) — adjust here if the Swift file differs. */
function esc(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/\*/g, "\\*").replace(/\[/g, "\\[").replace(/</g, "\\<");
}

// deno-lint-ignore no-explicit-any
function tablePreview(table: any): string[] {
  const rows: string[] = [];
  for (const r of table.tableRows ?? []) {
    const cells: string[] = [];
    for (const c of r.tableCells ?? []) {
      let text = "";
      for (const el of c.content ?? []) {
        for (const e of el.paragraph?.elements ?? []) {
          text += (e.textRun?.content as string ?? "").replace(/\n/g, " ");
        }
      }
      cells.push(text.trim());
    }
    rows.push(`| ${cells.join(" | ")} |`);
  }
  return rows;
}

// ── Inline markdown parser (shared with the renderer, Task 3) ───────────────

export function parseInline(src: string): Span[] {
  const spans: Span[] = [];
  let bold = false, italic = false, underline = false, buf = "";
  const flush = () => {
    if (buf) { spans.push({ text: buf, bold, italic, underline }); buf = ""; }
  };
  let i = 0;
  while (i < src.length) {
    if (src[i] === "\\" && i + 1 < src.length) { buf += src[i + 1]; i += 2; continue; }
    if (src.startsWith("***", i)) { flush(); bold = !bold; italic = !italic; i += 3; continue; }
    if (src.startsWith("**", i)) { flush(); bold = !bold; i += 2; continue; }
    if (src[i] === "*") { flush(); italic = !italic; i += 1; continue; }
    if (src.startsWith("<u>", i)) { flush(); underline = true; i += 3; continue; }
    if (src.startsWith("</u>", i)) { flush(); underline = false; i += 4; continue; }
    if (src[i] === "[") {
      const m = /^\[([^\]]*)\]\(([^)\s]+)\)/.exec(src.slice(i));
      if (m) { flush(); spans.push({ text: m[1], bold, italic, underline, link: m[2] }); i += m[0].length; continue; }
    }
    buf += src[i]; i += 1;
  }
  flush();
  return spans;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/`
Expected: all `doc_tabs_test.ts` tests PASS. If the Step-1 reading of `RichDocMarkdown.swift` revealed different escape rules, `esc()`/`parseInline()` and the fixtures were adjusted together.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/doc_tabs.ts supabase/functions/_shared/doc_tabs_test.ts
git commit -m "feat(sync): shared Docs-tab reader — JSON→markdown per tab + writability classifier"
```

---

### Task 3: Shared TS module — renderer (Markdown → `batchUpdate` requests)

**Files:**
- Modify: `supabase/functions/_shared/doc_tabs.ts` (append)
- Test: `supabase/functions/_shared/doc_tabs_test.ts` (append)

**Interfaces:**
- Consumes: `parseInline`, `Span` (Task 2).
- Produces (consumed by Task 5): `function renderRequests(tabId: string, endIndex: number, markdown: string): unknown[]` — the ordered Docs `batchUpdate` request array that replaces the tab's whole content with `markdown`. Request order mirrors `GoogleDocsMapper.batchUpdateBody` (`GoogleDocsService.swift:203-266`): one deleteContentRange, then per line: insertText → updateParagraphStyle → createParagraphBullets (lists) → updateTextStyle per styled span.

- [ ] **Step 1: Write the failing tests** (append to `doc_tabs_test.ts`)

```ts
import { renderRequests } from "./doc_tabs.ts";

Deno.test("renderRequests: clears the tab then rebuilds line by line", () => {
  const reqs = renderRequests("t.X", 20, "# Head\nplain **bold**\n- item\n") as any[];
  // 1. clear existing content (endIndex 20 → delete [1, 19))
  assertEquals(reqs[0], { deleteContentRange: { range: { tabId: "t.X", startIndex: 1, endIndex: 19 } } });
  // 2. "Head\n" inserted at 1, styled HEADING_1 over [1,5)
  assertEquals(reqs[1], { insertText: { location: { tabId: "t.X", index: 1 }, text: "Head\n" } });
  assertEquals(reqs[2], { updateParagraphStyle: {
    range: { tabId: "t.X", startIndex: 1, endIndex: 5 },
    paragraphStyle: { namedStyleType: "HEADING_1" }, fields: "namedStyleType" } });
  // 3. "plain bold\n" at 6 (UTF-16 length of "Head\n" is 5), NORMAL_TEXT, bold over "bold"
  assertEquals(reqs[3], { insertText: { location: { tabId: "t.X", index: 6 }, text: "plain bold\n" } });
  assertEquals(reqs[4], { updateParagraphStyle: {
    range: { tabId: "t.X", startIndex: 6, endIndex: 16 },
    paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } });
  assertEquals(reqs[5], { updateTextStyle: {
    range: { tabId: "t.X", startIndex: 12, endIndex: 16 },
    textStyle: { bold: true }, fields: "bold" } });
  // 4. "item\n" at 17, bulleted
  assertEquals(reqs[6], { insertText: { location: { tabId: "t.X", index: 17 }, text: "item\n" } });
  assertEquals(reqs[7], { updateParagraphStyle: {
    range: { tabId: "t.X", startIndex: 17, endIndex: 21 },
    paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } });
  assertEquals(reqs[8], { createParagraphBullets: {
    range: { tabId: "t.X", startIndex: 17, endIndex: 21 },
    bulletPreset: "BULLET_DISC_CIRCLE_SQUARE" } });
  assertEquals(reqs.length, 9);
});

Deno.test("renderRequests: empty tab (endIndex 2) emits no delete", () => {
  const reqs = renderRequests("t.X", 2, "hi\n") as any[];
  assertEquals("insertText" in (reqs[0] as any), true);
});

Deno.test("renderRequests: links become updateTextStyle link requests", () => {
  const reqs = renderRequests("t.X", 2, "see [site](https://x.com)\n") as any[];
  const linkReq = reqs.find((r: any) => r.updateTextStyle?.textStyle?.link) as any;
  assertEquals(linkReq.updateTextStyle.textStyle.link.url, "https://x.com");
  assertEquals(linkReq.updateTextStyle.fields, "link");
  // "see " is 4 chars → link over [5, 9)
  assertEquals(linkReq.updateTextStyle.range, { tabId: "t.X", startIndex: 5, endIndex: 9 });
});

Deno.test("renderRequests: numbered list uses the numbered preset", () => {
  const reqs = renderRequests("t.X", 2, "1. one\n2. two\n") as any[];
  const bullets = reqs.filter((r: any) => r.createParagraphBullets);
  assertEquals(bullets.length, 2);
  assertEquals((bullets[0] as any).createParagraphBullets.bulletPreset, "NUMBERED_DECIMAL_ALPHA_ROMAN");
});

Deno.test("round-trip: reader output re-renders to requests that reproduce the text", () => {
  // md → requests: concatenated insertText payloads must equal the md's plain text lines.
  const md = "# Head\nplain **bold** and [site](https://x.com)\n- item\n";
  const reqs = renderRequests("t.X", 2, md) as any[];
  const inserted = reqs.filter((r: any) => r.insertText).map((r: any) => r.insertText.text).join("");
  assertEquals(inserted, "Head\nplain bold and site\nitem\n");
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `deno test supabase/functions/_shared/`
Expected: FAIL — `renderRequests` not exported.

- [ ] **Step 3: Implement the renderer** (append to `doc_tabs.ts`)

```ts
// ── Markdown → batchUpdate requests (one tab) ───────────────────────────────

/** Replace the ENTIRE content of tab `tabId` (current body endIndex `endIndex`)
 *  with `markdown`. Mirrors GoogleDocsMapper.batchUpdateBody's request order,
 *  with every location/range scoped by tabId. Indices are UTF-16 (JS .length). */
export function renderRequests(tabId: string, endIndex: number, markdown: string): unknown[] {
  const requests: unknown[] = [];
  if (endIndex > 2) {
    requests.push({ deleteContentRange: { range: { tabId, startIndex: 1, endIndex: endIndex - 1 } } });
  }

  // Split into lines; a trailing "\n" yields a spurious last "" — drop it.
  const lines = markdown.split("\n");
  if (lines.length && lines[lines.length - 1] === "") lines.pop();

  let index = 1;
  let numbered = 0;
  for (const rawLine of lines) {
    let kind: "h1" | "h2" | "bullet" | "numbered" | "normal" = "normal";
    let rest = rawLine;
    const num = /^(\d+)\. /.exec(rawLine);
    if (rawLine.startsWith("# ")) { kind = "h1"; rest = rawLine.slice(2); }
    else if (rawLine.startsWith("## ")) { kind = "h2"; rest = rawLine.slice(3); }
    else if (rawLine.startsWith("- ")) { kind = "bullet"; rest = rawLine.slice(2); }
    else if (num) { kind = "numbered"; rest = rawLine.slice(num[0].length); }
    numbered = kind === "numbered" ? numbered + 1 : 0;

    const spans = parseInline(rest);
    const text = spans.map((s) => s.text).join("") + "\n";
    const start = index;
    const end = start + text.length - 1; // style ranges exclude the trailing \n

    requests.push({ insertText: { location: { tabId, index: start }, text } });
    requests.push({ updateParagraphStyle: {
      range: { tabId, startIndex: start, endIndex: end },
      paragraphStyle: { namedStyleType: kind === "h1" ? "HEADING_1" : kind === "h2" ? "HEADING_2" : "NORMAL_TEXT" },
      fields: "namedStyleType",
    } });
    if (kind === "bullet" || kind === "numbered") {
      requests.push({ createParagraphBullets: {
        range: { tabId, startIndex: start, endIndex: end },
        bulletPreset: kind === "numbered" ? "NUMBERED_DECIMAL_ALPHA_ROMAN" : "BULLET_DISC_CIRCLE_SQUARE",
      } });
    }

    let cursor = start;
    for (const s of spans) {
      const sEnd = cursor + s.text.length;
      if (s.link !== undefined) {
        requests.push({ updateTextStyle: {
          range: { tabId, startIndex: cursor, endIndex: sEnd },
          textStyle: { link: { url: s.link } }, fields: "link",
        } });
      } else {
        const fields: string[] = [];
        const style: Record<string, boolean> = {};
        if (s.bold) { style.bold = true; fields.push("bold"); }
        if (s.italic) { style.italic = true; fields.push("italic"); }
        if (s.underline) { style.underline = true; fields.push("underline"); }
        if (fields.length) {
          requests.push({ updateTextStyle: {
            range: { tabId, startIndex: cursor, endIndex: sEnd },
            textStyle: style, fields: fields.join(","),
          } });
        }
      }
      cursor = sEnd;
    }
    index += text.length;
  }
  return requests;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/`
Expected: ALL tests PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/doc_tabs.ts supabase/functions/_shared/doc_tabs_test.ts
git commit -m "feat(sync): shared Docs-tab renderer — markdown→tabId-scoped batchUpdate requests"
```

---

### Task 4: `google-sync` — tab-aware pull for multi-tab Docs

**Files:**
- Modify: `supabase/functions/google-sync/index.ts` (doc-note branch, lines 443-473; consts near line 85)

**Interfaces:**
- Consumes: `readTabs`, `tabsPreviewMarkdown`, `DocTab` from `../_shared/doc_tabs.ts`.
- Produces: `doc_note_tabs` rows kept in sync (upsert by `(reference_id, tab_id)`, stale rows deleted) for Docs with >1 tab; `notes.body` = `tabsPreviewMarkdown(...)` for those Docs. Single-tab Docs keep the existing `driveExportMarkdown` path byte-for-byte.

- [ ] **Step 1: Add the import and const**

At the top (after line 81's supabase-js import):
```ts
import { readTabs, tabsPreviewMarkdown } from "../_shared/doc_tabs.ts";
```
In the consts block (near line 85, beside `DRIVE_BASE`):
```ts
const DOCS_BASE = "https://docs.googleapis.com/v1";
```

- [ ] **Step 2: Add the Docs fetch helper** (beside `driveExportMarkdown`, after line 376)

```ts
// Docs API read with the full tab tree. Requires the `documents` scope
// (granted at connect alongside drive.file — GoogleAuthService.scopes).
async function docsGetWithTabs(accessToken: string, fileId: string): Promise<unknown> {
  const res = await fetch(
    `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}?includeTabsContent=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) throw new Error(`documents.get ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return await res.json();
}
```

- [ ] **Step 3: Fork the doc-note branch.** Replace lines 448-467 (the `if (changed) { … }` body — keep the surrounding `changed` computation and the unchanged-path `else` exactly as they are):

```ts
    if (changed) {
      const docJson = await docsGetWithTabs(accessToken, row.drive_file_id);
      const tabs = readTabs(docJson);
      if (tabs.length <= 1) {
        // Single-tab Doc: legacy Drive-Markdown pull, unchanged.
        const markdown = await driveExportMarkdown(accessToken, row.drive_file_id);
        if (!dryRun) {
          if (row.note_id) {
            const { error: nErr } = await admin.from("notes")
              .update({ body: markdown, updated_at: runStartISO })
              .eq("id", row.note_id).eq("user_id", userId);
            if (nErr) throw new Error(`note update failed: ${nErr.message}`);
          }
          // Doc went from multi-tab to single-tab: clear any stale tab rows.
          const { error: dErr } = await admin.from("doc_note_tabs")
            .delete().eq("reference_id", row.id).eq("user_id", userId);
          if (dErr) throw new Error(`tab cleanup failed: ${dErr.message}`);
        }
      } else {
        // Multi-tab Doc: per-tab storage + concatenated preview in notes.body.
        if (!dryRun) {
          const { error: uErr } = await admin.from("doc_note_tabs").upsert(
            tabs.map((t) => ({
              user_id: userId,
              reference_id: row.id,
              tab_id: t.tabId,
              parent_tab_id: t.parentTabId,
              title: t.title,
              ord: t.ord,
              body_md: t.markdown,
              writable: t.writable,
              readonly_reason: t.readonlyReason,
              updated_at: runStartISO,
            })),
            { onConflict: "reference_id,tab_id" },
          );
          if (uErr) throw new Error(`tab upsert failed: ${uErr.message}`);
          // Tabs deleted in Google disappear from the tree — drop their rows.
          const liveIds = tabs.map((t) => t.tabId);
          const { error: gErr } = await admin.from("doc_note_tabs")
            .delete().eq("reference_id", row.id).eq("user_id", userId)
            .not("tab_id", "in", `(${liveIds.map((id) => `"${id}"`).join(",")})`);
          if (gErr) throw new Error(`tab prune failed: ${gErr.message}`);
          if (row.note_id) {
            const { error: nErr } = await admin.from("notes")
              .update({ body: tabsPreviewMarkdown(tabs), updated_at: runStartISO })
              .eq("id", row.note_id).eq("user_id", userId);
            if (nErr) throw new Error(`note update failed: ${nErr.message}`);
          }
        }
      }
      if (!dryRun) {
        const { error: rErr } = await admin.from("project_references")
          .update({
            modified_time: meta.modifiedTime ?? null,
            mime_type: meta.mimeType ?? row.mime_type,
            last_synced_at: runStartISO,
            sync_state: "synced",
          })
          .eq("id", row.id).eq("user_id", userId);
        if (rErr) throw new Error(`reference update failed: ${rErr.message}`);
      }
      synced++;
    }
```

Guard: this branch already only runs for `kind === "doc_note"` rows (line 443), which are Google Docs by construction — no extra mimeType check needed. `docsGetWithTabs` and `readTabs` are reads, so they correctly run even in `dryRun` (matching `driveExportMarkdown`'s existing dryRun behavior).

- [ ] **Step 4: Type-check the function**

Run: `deno check supabase/functions/google-sync/index.ts`
Expected: no errors. (Remote esm.sh import resolution may need `--no-lock`; network fetch of the supabase-js types is expected.)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/google-sync/index.ts
git commit -m "feat(sync): tab-aware pull — multi-tab Docs land in doc_note_tabs, preview in notes.body"
```

---

### Task 5: `drive-writeback` — per-tab write branch + multi-tab guard

**Files:**
- Modify: `supabase/functions/drive-writeback/index.ts` (input parse ~116-137, post-staleness section 203+; consts near line 46)

**Interfaces:**
- Consumes: `readTabs`, `renderRequests`, `countTabs` from `../_shared/doc_tabs.ts`; existing auth/staleness plumbing (lines 93-201) untouched.
- Produces (consumed by Task 7's Swift client):
  - Request body gains optional `tabId: string`.
  - New 409 responses: `{ ok: false, error: "multitab_unsupported", tabCount }` (legacy whole-file write attempted on a multi-tab Doc) and `{ ok: false, error: "tab_readonly", reason }` (per-tab write attempted on a rich tab).
  - Success shape unchanged: `{ ok: true, modifiedTime }`.

- [ ] **Step 1: Add import + const**

Top of file:
```ts
import { readTabs, renderRequests } from "../_shared/doc_tabs.ts";
```
Consts (beside `DRIVE_UPLOAD`, line 47):
```ts
const DOCS_BASE = "https://docs.googleapis.com/v1";
```

- [ ] **Step 2: Parse `tabId` from the body.** In the input block (after the `overwrite` line, 134):

```ts
    tabId =
      typeof b?.tabId === "string" && b.tabId.trim() ? b.tabId.trim() : null;
```
And declare with the others (near line 119): `let tabId: string | null;`

- [ ] **Step 3: Insert the tab logic between the staleness guard (line 201) and the multipart upload (line 203).** The legacy upload block stays for single-tab Docs; wrap it:

```ts
  // ── Tab awareness: read the live tab tree once (Docs API, `documents` scope) ──
  const docRes = await fetch(
    `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}?includeTabsContent=true`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!docRes.ok) {
    const text = (await docRes.text()).slice(0, 200);
    return json({ error: `documents.get ${docRes.status}: ${text}` }, 502);
  }
  const tabs = readTabs(await docRes.json());

  if (tabId === null) {
    // Legacy whole-file Markdown rewrite — SAFE only on single-tab Docs.
    // On a multi-tab Doc the Markdown reconversion destroys the tab tree
    // (undefined behavior, observed corrupting tab nesting) — refuse.
    if (tabs.length > 1) {
      return json({ ok: false, error: "multitab_unsupported", tabCount: tabs.length }, 409);
    }
    // …existing multipart upload block (lines 203-233) runs here unchanged…
  } else {
    // ── Per-tab write: batchUpdate scoped by tabId. Blast radius = this tab. ──
    const tab = tabs.find((t) => t.tabId === tabId);
    if (!tab) return json({ error: "Tab not found in Doc" }, 404);
    // Re-verify writability against the LIVE structure (defense in depth —
    // the tab may have gained a table/image in Google since the last pull).
    if (!tab.writable) {
      return json({ ok: false, error: "tab_readonly", reason: tab.readonlyReason }, 409);
    }
    // endIndex of the tab's current content, for the clearing delete.
    // readTabs doesn't expose it, so recompute from the raw JSON — cheapest is
    // a second fields-limited get scoped to structure only:
    const endRes = await fetch(
      `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}?includeTabsContent=true&fields=tabs`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    if (!endRes.ok) {
      return json({ error: `documents.get(fields) ${endRes.status}` }, 502);
    }
    const endIndex = tabEndIndex(await endRes.json(), tabId);
    if (endIndex === null) return json({ error: "Tab not found in Doc" }, 404);

    const requests = renderRequests(tabId, endIndex, markdown);
    const buRes = await fetch(
      `${DOCS_BASE}/documents/${encodeURIComponent(fileId)}:batchUpdate`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ requests }),
      },
    );
    if (!buRes.ok) {
      const text = (await buRes.text()).slice(0, 200);
      return json({ error: `documents.batchUpdate ${buRes.status}: ${text}` }, 502);
    }
    // Fresh modifiedTime for the new baseline (batchUpdate bumped it).
    const mRes = await fetch(
      `${DRIVE_BASE}/files/${encodeURIComponent(fileId)}?fields=modifiedTime&supportsAllDrives=true`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    const newModifiedTime = mRes.ok ? (await mRes.json()).modifiedTime as string : null;

    // Persist: tab body + reference baseline (storm guard vs the pull cron).
    const nowISO = new Date().toISOString();
    await admin.from("doc_note_tabs")
      .update({ body_md: markdown, updated_at: nowISO })
      .eq("reference_id", refRow.id).eq("tab_id", tabId).eq("user_id", userId);
    const { error: bErr } = await admin.from("project_references")
      .update({ modified_time: newModifiedTime, last_synced_at: nowISO, sync_state: "synced" })
      .eq("id", refRow.id).eq("user_id", userId);
    if (bErr) return json({ ok: true, modifiedTime: newModifiedTime, warning: "baseline not stored" });
    return json({ ok: true, modifiedTime: newModifiedTime });
  }
```

Add the helper beside `sameInstant` (after line 91):
```ts
// Max endIndex of one tab's body content, searching the tab tree recursively.
// deno-lint-ignore no-explicit-any
function tabEndIndex(doc: any, tabId: string): number | null {
  const stack: any[] = [...(doc?.tabs ?? [])];
  while (stack.length) {
    const t = stack.pop();
    if (t?.tabProperties?.tabId === tabId) {
      const content: any[] = t?.documentTab?.body?.content ?? [];
      let max = 1;
      for (const el of content) if (typeof el?.endIndex === "number" && el.endIndex > max) max = el.endIndex;
      return max;
    }
    for (const c of t?.childTabs ?? []) stack.push(c);
  }
  return null;
}
```

Implementation note: the first `documents.get` already includes content, so the `fields=tabs` second fetch is redundant — implementers should keep the raw JSON from the first fetch and pass it to BOTH `readTabs` and `tabEndIndex`, skipping the second fetch entirely. (Written out above for clarity of intent; collapse to one fetch in the real edit.)

- [ ] **Step 4: Type-check**

Run: `deno check supabase/functions/drive-writeback/index.ts`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/drive-writeback/index.ts
git commit -m "feat(writeback): per-tab batchUpdate branch + multi-tab guard on the legacy path"
```

---

### Task 6: Swift — `DocNoteTab` model + DB row + AppState loader

**Files:**
- Modify: `AtlasCore/Sources/AtlasCore/Reference.swift` (append model)
- Modify: `Atlas/Data/AtlasDB.swift` (append row + fetch; follow `ReferenceRow` patterns at 438+)
- Modify: `Atlas/Data/AppState.swift` (append loader)
- Test: `AtlasCore/Tests/AtlasCoreTests/DocNoteTabTests.swift`

**Interfaces:**
- Produces (consumed by Tasks 7, 8):
  - `public struct DocNoteTab: Identifiable, Equatable { public let id: UUID; public let referenceID: UUID; public let tabId: String; public let parentTabId: String?; public let title: String; public let ord: Int; public let bodyMD: String; public let writable: Bool; public let readonlyReason: String? }`
  - `AtlasDB.fetchDocNoteTabs(referenceID: UUID) async throws -> [DocNoteTab]` (GET `doc_note_tabs?reference_id=eq.<id>&order=ord.asc`, RLS-scoped).
  - `AppState.loadDocTabs(referenceID: UUID) async -> [DocNoteTab]` (thin wrapper, returns `[]` on error).

- [ ] **Step 1: Write the failing model test**

```swift
// AtlasCore/Tests/AtlasCoreTests/DocNoteTabTests.swift
import XCTest
@testable import AtlasCore

final class DocNoteTabTests: XCTestCase {
    func testDisplayTitleNestsParent() {
        let parent = DocNoteTab(id: UUID(), referenceID: UUID(), tabId: "t.p", parentTabId: nil,
                                title: "Project A", ord: 0, bodyMD: "", writable: true, readonlyReason: nil)
        let child = DocNoteTab(id: UUID(), referenceID: parent.referenceID, tabId: "t.c", parentTabId: "t.p",
                               title: "Notes", ord: 1, bodyMD: "", writable: true, readonlyReason: nil)
        let tabs = [parent, child]
        XCTAssertEqual(child.displayTitle(in: tabs), "Project A ▸ Notes")
        XCTAssertEqual(parent.displayTitle(in: tabs), "Project A")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path AtlasCore --filter DocNoteTabTests`
Expected: FAIL — `DocNoteTab` not found.

- [ ] **Step 3: Implement the model** (append to `Reference.swift`)

```swift
// MARK: - Doc tabs (multi-tab Google Doc notes)

/// One tab of a multi-tab Google Doc note. Mirrors `doc_note_tabs`.
/// `writable == false` ⇒ the tab contains content Atlas can't safely rewrite
/// (table, image, exotic formatting — `readonlyReason`); the editor shows it
/// read-only and the server refuses writes to it regardless.
public struct DocNoteTab: Identifiable, Equatable {
    public let id: UUID
    public let referenceID: UUID
    public let tabId: String
    public let parentTabId: String?
    public let title: String
    public let ord: Int
    public let bodyMD: String
    public let writable: Bool
    public let readonlyReason: String?

    public init(id: UUID, referenceID: UUID, tabId: String, parentTabId: String?,
                title: String, ord: Int, bodyMD: String, writable: Bool, readonlyReason: String?) {
        self.id = id
        self.referenceID = referenceID
        self.tabId = tabId
        self.parentTabId = parentTabId
        self.title = title
        self.ord = ord
        self.bodyMD = bodyMD
        self.writable = writable
        self.readonlyReason = readonlyReason
    }

    /// "Parent ▸ Child" for nested tabs, matching the Docs sidebar.
    public func displayTitle(in tabs: [DocNoteTab]) -> String {
        guard let parentTabId, let parent = tabs.first(where: { $0.tabId == parentTabId }) else {
            return title
        }
        return "\(parent.title) ▸ \(title)"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path AtlasCore --filter DocNoteTabTests`
Expected: PASS.

- [ ] **Step 5: Add the DB row + fetch** (append to `AtlasDB.swift`, matching `ReferenceRow`'s style — String timestamps decoded leniently, snake_case CodingKeys):

```swift
// MARK: - Doc note tabs

struct DocNoteTabRow: Codable {
    var id: UUID
    var referenceId: UUID
    var tabId: String
    var parentTabId: String?
    var title: String
    var ord: Int
    var bodyMd: String
    var writable: Bool
    var readonlyReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case referenceId = "reference_id"
        case tabId = "tab_id"
        case parentTabId = "parent_tab_id"
        case title
        case ord
        case bodyMd = "body_md"
        case writable
        case readonlyReason = "readonly_reason"
    }

    func toDomain() -> DocNoteTab {
        DocNoteTab(id: id, referenceID: referenceId, tabId: tabId, parentTabId: parentTabId,
                   title: title, ord: ord, bodyMD: bodyMd, writable: writable,
                   readonlyReason: readonlyReason)
    }
}
```
And the fetch, following the exact pattern of the existing reference fetch in this file (same client, same decode helper):
```swift
    func fetchDocNoteTabs(referenceID: UUID) async throws -> [DocNoteTab] {
        let rows: [DocNoteTabRow] = try await select(
            path: "doc_note_tabs",
            query: "reference_id=eq.\(referenceID.uuidString)&order=ord.asc"
        )
        return rows.map { $0.toDomain() }
    }
```
(Implementer: match the file's actual request-building helper — the research shows PostgREST-style calls; mirror however `ReferenceRow` rows are fetched, including auth headers and decoder. If the file exposes a generic `select` differently, adapt the call but keep the signature `fetchDocNoteTabs(referenceID:) async throws -> [DocNoteTab]`.)

- [ ] **Step 6: Add the AppState loader** (append near the reference-sync helpers):

```swift
    /// Tabs of a multi-tab Doc note, ordered. Empty for single-tab docs or on error.
    func loadDocTabs(referenceID: UUID) async -> [DocNoteTab] {
        (try? await db.fetchDocNoteTabs(referenceID: referenceID)) ?? []
    }
```
(Implementer: `db` here is whatever `AppState` names its `AtlasDB` — match the existing property.)

- [ ] **Step 7: Build**

```bash
xcodegen generate && xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add AtlasCore/Sources/AtlasCore/Reference.swift AtlasCore/Tests/AtlasCoreTests/DocNoteTabTests.swift Atlas/Data/AtlasDB.swift Atlas/Data/AppState.swift
git commit -m "feat(model): DocNoteTab + doc_note_tabs fetch + AppState loader"
```

---

### Task 7: Swift — write-back client + protocol gain `tabId`

**Files:**
- Modify: `Atlas/Services/GoogleDocWriteBackClient.swift` (body build ~30-42, outcome mapping ~49-68)
- Modify: `Atlas/Views/Notes/NoteEditorView.swift` (protocol + outcome enum, lines 582-610)

**Interfaces:**
- Consumes: Task 5's new 409 error strings (`multitab_unsupported`, `tab_readonly`).
- Produces (consumed by Task 8):
  - `protocol DocNoteWriteBack { func writeBack(reference: Reference, markdown: String, tabId: String?, overwrite: Bool) async throws -> DocWriteBackOutcome }`
  - `enum DocWriteBackOutcome` gains `.multitabUnsupported(tabCount: Int)` and `.tabReadOnly(reason: String?)`.

- [ ] **Step 1: Extend the protocol + outcome enum** in `NoteEditorView.swift` (lines 582-610):

```swift
enum DocWriteBackOutcome: Equatable {
    case written(modifiedTime: Date?)
    case changedInGoogle
    /// Legacy whole-file write refused: the Doc has tabs. Enable per-tab sync
    /// (Settings) or edit in Google Docs.
    case multitabUnsupported(tabCount: Int)
    /// Per-tab write refused: the tab's live content is beyond the editable
    /// vocabulary (table/image/rich formatting).
    case tabReadOnly(reason: String?)
}

protocol DocNoteWriteBack {
    func writeBack(reference: Reference, markdown: String, tabId: String?, overwrite: Bool) async throws -> DocWriteBackOutcome
}
```
Update the existing two call sites in `push(ref:service:overwrite:)` to pass `tabId: nil` for now (Task 8 threads the real value).

- [ ] **Step 2: Extend the client.** In `GoogleDocWriteBackClient.swift`:
  - Signature: `func writeBack(reference: Reference, markdown: String, tabId: String?, overwrite: Bool) async throws -> DocWriteBackOutcome`.
  - Body dict (after line 34): `if let tabId { body["tabId"] = tabId }`.
  - Outcome mapping (the 409 branch, ~65): extend to:

```swift
        if code == 409, let err = payload["error"] as? String {
            switch err {
            case "stale":
                return .changedInGoogle
            case "multitab_unsupported":
                return .multitabUnsupported(tabCount: payload["tabCount"] as? Int ?? 0)
            case "tab_readonly":
                return .tabReadOnly(reason: payload["reason"] as? String)
            default:
                break
            }
        }
```

- [ ] **Step 3: Build**

Run the standard xcodebuild command.
Expected: BUILD SUCCEEDED (the Task-8-pending call sites compile because they pass `tabId: nil`).

- [ ] **Step 4: Commit**

```bash
git add Atlas/Services/GoogleDocWriteBackClient.swift Atlas/Views/Notes/NoteEditorView.swift
git commit -m "feat(writeback): client + protocol carry tabId; map multitab/readonly 409s"
```

---

### Task 8: Swift — editor tab switcher, per-tab save, read-only mode (flagged)

**Files:**
- Modify: `Atlas/Views/Notes/NoteEditorView.swift` (state ~19-45, onAppear 79-87, core layout 120-152, commit path 513-562)

**Interfaces:**
- Consumes: `AppState.loadDocTabs` (Task 6), `writeBack(… tabId:)` + new outcomes (Task 7), `AtlasSegmentedPicker` (`Atlas/Views/Components/AtlasSegmentedPicker.swift`), flag key `notes.perTabDocsSync.enabled`.
- Produces: the user-visible feature. Multi-tab doc-note + flag ON ⇒ tab switcher between title and styleBar; each tab loads its `bodyMD` into `doc`; read-only tabs disable editing with a banner + "Open in Google Docs" deep link (`?tab=<tabId>`); save pushes ONLY the current tab. Flag OFF or single-tab ⇒ behavior identical to today (server guard still protects).

- [ ] **Step 1: Add state + flag** (with the other `@State`s, ~line 24):

```swift
    @AppStorage("notes.perTabDocsSync.enabled") private var perTabSyncEnabled = false
    @State private var docTabs: [DocNoteTab] = []
    @State private var selectedTab: DocNoteTab?
    @State private var tabDirty = false
```

- [ ] **Step 2: Load tabs on appear.** In `.onAppear`/adjacent `.task` (lines 79-87 area — use a `.task` so async is natural):

```swift
        .task {
            guard perTabSyncEnabled, let ref = docReference else { return }
            let tabs = await state.loadDocTabs(referenceID: ref.id)
            guard tabs.count > 1 else { return }
            docTabs = tabs
            let first = tabs.first!
            selectedTab = first
            doc = RichDoc.fromMarkdown(first.bodyMD)
        }
```

- [ ] **Step 3: Insert the switcher into `core`** (between the title row and `styleBar`, lines 120-133). `AtlasSegmentedPicker` requires `Hashable & Identifiable` options — `DocNoteTab` qualifies via `id`:

```swift
            if !docTabs.isEmpty {
                AtlasSegmentedPicker(
                    options: docTabs,
                    label: { $0.displayTitle(in: docTabs) },
                    selection: Binding(
                        get: { selectedTab ?? docTabs[0] },
                        set: { switchTab(to: $0) }
                    )
                )
                if let tab = selectedTab, !tab.writable {
                    readOnlyTabBanner(tab)
                }
            }
```

- [ ] **Step 4: Tab switching with save-on-switch:**

```swift
    private func switchTab(to tab: DocNoteTab) {
        guard tab.id != selectedTab?.id else { return }
        if tabDirty, let current = selectedTab, current.writable, let ref = docReference {
            // Push the edited tab before leaving it; stay open regardless of outcome.
            let markdown = doc.markdown
            let service = writeBackService
            Task { _ = try? await service?.writeBack(reference: ref, markdown: markdown, tabId: current.tabId, overwrite: false) }
        }
        selectedTab = tab
        doc = RichDoc.fromMarkdown(tab.bodyMD)
        tabDirty = false
    }
```
Also set `tabDirty = true` wherever `isDirty` is set for block edits (`textBinding(for:)`, lines 482-490).

- [ ] **Step 5: Read-only banner** (model on `newerVersionBanner`, lines 267-287; reuse its warning-tint styling):

```swift
    private func readOnlyTabBanner(_ tab: DocNoteTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.doc")
            Text("This tab has content Atlas can't safely edit\(tab.readonlyReason.map { " (\($0))" } ?? "") — read-only here.")
            Spacer()
            Button("Open in Google Docs") {
                if let ref = docReference, let fileId = ref.driveFileId,
                   let url = URL(string: "https://docs.google.com/document/d/\(fileId)/edit?tab=\(tab.tabId)") {
                    openURL(url)
                }
            }
        }
        .font(.callout)
        .padding(10)
        .background(AtlasTheme.Colors.warning.opacity(0.08))
    }
```
Gate editing when the tab is read-only: disable the per-block `TextField`s and `styleBar` (`.disabled(selectedTab.map { !$0.writable } ?? false)` on the blocks scroll + style bar).

- [ ] **Step 6: Per-tab save on Done.** In `commit()`'s doc-note branch (513-527) and `push` (542-562): when `docTabs` is non-empty, pass `tabId: selectedTab?.tabId` (skip the push entirely if the current tab is read-only or `!tabDirty` — just close). Handle the new outcomes in `push`'s switch:

```swift
        case .multitabUnsupported:
            // Flag OFF but the Doc grew tabs: local copy kept, nothing pushed.
            showMultitabNotice = true
        case .tabReadOnly:
            showTabReadOnlyNotice = true
```
Add the two `@State` booleans and matching `.alert`s:
- multitab: title "This Doc has multiple tabs", message "Atlas kept your local copy but didn't push it — enable per-tab sync in Settings → General, or edit this Doc in Google Docs.", OK.
- readOnly: title "Tab is read-only", message "This tab's content (table, image, or rich formatting) can only be edited in Google Docs.", OK.

- [ ] **Step 7: Build, then STOP for visual pass**

Run the standard xcodebuild command.
Expected: BUILD SUCCEEDED. Per CLAUDE.md §4 this is UI — applied + builds ≠ works. Drew must visually confirm: switcher renders, tabs switch content, read-only tab locks editing, save pushes one tab.

- [ ] **Step 8: Commit**

```bash
git add Atlas/Views/Notes/NoteEditorView.swift
git commit -m "feat(editor): per-tab switcher, save-on-switch, read-only tabs (flagged)"
```

---

### Task 9: Swift — Settings flag toggle + real connection-status badge

**Files:**
- Modify: `Atlas/Views/Auth/SettingsView.swift` (general/integrations sections, toggle rows pattern at 399-412 / 488-495)
- Modify: `Atlas/Data/AtlasDB.swift` (append status fetch)

**Interfaces:**
- Consumes: `google_connections` owner-read RLS policy (0006:100-103 — already live) exposing `status`/`last_error`.
- Produces: a "Per-tab Google Doc sync (beta)" toggle bound to `@AppStorage("notes.perTabDocsSync.enabled")`; a connection badge in the Google integration section that shows the SERVER's view: `status == "active"` ⇒ "Connected", `"revoked"`/`"error"` ⇒ "⚠ Reconnect needed — sync is stopped" (accent/warning color), no row ⇒ "Not connected". This answers Drew's requirement: the app must say when it's not actually connected.

- [ ] **Step 1: Status fetch** (append to `AtlasDB.swift`, same PostgREST idiom as Task 6):

```swift
    struct GoogleConnectionStatus: Codable {
        var status: String
        var lastError: String?
        enum CodingKeys: String, CodingKey {
            case status
            case lastError = "last_error"
        }
    }

    /// The SERVER's view of the Google connection (google_connections.status).
    /// nil ⇒ no connection row. RLS: owner-read policy from 0006.
    func fetchGoogleConnectionStatus() async throws -> GoogleConnectionStatus? {
        let rows: [GoogleConnectionStatus] = try await select(
            path: "google_connections",
            query: "select=status,last_error&limit=1"
        )
        return rows.first
    }
```

- [ ] **Step 2: Toggle + badge in SettingsView.** Follow the exact row idiom of the two-way sync toggle (488-495): a labeled hairline row with `Toggle("", isOn: $perTabSyncEnabled).toggleStyle(.switch)` where `@AppStorage("notes.perTabDocsSync.enabled") private var perTabSyncEnabled = false`, caption "Per-tab Google Doc sync (beta) — multi-tab Docs edit tab-by-tab; tabs with tables or images stay read-only." Place it in the integrations section beside the Google sync rows. For the badge: `@State private var connectionStatus: String?` loaded in a `.task` via `fetchGoogleConnectionStatus()`; render next to the Google connect controls:

```swift
    if let s = connectionStatus {
        if s == "active" {
            Text("Connected").foregroundStyle(AtlasTheme.Colors.mutedText)
        } else {
            Text("⚠ Reconnect needed — sync is stopped")
                .foregroundStyle(AtlasTheme.Colors.warning)
        }
    }
```
(Implementer: match `AtlasTheme` color names actually present; research shows `.warning` and muted text styles in use in this file's vocabulary.)

- [ ] **Step 3: Build, commit**

```bash
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
git add Atlas/Views/Auth/SettingsView.swift Atlas/Data/AtlasDB.swift
git commit -m "feat(settings): per-tab sync flag + real server-side connection status badge"
```

---

### Task 10: Deploy — migrations 0016→0020 + both edge functions

**Files:** none (operational). Project ref: `jxrmozhgsebwtbdleyxp`.

Decision on record (Drew, 2026-07-08): push EVERYTHING pending, including 0016 shared-projects (0019 fixes its recursive policy — they go together).

- [ ] **Step 1: Inventory what prod is missing**

Run: `supabase migration list --project-ref jxrmozhgsebwtbdleyxp`
Expected: local 0001-0020, remote missing some tail set (likely 0016+, possibly minus 0017/0018 which one memory says are live — TRUST THIS COMMAND over any note).

- [ ] **Step 2: Push**

Run: `supabase db push --project-ref jxrmozhgsebwtbdleyxp`
Expected: applies the pending tail in order, ending with 0020. If 0016 errors on prod state, STOP and report — do not hand-edit prod.

- [ ] **Step 3: Verify 0020 live**

```bash
SK=$(supabase projects api-keys --project-ref jxrmozhgsebwtbdleyxp -o json | python3 -c "import sys,json,base64
rows=json.load(sys.stdin)
def role(j):
    p=j.split('.')[1]; p+='='*(-len(p)%4)
    return json.loads(base64.urlsafe_b64decode(p)).get('role')
print(next(r['api_key'] for r in rows if role(r['api_key'])=='service_role'))")
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/rest/v1/doc_note_tabs?limit=1" -H "apikey: $SK" -H "Authorization: Bearer $SK"
```
Expected: `[]` (empty array — table exists, no rows). NEVER echo `$SK` itself.

- [ ] **Step 4: Check existing function JWT settings, then deploy both functions**

Run: `supabase functions list --project-ref jxrmozhgsebwtbdleyxp` — note each function's `verify_jwt` value, then deploy preserving them:
```bash
supabase functions deploy google-sync drive-writeback --project-ref jxrmozhgsebwtbdleyxp
```
(Append `--no-verify-jwt` per function ONLY if that matches its current setting — google-sync is service-role-called by pg_cron and does its own auth.)
Expected: both deploy green; `_shared/doc_tabs.ts` is bundled automatically via the relative import.

- [ ] **Step 5: Smoke the deployed google-sync in dryRun**

```bash
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/google-sync?dryRun=1" -X POST -H "Authorization: Bearer $SK" -H "Content-Type: application/json" -d '{}'
```
Expected: `{ ok: true, dryRun: true, ... }` with no thrown errors. (If Drew hasn't reconnected Google yet, users may show revoked — that's fine; the function must not 500.)

- [ ] **Step 6: Commit nothing; record deploy in the run log** (append a dated line to the PR/branch description or `docs/HANDOFF.md` if asked).

---

### Task 11: Live E2E — real Doc, real functions, round-trip proof

**Files:**
- Create: `scripts/doc_tabs_e2e.py` (committed; secrets read at runtime, never embedded)

**Preconditions:** Task 10 deployed; Drew has reconnected Google in-app (fresh Vault token, `status=active`) — the script hard-fails with a clear message if `status != active`. Uses Drew's real 6-tab test Doc `1mn4G22zFRY09eVXQtZFUoIg1twA8qzoSGoYwiVeAl4Y` READ-ONLY plus a throwaway copy for writes.

- [ ] **Step 1: Write the script.** Contract (full script, ~150 lines, follows the probe's proven patterns):
  1. Service key via `supabase projects api-keys` (as Task 10 Step 3); Google client id/secret from `Config/Secrets.xcconfig`; refresh token via `read_google_secret` RPC on the single `google_connections` row; mint access token (probe's `oauth2.googleapis.com/token` flow). Abort with instructions if `status != "active"`.
  2. **Copy** the test Doc via Drive `files.copy` (throwaway; print its URL).
  3. **Pull proof:** `documents.get?includeTabsContent=true` on the copy → assert 6 tabs, correct tree (4 top + 2 nested).
  4. **Renderer round-trip on the live API:** for the simple-text tab (`Tap1`-equivalent): read its markdown via the same conversion the server uses (invoke a small Deno shim: `deno run --allow-net scripts/doc_tabs_shim.ts read <json-file>` OR reimplement the read in Python matching `doc_tabs.ts` — implementer's choice, the Deno shim avoids double-implementation), write it back through the DEPLOYED `drive-writeback` function (`{noteId, tabId, markdown}` with a real note linked to the copy — create the `project_references` + `notes` rows directly via PostgREST with the service key, cleanup at the end), then re-read the tab and assert markdown equality.
  5. **Guard proofs against the deployed function:** (a) legacy write (`tabId` absent) to the multi-tab copy → expect 409 `multitab_unsupported`; (b) per-tab write to the table tab → expect 409 `tab_readonly`.
  6. **Isolation proof:** after the tab write, re-read ALL tabs → assert every OTHER tab's content is byte-identical to before.
  7. Cleanup: delete the created notes/references/doc_note_tabs rows; trash the copy via Drive.
  8. Print a PASS/FAIL table of all assertions.

- [ ] **Step 2: Run it**

Run: `python3 scripts/doc_tabs_e2e.py`
Expected: every assertion PASS. Isolation proof (6) is the headline: a tab write may touch nothing else.

- [ ] **Step 3: Trigger a real pull and verify rows**

Force one live sync tick (real, not dryRun — same curl as Task 10 Step 5 without `dryRun=1`), then:
```bash
curl -s "https://jxrmozhgsebwtbdleyxp.supabase.co/rest/v1/doc_note_tabs?select=title,ord,writable,readonly_reason&order=ord" -H "apikey: $SK" -H "Authorization: Bearer $SK"
```
Expected: rows for any multi-tab doc-note Drew has actually linked in Atlas (if none linked yet, link the test Doc in-app first — Drew action).

- [ ] **Step 4: Commit**

```bash
git add scripts/doc_tabs_e2e.py
git commit -m "test(e2e): live per-tab round-trip, guard, and isolation proofs"
```

- [ ] **Step 5: Hand to Drew for the visual pass** — flag ON in Settings, open the linked multi-tab note: switcher, tab content, read-only banner on the table tab, edit+save a simple tab, confirm in Google Docs the edit landed and every other tab is untouched. THE FEATURE IS NOT "WORKING" UNTIL DREW CONFIRMS THIS.

---

## Execution notes for the orchestrator

- Task order is dependency order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11. Tasks 4+5 depend on 2+3; 7 depends on 5's error strings; 8 depends on 6+7. Tasks (4,5) can run in parallel after 3; (6) can run in parallel with (4,5); (8,9) after (6,7).
- Subagent per task (Opus), code-review between tasks per superpowers:subagent-driven-development.
- Rollback story: code = revert branch `feat/doc-tabs`; functions = redeploy previous main; migration 0020 is additive-only (safe to leave); any touched Doc = Google revision history.
- Out of scope (explicitly): tab create/delete from Atlas; per-tab staleness (file-level `modified_time` baseline retained); mobile editor changes (server guard protects mobile writes regardless); tabsPreviewMarkdown being parseable back (display-only).
