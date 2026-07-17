// supabase/functions/_shared/doc_tabs.ts
/**
 * Atlas — Google Docs tab helpers, shared by google-sync (pull) and
 * drive-writeback (push). Converts Docs-API JSON ⇄ the RichDocMarkdown
 * dialect PER TAB and classifies each tab writable/read-only.
 *
 * Fidelity contract (2026-07-08, amended for frozen islands the same day):
 * a tab is WRITABLE when everything outside its FROZEN ISLANDS is expressible
 * in the dialect — paragraphs styled NORMAL_TEXT/HEADING_1/TITLE (→ #) /
 * HEADING_2/SUBTITLE/HEADING_3 (→ ##), flat lists, and runs styled only
 * bold/italic/underline/link. Link runs are exempt from strictness on
 * underline/foregroundColor (Google auto-styles links).
 *
 * FROZEN ISLANDS: tables, horizontal-rule dividers, and image paragraphs that
 * can't round-trip (cropped/rotated/adjusted images, an image sharing its
 * paragraph with text or a heading/list prefix, multiple images on one line,
 * positioned/floating-image tether paragraphs) no longer lock the tab. They are
 * emitted as `!> `-marked lines — display-only in the editor — and the write path
 * SPLICES around them (renderTabRequests): only the editable gaps between islands
 * are ever deleted and rebuilt, so island content is physically untouched by a
 * save. Anything else beyond the dialect (nested lists, unknown styles, smart
 * chips, TOC, mid-doc section breaks, and the remaining unsupported inline
 * elements — page/column breaks, footnotes, equations…) still locks the whole
 * tab, with a lossy-but-readable markdown preview.
 *
 * DIALECT SOURCE OF TRUTH: AtlasCore/Sources/AtlasCore/RichDocMarkdown.swift.
 * The emitted markdown is parsed by `RichDoc.fromMarkdown` for editing and
 * re-serialized by `doc.markdown`, so the escaping here mirrors Swift's
 * `escapeInline` (only `\ * <`) and `escapingLeadingMarker` (leading `# ## - N.`
 * on normal blocks — plus `!>` on the TS side, escaped by the editor's save
 * path, so user text never fakes an island). See doc_tabs_test.ts
 * "divergence:" cases.
 */

/** Line prefix marking a frozen-island line in a tab's markdown. */
const ISLAND_MARKER = "!> ";

export interface DocImage {
  objectId: string;
  contentUri: string | null;
  widthPt: number | null;
  heightPt: number | null;
  cropLocked: boolean;
  /** True when the image lives inside a frozen island — display-only forever
   *  (the splice never deletes it, so it is never re-inserted on write). */
  frozen: boolean;
}

export interface DocTab {
  tabId: string;
  parentTabId: string | null;
  title: string;
  ord: number;
  markdown: string;
  writable: boolean;
  readonlyReason: string | null;
  /** Advisory: a cosmetic inline style (text color, highlight, strikethrough,
   *  small caps, super/subscript) was stripped on import. The tab stays writable;
   *  the styling survives in Google unless the tab is edited and saved. */
  droppedStyling: boolean;
  images: DocImage[];
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
 *  Display/search only — NEVER parsed back or written to Google. Island
 *  markers are an editor-wire concern, so the preview drops them. */
export function tabsPreviewMarkdown(tabs: DocTab[]): string {
  return tabs
    .map((t) => `# ${t.title}\n\n${stripIslandMarkers(t.markdown)}`.trimEnd())
    .join("\n\n") + "\n";
}

/** `md` with every `!> ` island marker removed (bare `!>` lines become empty). */
export function stripIslandMarkers(md: string): string {
  return md
    .split("\n")
    .map((l) => (l === "!>" ? "" : l.startsWith(ISLAND_MARKER) ? l.slice(ISLAND_MARKER.length) : l))
    .join("\n");
}

/** The raw documentTab node for `tabId`, searching the tab tree — the splice
 *  renderer needs element indices, which readTabs' DocTab projection drops. */
export function findDocumentTab(doc: unknown, tabId: string): unknown | null {
  // deno-lint-ignore no-explicit-any
  const stack: any[] = [...(((doc as Record<string, unknown>)?.tabs as any[]) ?? [])];
  while (stack.length) {
    const t = stack.pop();
    if (t?.tabProperties?.tabId === tabId) return t?.documentTab ?? null;
    for (const c of t?.childTabs ?? []) stack.push(c);
  }
  return null;
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
      droppedStyling: conv.droppedStyling,
      images: conv.images,
    });
    if (Array.isArray(t?.childTabs) && t.childTabs.length) {
      walk(t.childTabs, tp.tabId as string, acc);
    }
  }
}

// ── Island classification (shared by pull markdown + write splice) ──────────

/** True when a paragraph is a frozen island: it holds a horizontal-rule divider,
 *  tethers a positioned (floating) image, or carries inline image(s) that can't
 *  round-trip as a solo clean `![image:id]` line — image+text on one line, an
 *  image under a heading/list prefix, several images in one paragraph, or a
 *  cropped/rotated/adjusted image. MUST stay in lockstep between tabToMarkdown
 *  (pull) and segmentTab (write) — it is the single decision both sides share.
 */
// deno-lint-ignore no-explicit-any
function paraIsland(p: any, inlineObjects: any): boolean {
  if (Array.isArray(p.positionedObjectIds) && p.positionedObjectIds.length) return true;
  let imgs = 0;
  let hadText = false;
  let anyCropped = false;
  for (const e of p.elements ?? []) {
    if (e.inlineObjectElement !== undefined) {
      imgs += 1;
      const objectId = e.inlineObjectElement.inlineObjectId as string;
      const imgProps = inlineObjects?.[objectId]?.inlineObjectProperties?.embeddedObject?.imageProperties;
      if (isCropLocked(imgProps)) anyCropped = true;
    } else if (e.horizontalRule !== undefined) {
      // A horizontal-rule divider can't round-trip through the dialect, so it
      // freezes its paragraph — preserved untouched in Google, display-only here.
      return true;
    } else if (e.textRun !== undefined) {
      if (((e.textRun.content as string) ?? "").replace(/\n$/, "") !== "") hadText = true;
    }
  }
  if (imgs === 0) return false;
  const style = p.paragraphStyle?.namedStyleType ?? "NORMAL_TEXT";
  const prefixed = p.bullet !== undefined || H1_STYLES.has(style) || H2_STYLES.has(style);
  return imgs > 1 || hadText || prefixed || anyCropped;
}

// ── Docs JSON → markdown (one tab) ──────────────────────────────────────────

// deno-lint-ignore no-explicit-any
function tabToMarkdown(documentTab: any): { markdown: string; reason: string | null; images: DocImage[]; droppedStyling: boolean } {
  const content: any[] = documentTab?.body?.content ?? [];
  const lists: any = documentTab?.lists ?? {};
  // Inline objects (images) live PER-TAB when the Doc is fetched with
  // includeTabsContent=true, keyed by the inlineObjectId in paragraph elements.
  const inlineObjects: any = documentTab?.inlineObjects ?? {};
  const images: DocImage[] = [];
  let reason: string | null = null;
  let droppedStyling = false; // advisory: a cosmetic inline style was stripped
  const flag = (r: string) => { if (reason === null) reason = r; };
  const lines: string[] = [];
  let orderedCounter = 0;

  content.forEach((el, i) => {
    if (el.sectionBreak !== undefined) {
      if (i !== 0) flag("section break"); // leading sectionBreak is normal Docs structure
      return;
    }
    if (el.table !== undefined) {
      // Frozen island: rendered as a read-only grid, never rewritten (the splice
      // deletes around it) — a table no longer locks the tab.
      orderedCounter = 0;
      lines.push(...tablePreview(el.table).map((l) => ISLAND_MARKER + l));
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
    // Island paragraphs are frozen whole: their content is display-only and the
    // write path never touches it, so nothing INSIDE one can flag the tab.
    const island = paraIsland(p, inlineObjects);
    const style = p.paragraphStyle?.namedStyleType ?? "NORMAL_TEXT";
    if (!island && !KNOWN_STYLES.has(style)) flag(`style ${style}`);

    let prefix = "";
    if (p.bullet !== undefined) {
      if (!island && (p.bullet.nestingLevel ?? 0) > 0) flag("nested list");
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
        const run = runToMarkdown(e.textRun);
        line += run.md;
        if (!island && run.dropped) droppedStyling = true;
      } else if (e.inlineObjectElement !== undefined) {
        // Inline image: harvest it (re-host at pull time; re-insert at write time
        // for WRITABLE image lines, display-only for frozen ones) and emit a
        // placeholder token.
        const objectId = e.inlineObjectElement.inlineObjectId as string;
        const embedded = inlineObjects[objectId]?.inlineObjectProperties?.embeddedObject ?? {};
        const imgProps = embedded.imageProperties ?? {};
        const size = embedded.size ?? {};
        images.push({
          objectId,
          contentUri: typeof imgProps.contentUri === "string" ? imgProps.contentUri : null,
          widthPt: typeof size.width?.magnitude === "number" ? size.width.magnitude : null,
          heightPt: typeof size.height?.magnitude === "number" ? size.height.magnitude : null,
          cropLocked: isCropLocked(imgProps),
          frozen: island,
        });
        line += `![image:${objectId}]`;
      } else if (e.person !== undefined || e.richLink !== undefined) {
        if (!island) flag("smart chip");
      } else if (e.horizontalRule !== undefined) {
        // A horizontal rule always freezes its paragraph (paraIsland), so this is
        // only reached with island === true. Emit a `---` divider token for
        // display; the write splices around the island, leaving the real rule
        // untouched in Google.
        line += "---";
      } else if (e.pageBreak !== undefined || e.columnBreak !== undefined ||
                 e.footnoteReference !== undefined || e.equation !== undefined) {
        if (!island) flag("unsupported inline element");
      }
    }
    if (island) {
      lines.push(ISLAND_MARKER + prefix + line);
      return;
    }
    // Normal paragraphs (no heading/list prefix) get their leading block marker
    // escaped, mirroring RichDocMarkdown.swift's `escapingLeadingMarker` so
    // literal "# …"/"- …"/"N. …" text doesn't re-parse as structure ("!>" is a
    // TS-side addition — the Mac editor escapes it on save, we escape on pull).
    if (prefix === "") line = escapeLeadingMarker(line);
    lines.push(prefix + line);
  });

  const markdown = lines.join("\n") + (lines.length ? "\n" : "");
  return { markdown, reason, images, droppedStyling };
}

/** True when an image carries a crop, rotation, or brightness/contrast/
 *  transparency adjustment (any non-zero) — none of which survive a dialect
 *  round-trip, so such an image freezes its paragraph (re-insert would drop them). */
// deno-lint-ignore no-explicit-any
function isCropLocked(imgProps: any): boolean {
  if (!imgProps) return false;
  const nz = (v: unknown) => typeof v === "number" && v !== 0;
  const cp = imgProps.cropProperties ?? {};
  if (nz(cp.offsetLeft) || nz(cp.offsetRight) || nz(cp.offsetTop) || nz(cp.offsetBottom) || nz(cp.angle)) return true;
  return nz(imgProps.angle) || nz(imgProps.brightness) || nz(imgProps.contrast) || nz(imgProps.transparency);
}

// deno-lint-ignore no-explicit-any
function runToMarkdown(run: any): { md: string; dropped: boolean } {
  const raw = (run.content as string ?? "").replace(/\n$/, "");
  // Empty carrier run (e.g. a styled paragraph-terminating "\n"): drop it, marks
  // and all, matching RichDocMarkdown.swift's `guard !run.text.isEmpty` — an
  // invisible run neither prints marks (degenerate `****`) nor blocks writes.
  if (raw === "") return { md: "", dropped: false };
  const ts = run.textStyle ?? {};
  const link: string | undefined = ts.link?.url;

  // Cosmetic inline styles the dialect can't round-trip (text color, highlight,
  // strikethrough, small caps, super/subscript) no longer lock the tab: we STRIP
  // them, keep the text and its bold/italic/underline/link marks, and raise an
  // advisory `dropped` flag so the editor can note the loss. Write-back never
  // re-applies these, so the styling survives in Google unless the tab is saved.
  // Linked runs' foregroundColor is Google's auto link style — not user styling.
  const dropped = ts.strikethrough === true ||
    ts.smallCaps === true ||
    ts.baselineOffset === "SUPERSCRIPT" || ts.baselineOffset === "SUBSCRIPT" ||
    ts.backgroundColor?.color !== undefined ||
    (ts.foregroundColor?.color !== undefined && link === undefined);

  if (link !== undefined) {
    // Marks inside links are dropped (dialect has no styled links).
    return { md: `[${esc(raw)}](${link})`, dropped };
  }
  let md = esc(raw);
  if (ts.underline === true) md = `<u>${md}</u>`;
  if (ts.bold === true && ts.italic === true) md = `***${md}***`;
  else if (ts.bold === true) md = `**${md}**`;
  else if (ts.italic === true) md = `*${md}*`;
  return { md, dropped };
}

/** Escape dialect-significant characters. Matches RichDocMarkdown.swift's
 *  `escapeInline` EXACTLY — only `\`, `*`, `<`. It does NOT escape `[`: the Swift
 *  serializer leaves `[` literal and its parser has no link syntax (links are a
 *  TS-layer addition that round-trip through Swift as plain text). */
function esc(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/\*/g, "\\*").replace(/</g, "\\<");
}

/** Backslash-escape a leading block marker on a NORMAL paragraph, mirroring
 *  RichDocMarkdown.swift's `escapingLeadingMarker`, so text beginning `# `/`## `/
 *  `- `/`N. ` isn't re-classified as a heading/list by `RichDoc.fromMarkdown` —
 *  plus the island marker `!>`, so literal Doc text never fakes a frozen island
 *  (the Mac editor applies the same escape to user-typed lines on save). */
function escapeLeadingMarker(line: string): string {
  if (line.startsWith("# ") || line.startsWith("## ") || line.startsWith("- ") ||
      /^\d+\. /.test(line) || line === "!>" || line.startsWith(ISLAND_MARKER)) {
    return "\\" + line;
  }
  return line;
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

// ── Markdown → batchUpdate requests (one tab, splicing around islands) ──────

/** Thrown by renderTabRequests when a `![image:id]` placeholder in an EDITABLE
 *  segment has no entry in the `images` map (its re-hosted copy is missing).
 *  Writeback maps this to a 409 tab_readonly so the tab isn't corrupted by
 *  dropping the image. */
export class UnmappedImageError extends Error {
  objectId: string;
  constructor(objectId: string) {
    super(`unmapped image: ${objectId}`);
    this.name = "UnmappedImageError";
    this.objectId = objectId;
  }
}

/** Thrown by renderTabRequests when the client markdown's island sequence no
 *  longer matches the live Doc's (a table/image was added, removed or moved on
 *  Google's side, or user text fabricated a marker). The write is refused —
 *  the splice ranges would land in the wrong places — and the client must
 *  re-pull. */
export class IslandMismatchError extends Error {
  constructor(detail: string) {
    super(`island mismatch: ${detail}`);
    this.name = "IslandMismatchError";
  }
}

export interface LiveIsland { type: "table" | "para"; startIndex: number; endIndex: number }
export interface LiveGap { startIndex: number; endIndex: number }

/** Split a live tab into frozen islands and the editable gaps between them.
 *  gaps.length === islands.length + 1 always; leading/trailing gaps may be
 *  empty (startIndex === endIndex). MUST agree with tabToMarkdown's island
 *  decision — both defer to paraIsland. */
export function segmentTab(documentTab: unknown): { islands: LiveIsland[]; gaps: LiveGap[] } {
  // deno-lint-ignore no-explicit-any
  const content: any[] = (documentTab as any)?.body?.content ?? [];
  // deno-lint-ignore no-explicit-any
  const inlineObjects: any = (documentTab as any)?.inlineObjects ?? {};
  const islands: LiveIsland[] = [];
  const gaps: LiveGap[] = [];
  let pending: LiveGap | null = null;
  let cursor = 1; // where an empty gap sits when no paragraph precedes the next island
  content.forEach((el, i) => {
    if (el.sectionBreak !== undefined && i === 0) return; // leading sectionBreak sits before index 1
    const s = typeof el.startIndex === "number" ? el.startIndex : cursor;
    const e = typeof el.endIndex === "number" ? el.endIndex : cursor;
    let isle: "table" | "para" | null = null;
    if (el.table !== undefined) isle = "table";
    else if (el.paragraph !== undefined) { if (paraIsland(el.paragraph, inlineObjects)) isle = "para"; }
    else isle = "para"; // TOC / stray break — such a tab is read-only anyway; defensive
    if (isle) {
      gaps.push(pending ?? { startIndex: s, endIndex: s });
      pending = null;
      islands.push({ type: isle, startIndex: s, endIndex: e });
    } else {
      pending = pending ? { startIndex: pending.startIndex, endIndex: e } : { startIndex: s, endIndex: e };
    }
    cursor = e;
  });
  gaps.push(pending ?? { startIndex: cursor, endIndex: cursor });
  return { islands, gaps };
}

/** Split the client's tab markdown into island groups and the text segments
 *  between them. texts.length === islands.length + 1. A run of consecutive
 *  `!> |…` lines is ONE table island; every other `!> ` line is its own
 *  paragraph island. */
export function parseClientSegments(markdown: string): { texts: string[][]; islands: { type: "table" | "para" }[] } {
  const lines = markdown.split("\n");
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
  const texts: string[][] = [[]];
  const islands: { type: "table" | "para" }[] = [];
  const isFrozen = (l: string) => l === "!>" || l.startsWith(ISLAND_MARKER);
  const stripped = (l: string) => (l === "!>" ? "" : l.slice(ISLAND_MARKER.length));
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!isFrozen(l)) {
      texts[texts.length - 1].push(l);
      i += 1;
      continue;
    }
    if (stripped(l).startsWith("|")) {
      while (i < lines.length && isFrozen(lines[i]) && stripped(lines[i]).startsWith("|")) i += 1;
      islands.push({ type: "table" });
    } else {
      islands.push({ type: "para" });
      i += 1;
    }
    texts.push([]);
  }
  return { texts, islands };
}

/** Rewrite the EDITABLE gaps of tab `tabId` with the client's markdown, splicing
 *  around the frozen islands (which are never deleted, so their content is
 *  physically untouchable by a save). Zero islands degrades to the classic
 *  whole-tab clear+rebuild. Gaps are processed BOTTOM-UP so every emitted range
 *  refers to original-document indices. Indices are UTF-16 (JS .length).
 *
 *  `images` maps an image objectId → its re-hosted, publicly-fetchable URI (+
 *  preserved size) for WRITABLE `![image:id]` lines in editable gaps; an id
 *  absent from the map throws UnmappedImageError. */
export function renderTabRequests(
  tabId: string,
  documentTab: unknown,
  markdown: string,
  images?: Record<string, { uri: string; widthPt?: number | null; heightPt?: number | null }>,
): unknown[] {
  const live = segmentTab(documentTab);
  const client = parseClientSegments(markdown);
  if (client.islands.length !== live.islands.length) {
    throw new IslandMismatchError(`client has ${client.islands.length} island(s), Doc has ${live.islands.length}`);
  }
  for (let i = 0; i < live.islands.length; i++) {
    if (client.islands[i].type !== live.islands[i].type) {
      throw new IslandMismatchError(`island ${i}: client ${client.islands[i].type} vs Doc ${live.islands[i].type}`);
    }
  }

  const requests: unknown[] = [];
  for (let g = live.gaps.length - 1; g >= 0; g--) {
    const gap = live.gaps[g];
    const linesForGap = client.texts[g] ?? [];
    if (gap.endIndex <= gap.startIndex) {
      // Empty live gap: the Doc has NO paragraph here (islands touch). Nothing to
      // rewrite — unless the client added text, which lands as fresh paragraphs
      // carved out of the PRECEDING island's final newline.
      if (!linesForGap.some((l) => l !== "")) continue;
      if (g === 0) {
        // A Doc that STARTS with a table has no paragraph to splice text into.
        throw new IslandMismatchError("text added above a leading table the Doc has no paragraph for");
      }
      requests.push(...renderLines(tabId, live.islands[g - 1].endIndex - 1, linesForGap, images, true));
      continue;
    }
    // Delete everything in the gap EXCEPT its final newline — that surviving
    // paragraph mark terminates the gap's last inserted line (and, for the
    // tab-final gap, is the tab's mandatory final mark, which cannot be deleted).
    if (gap.endIndex - 1 > gap.startIndex) {
      requests.push({ deleteContentRange: { range: { tabId, startIndex: gap.startIndex, endIndex: gap.endIndex - 1 } } });
    }
    requests.push(...renderLines(tabId, gap.startIndex, linesForGap, images, false));
  }
  return requests;
}

/** Requests for one editable segment's lines starting at `startIndex`. The LAST
 *  line never appends "\n" — the gap's preserved final newline terminates it
 *  (the anti-drift rule proven by the live E2E round-trip). `leadingNewline`
 *  first splits the preceding island's paragraph mark (empty-gap insertion). */
function renderLines(
  tabId: string,
  startIndex: number,
  lines: string[],
  images: Record<string, { uri: string; widthPt?: number | null; heightPt?: number | null }> | undefined,
  leadingNewline: boolean,
): unknown[] {
  const requests: unknown[] = [];
  let index = startIndex;
  if (leadingNewline) {
    requests.push({ insertText: { location: { tabId, index }, text: "\n" } });
    index += 1;
  }
  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const isLast = i === lines.length - 1;

    // ── Image line: `![image:<objectId>]` alone on its line re-inserts the image ──
    // An inline image occupies exactly 1 UTF-16 unit and gets NO paragraph style.
    const imgMatch = /^!\[image:([^\]]+)\]$/.exec(rawLine);
    if (imgMatch) {
      const objectId = imgMatch[1];
      const img = images?.[objectId];
      if (!img) throw new UnmappedImageError(objectId);
      const insert: Record<string, unknown> = { location: { tabId, index }, uri: img.uri };
      if (img.widthPt != null && img.heightPt != null) {
        insert.objectSize = {
          width: { magnitude: img.widthPt, unit: "PT" },
          height: { magnitude: img.heightPt, unit: "PT" },
        };
      }
      requests.push({ insertInlineImage: insert });
      // The image is 1 unit; unless it's the last line, terminate its paragraph
      // with a newline at index+1. Advance 2 (image + "\n"), or 1 when last (the
      // gap's preserved final newline supplies the terminator).
      if (!isLast) {
        requests.push({ insertText: { location: { tabId, index: index + 1 }, text: "\n" } });
        index += 2;
      } else {
        index += 1;
      }
      continue;
    }

    let kind: "h1" | "h2" | "bullet" | "numbered" | "normal" = "normal";
    let rest = rawLine;
    const num = /^(\d+)\. /.exec(rawLine);
    if (rawLine.startsWith("# ")) { kind = "h1"; rest = rawLine.slice(2); }
    else if (rawLine.startsWith("## ")) { kind = "h2"; rest = rawLine.slice(3); }
    else if (rawLine.startsWith("- ")) { kind = "bullet"; rest = rawLine.slice(2); }
    else if (num) { kind = "numbered"; rest = rawLine.slice(num[0].length); }

    const spans = parseInline(rest);
    const content = spans.map((s) => s.text).join("");
    const text = isLast ? content : content + "\n";
    const start = index;
    const end = start + content.length; // style ranges exclude the newline

    if (text) requests.push({ insertText: { location: { tabId, index: start }, text } });
    // Empty lines carry no styleable characters — an empty range is invalid in
    // the Docs API, so style/bullet requests are emitted only for real content.
    if (content.length > 0) {
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
