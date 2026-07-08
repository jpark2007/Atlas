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
 *
 * DIALECT SOURCE OF TRUTH: AtlasCore/Sources/AtlasCore/RichDocMarkdown.swift.
 * The emitted markdown is parsed by `RichDoc.fromMarkdown` for editing and
 * re-serialized by `doc.markdown`, so the escaping here mirrors Swift's
 * `escapeInline` (only `\ * <`) and `escapingLeadingMarker` (leading `# ## - N.`
 * on normal blocks). See doc_tabs_test.ts "divergence:" cases.
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
    // Normal paragraphs (no heading/list prefix) get their leading block marker
    // escaped, mirroring RichDocMarkdown.swift's `escapingLeadingMarker` so
    // literal "# …"/"- …"/"N. …" text doesn't re-parse as structure.
    if (prefix === "") line = escapeLeadingMarker(line);
    lines.push(prefix + line);
  });

  const markdown = lines.join("\n") + (lines.length ? "\n" : "");
  return { markdown, reason };
}

// deno-lint-ignore no-explicit-any
function runToMarkdown(run: any): { md: string; reason: string | null } {
  const raw = (run.content as string ?? "").replace(/\n$/, "");
  // Empty carrier run (e.g. a styled paragraph-terminating "\n"): drop it, marks
  // and all, matching RichDocMarkdown.swift's `guard !run.text.isEmpty` — an
  // invisible run neither prints marks (degenerate `****`) nor blocks writes.
  if (raw === "") return { md: "", reason: null };
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

/** Escape dialect-significant characters. Matches RichDocMarkdown.swift's
 *  `escapeInline` EXACTLY — only `\`, `*`, `<`. It does NOT escape `[`: the Swift
 *  serializer leaves `[` literal and its parser has no link syntax (links are a
 *  TS-layer addition that round-trip through Swift as plain text). */
function esc(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/\*/g, "\\*").replace(/</g, "\\<");
}

/** Backslash-escape a leading block marker on a NORMAL paragraph, mirroring
 *  RichDocMarkdown.swift's `escapingLeadingMarker`, so text beginning `# `/`## `/
 *  `- `/`N. ` isn't re-classified as a heading/list by `RichDoc.fromMarkdown`. */
function escapeLeadingMarker(line: string): string {
  if (line.startsWith("# ") || line.startsWith("## ") || line.startsWith("- ") ||
      /^\d+\. /.test(line)) {
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
  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    let kind: "h1" | "h2" | "bullet" | "numbered" | "normal" = "normal";
    let rest = rawLine;
    const num = /^(\d+)\. /.exec(rawLine);
    if (rawLine.startsWith("# ")) { kind = "h1"; rest = rawLine.slice(2); }
    else if (rawLine.startsWith("## ")) { kind = "h2"; rest = rawLine.slice(3); }
    else if (rawLine.startsWith("- ")) { kind = "bullet"; rest = rawLine.slice(2); }
    else if (num) { kind = "numbered"; rest = rawLine.slice(num[0].length); }
    numbered = kind === "numbered" ? numbered + 1 : 0;

    const spans = parseInline(rest);
    const content = spans.map((s) => s.text).join("");
    // The tab's mandatory final paragraph mark survives the clearing delete and
    // supplies the terminal newline — so the LAST line must NOT add its own "\n",
    // or every write grows the tab by one empty paragraph (cumulative drift,
    // caught by the live E2E round-trip proof).
    const isLast = i === lines.length - 1;
    const text = isLast ? content : content + "\n";
    const start = index;
    const end = start + content.length; // style ranges exclude the newline

    if (text) requests.push({ insertText: { location: { tabId, index: start }, text } });
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
