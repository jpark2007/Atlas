// supabase/functions/_shared/doc_tabs_test.ts
import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  countTabs,
  findDocumentTab,
  IslandMismatchError,
  parseClientSegments,
  parseInline,
  readTabs,
  renderTabRequests,
  segmentTab,
  stripIslandMarkers,
  tabsPreviewMarkdown,
  UnmappedImageError,
} from "./doc_tabs.ts";

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
            { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
                elements: [{ textRun: { content: "after the table\n", textStyle: {} } }] } },
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

Deno.test("table becomes a frozen island: tab stays WRITABLE, grid lines carry the marker", () => {
  const t = readTabs(FIXTURE)[1];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.markdown, "!> | a | b |\n!> | c | d |\nafter the table\n");
});

Deno.test("positioned (floating) image tether becomes a frozen paragraph island", () => {
  // Floating images live on paragraph.positionedObjectIds, not in elements[] —
  // the splice never deletes the tethering paragraph, so the image survives.
  const doc = { tabs: [{
    tabProperties: { tabId: "t.p", title: "Float", index: 0 },
    documentTab: { body: { content: [
      { sectionBreak: {} },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          positionedObjectIds: ["kix.float1"],
          elements: [{ textRun: { content: "text beside a floating image\n", textStyle: {} } }] } },
    ] }, lists: {} },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.markdown, "!> text beside a floating image\n");
});

Deno.test("non-island lockers still lock: nested list flags the tab read-only", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.n", title: "Nest", index: 0 },
    documentTab: { body: { content: [
      { sectionBreak: {} },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          bullet: { listId: "kix.l1", nestingLevel: 1 },
          elements: [{ textRun: { content: "deep\n", textStyle: {} } }] } },
    ] }, lists: { "kix.l1": { listProperties: { nestingLevels: [{ glyphType: "GLYPH_TYPE_UNSPECIFIED" }] } } } },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.writable, false);
  assertEquals(t.readonlyReason, "nested list");
});

Deno.test("preview concatenation strips island markers (mobile/search surface)", () => {
  const md = tabsPreviewMarkdown(readTabs(FIXTURE));
  assertEquals(md.startsWith("# Simple\n"), true);
  assertEquals(md.includes("# Rich\n"), true);
  assertEquals(md.includes("| a | b |"), true);
  assertEquals(md.includes("!> "), false);
});

Deno.test("stripIslandMarkers: marked lines lose the marker, bare '!>' becomes empty", () => {
  assertEquals(stripIslandMarkers("a\n!> | x |\n!>\nb"), "a\n| x |\n\nb");
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

// ── Divergence fixtures (Task 2 Step 1) ─────────────────────────────────────
// RichDocMarkdown.swift's actual serializer differs from the plan's draft in
// three ways; each is pinned by a test below so the TS reader stays byte-faithful
// to what `RichDoc.fromMarkdown` will parse.

// Divergence 1: escapeInline escapes ONLY `\ * <` — NOT `[`. Literal brackets
// (and the plan's draft `esc()` that escaped them) would round-trip wrong.
Deno.test("divergence: literal '[' is NOT backslash-escaped (Swift escapeInline)", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.b", title: "B", index: 0 },
    documentTab: { body: { content: [
      { sectionBreak: {} },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "see [x] later\n", textStyle: {} } }] } },
    ] }, lists: {} },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.markdown, "see [x] later\n");
  assertEquals(t.markdown.includes("\\["), false);
  assertEquals(t.writable, true);
});

// Divergence 2: a NORMAL paragraph whose text starts with a block marker is
// backslash-prefixed (Swift escapingLeadingMarker), else Swift re-parses it as a
// heading/list and the tab gets corrupted on write-back. `!>` is the TS-side
// addition: literal Doc text must never fake a frozen island.
Deno.test("divergence: leading block markers on normal paragraphs are escaped", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.m", title: "M", index: 0 },
    documentTab: { body: { content: [
      { sectionBreak: {} },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "# not a heading\n", textStyle: {} } }] } },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "## also not\n", textStyle: {} } }] } },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "- not a bullet\n", textStyle: {} } }] } },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "1. not numbered\n", textStyle: {} } }] } },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "!> not an island\n", textStyle: {} } }] } },
    ] }, lists: {} },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.markdown,
    "\\# not a heading\n\\## also not\n\\- not a bullet\n\\1. not numbered\n\\!> not an island\n");
  assertEquals(t.writable, true);
});

// Divergence 3: marks on an empty carrier run are dropped (Swift inlineMarkdown
// `guard !run.text.isEmpty`), so a bold trailing-newline run must NOT emit `****`.
Deno.test("divergence: empty styled run drops marks (no degenerate '****')", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.e", title: "E", index: 0 },
    documentTab: { body: { content: [
      { sectionBreak: {} },
      { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, elements: [
        { textRun: { content: "hi", textStyle: { bold: true } } },
        { textRun: { content: "\n", textStyle: { bold: true } } },
      ] } },
    ] }, lists: {} },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.markdown, "**hi**\n");
  assertEquals(t.markdown.includes("****"), false);
  assertEquals(t.writable, true);
});

// ── Renderer (markdown → tabId-scoped batchUpdate requests, island splice) ──

/** A tab whose whole body is ONE plain editable paragraph spanning [1, endIndex).
 *  The zero-island degenerate case — renderTabRequests must behave exactly like
 *  the classic whole-tab clear+rebuild these expectations were written against. */
function plainTab(endIndex: number) {
  return {
    body: { content: [
      { sectionBreak: {}, startIndex: 0, endIndex: 1 },
      { startIndex: 1, endIndex, paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "old\n", textStyle: {} } }] } },
    ] },
    inlineObjects: {},
    lists: {},
  };
}

Deno.test("renderTabRequests (no islands): clears the tab then rebuilds line by line", () => {
  const reqs = renderTabRequests("t.X", plainTab(20), "# Head\nplain **bold**\n- item\n") as any[];
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
  // 4. "item" at 17 (LAST line: no trailing \n — the mandatory final paragraph
  // mark supplies it; see the drift regression test below), bulleted
  assertEquals(reqs[6], { insertText: { location: { tabId: "t.X", index: 17 }, text: "item" } });
  assertEquals(reqs[7], { updateParagraphStyle: {
    range: { tabId: "t.X", startIndex: 17, endIndex: 21 },
    paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } });
  assertEquals(reqs[8], { createParagraphBullets: {
    range: { tabId: "t.X", startIndex: 17, endIndex: 21 },
    bulletPreset: "BULLET_DISC_CIRCLE_SQUARE" } });
  assertEquals(reqs.length, 9);
});

Deno.test("renderTabRequests: empty tab (endIndex 2) emits no delete", () => {
  const reqs = renderTabRequests("t.X", plainTab(2), "hi\n") as any[];
  assertEquals("insertText" in (reqs[0] as any), true);
});

Deno.test("renderTabRequests: links become updateTextStyle link requests", () => {
  const reqs = renderTabRequests("t.X", plainTab(2), "see [site](https://x.com)\n") as any[];
  const linkReq = reqs.find((r: any) => r.updateTextStyle?.textStyle?.link) as any;
  assertEquals(linkReq.updateTextStyle.textStyle.link.url, "https://x.com");
  assertEquals(linkReq.updateTextStyle.fields, "link");
  // "see " is 4 chars → link over [5, 9)
  assertEquals(linkReq.updateTextStyle.range, { tabId: "t.X", startIndex: 5, endIndex: 9 });
});

Deno.test("renderTabRequests: numbered list uses the numbered preset", () => {
  const reqs = renderTabRequests("t.X", plainTab(2), "1. one\n2. two\n") as any[];
  const bullets = reqs.filter((r: any) => r.createParagraphBullets);
  assertEquals(bullets.length, 2);
  assertEquals((bullets[0] as any).createParagraphBullets.bulletPreset, "NUMBERED_DECIMAL_ALPHA_ROMAN");
});

Deno.test("round-trip: reader output re-renders to requests that reproduce the text", () => {
  // md → requests: concatenated insertText payloads must equal the md's plain text
  // MINUS its final "\n" — the tab's mandatory final paragraph mark supplies that,
  // so content-after-write == md exactly.
  const md = "# Head\nplain **bold** and [site](https://x.com)\n- item\n";
  const reqs = renderTabRequests("t.X", plainTab(2), md) as any[];
  const inserted = reqs.filter((r: any) => r.insertText).map((r: any) => r.insertText.text).join("");
  assertEquals(inserted, "Head\nplain bold and site\nitem");
});

Deno.test("drift regression: inserted text + mandatory newline == canonical md", () => {
  // Caught live by the E2E round-trip proof: the renderer used to append "\n" on
  // the last line too, so every save grew the tab by one empty paragraph
  // (reader∘renderer == md + "\n", cumulative). The invariant that kills it:
  // for canonical (\n-terminated) markdown, joined inserts + "\n" == plain-text md.
  for (const md of [
    "one line\n",
    "a\nb\n",
    "a\n\nb\n",           // interior blank paragraph preserved
    "trailing blank\n\n", // blank FINAL paragraph: no empty insertText emitted
    "\n",                 // empty tab
  ]) {
    const reqs = renderTabRequests("t.X", plainTab(2), md) as any[];
    const inserts = reqs.filter((r: any) => r.insertText).map((r: any) => r.insertText.text);
    assertEquals(inserts.join("") + "\n", md, `unstable for ${JSON.stringify(md)}`);
    // Docs rejects empty insertText — none may ever be emitted.
    assertEquals(inserts.every((t: string) => t.length > 0), true, `empty insert for ${JSON.stringify(md)}`);
    // Docs rejects empty ranges — no style/bullet request may span zero chars.
    const ranges = reqs
      .map((r: any) => r.updateParagraphStyle?.range ?? r.createParagraphBullets?.range ?? r.updateTextStyle?.range)
      .filter(Boolean);
    assertEquals(ranges.every((r: any) => r.endIndex > r.startIndex), true, `empty range for ${JSON.stringify(md)}`);
  }
});

// ── Island splice ────────────────────────────────────────────────────────────

/** intro paragraph [1,7) · table [7,20) · tail paragraph [20,26). */
const TABLE_TAB = {
  body: { content: [
    { sectionBreak: {}, startIndex: 0, endIndex: 1 },
    { startIndex: 1, endIndex: 7, paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
        elements: [{ textRun: { content: "intro\n", textStyle: {} } }] } },
    { startIndex: 7, endIndex: 20, table: { tableRows: [
      { tableCells: [{ content: [{ paragraph: { elements: [{ textRun: { content: "a\n" } }] } }] }] },
    ] } },
    { startIndex: 20, endIndex: 26, paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
        elements: [{ textRun: { content: "tail!\n", textStyle: {} } }] } },
  ] },
  inlineObjects: {},
  lists: {},
};

Deno.test("segmentTab: islands and gaps interleave, gaps.length == islands.length + 1", () => {
  const { islands, gaps } = segmentTab(TABLE_TAB);
  assertEquals(islands, [{ type: "table", startIndex: 7, endIndex: 20 }]);
  assertEquals(gaps, [{ startIndex: 1, endIndex: 7 }, { startIndex: 20, endIndex: 26 }]);
});

Deno.test("parseClientSegments: marked pipe run is ONE table island; marked non-pipe lines are para islands", () => {
  const { texts, islands } = parseClientSegments("intro\n!> | a | b |\n!> | c | d |\nmid\n!> ![image:kix.z]\ntail\n");
  assertEquals(islands, [{ type: "table" }, { type: "para" }]);
  assertEquals(texts, [["intro"], ["mid"], ["tail"]]);
});

Deno.test("splice: text around a table rewrites ONLY the gaps, bottom-up, table untouched", () => {
  const md = "intro2\n!> | a |\ntail2\n";
  const reqs = renderTabRequests("t.T", TABLE_TAB, md) as any[];
  assertEquals(reqs, [
    // tail gap first (bottom-up): delete [20,25) keeping the final mark, insert at 20
    { deleteContentRange: { range: { tabId: "t.T", startIndex: 20, endIndex: 25 } } },
    { insertText: { location: { tabId: "t.T", index: 20 }, text: "tail2" } },
    { updateParagraphStyle: { range: { tabId: "t.T", startIndex: 20, endIndex: 25 },
        paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } },
    // intro gap: delete [1,6) keeping ITS final newline, insert at 1
    { deleteContentRange: { range: { tabId: "t.T", startIndex: 1, endIndex: 6 } } },
    { insertText: { location: { tabId: "t.T", index: 1 }, text: "intro2" } },
    { updateParagraphStyle: { range: { tabId: "t.T", startIndex: 1, endIndex: 7 },
        paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } },
  ]);
  // No request range may overlap the table [7,20).
  for (const r of reqs) {
    const range = r.deleteContentRange?.range ?? r.updateParagraphStyle?.range;
    const loc = r.insertText?.location;
    if (range) assertEquals(range.endIndex <= 7 || range.startIndex >= 20, true);
    if (loc) assertEquals(loc.index <= 7 || loc.index >= 20, true);
  }
});

Deno.test("splice: island count mismatch throws IslandMismatchError", () => {
  assertThrows(() => renderTabRequests("t.T", TABLE_TAB, "no islands here\n"), IslandMismatchError);
});

Deno.test("splice: island type mismatch throws IslandMismatchError", () => {
  assertThrows(() => renderTabRequests("t.T", TABLE_TAB, "a\n!> frozen para\nb\n"), IslandMismatchError);
});

Deno.test("splice: user-fabricated '!>' island (count too high) throws", () => {
  assertThrows(
    () => renderTabRequests("t.T", TABLE_TAB, "a\n!> | a |\nb\n!> fake\n"),
    IslandMismatchError,
  );
});

Deno.test("splice: text added after a TRAILING island splits the island's final newline", () => {
  // One frozen image para [1,3) as the ONLY (and last) element — trailing gap empty.
  const tab = {
    body: { content: [
      { sectionBreak: {}, startIndex: 0, endIndex: 1 },
      { startIndex: 1, endIndex: 3, paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [
            { inlineObjectElement: { inlineObjectId: "kix.a" } },
            { textRun: { content: " beside\n", textStyle: {} } },
          ] } },
    ] },
    inlineObjects: { "kix.a": { inlineObjectProperties: { embeddedObject: {
      imageProperties: { contentUri: "https://x/i" }, size: {} } } } },
    lists: {},
  };
  const reqs = renderTabRequests("t.I", tab, "!> ![image:kix.a] beside\nnew line\n") as any[];
  assertEquals(reqs, [
    { insertText: { location: { tabId: "t.I", index: 2 }, text: "\n" } },
    { insertText: { location: { tabId: "t.I", index: 3 }, text: "new line" } },
    { updateParagraphStyle: { range: { tabId: "t.I", startIndex: 3, endIndex: 11 },
        paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } },
  ]);
});

Deno.test("splice: text added ABOVE a leading table (no paragraph exists there) throws", () => {
  const tab = {
    body: { content: [
      { sectionBreak: {}, startIndex: 0, endIndex: 1 },
      { startIndex: 1, endIndex: 14, table: { tableRows: [
        { tableCells: [{ content: [{ paragraph: { elements: [{ textRun: { content: "a\n" } }] } }] }] },
      ] } },
      { startIndex: 14, endIndex: 15, paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
          elements: [{ textRun: { content: "\n", textStyle: {} } }] } },
    ] },
    inlineObjects: {},
    lists: {},
  };
  assertThrows(() => renderTabRequests("t.L", tab, "above\n!> | a |\n\n"), IslandMismatchError);
  // …but leaving it alone is fine (empty text segment above the leading table).
  const ok = renderTabRequests("t.L", tab, "!> | a |\n\n") as any[];
  assertEquals(ok, []);
});

Deno.test("findDocumentTab returns the raw node (indices intact) or null", () => {
  const node = findDocumentTab(FIXTURE, "t.child") as any;
  assertEquals(Array.isArray(node?.body?.content), true);
  assertEquals(findDocumentTab(FIXTURE, "t.nope"), null);
});

// ── Image pipeline (harvest + placeholder + re-insert) ──────────────────────

// One tab: an intro paragraph then a solo-paragraph inline image, with the image
// living in the per-tab inlineObjects map (documents.get?includeTabsContent=true).
const IMAGE_DOC = {
  tabs: [{
    tabProperties: { tabId: "t.img", title: "Img", index: 0 },
    documentTab: {
      body: { content: [
        { sectionBreak: {} },
        { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
            elements: [{ textRun: { content: "intro\n", textStyle: {} } }] } },
        { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
            elements: [
              { inlineObjectElement: { inlineObjectId: "kix.img1" } },
              { textRun: { content: "\n", textStyle: {} } },
            ] } },
      ] },
      inlineObjects: {
        "kix.img1": { inlineObjectProperties: { embeddedObject: {
          imageProperties: { contentUri: "https://lh3.example/img1" },
          size: { width: { magnitude: 200, unit: "PT" }, height: { magnitude: 100, unit: "PT" } },
        } } },
      },
      lists: {},
    },
    childTabs: [],
  }],
};

Deno.test("image harvest: solo-paragraph image stays writable + emits id placeholder", () => {
  const t = readTabs(IMAGE_DOC)[0];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.markdown, "intro\n![image:kix.img1]\n");
  assertEquals(t.images.length, 1);
  assertEquals(t.images[0], {
    objectId: "kix.img1",
    contentUri: "https://lh3.example/img1",
    widthPt: 200,
    heightPt: 100,
    cropLocked: false,
    frozen: false,
  });
});

Deno.test("image harvest: cropped image becomes a frozen island (tab stays writable)", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.crop", title: "Crop", index: 0 },
    documentTab: {
      body: { content: [
        { sectionBreak: {} },
        { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
            elements: [
              { inlineObjectElement: { inlineObjectId: "kix.c" } },
              { textRun: { content: "\n", textStyle: {} } },
            ] } },
      ] },
      inlineObjects: {
        "kix.c": { inlineObjectProperties: { embeddedObject: {
          imageProperties: { contentUri: "https://lh3.example/c", cropProperties: { offsetLeft: 0.1 } },
          size: { width: { magnitude: 50, unit: "PT" }, height: { magnitude: 50, unit: "PT" } },
        } } },
      },
      lists: {},
    },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.images[0].cropLocked, true);
  assertEquals(t.images[0].frozen, true);
  // Marked placeholder is still emitted so the editor can display the frozen image.
  assertEquals(t.markdown, "!> ![image:kix.c]\n");
});

Deno.test("image harvest: image sharing a line with text becomes a frozen island", () => {
  const doc = { tabs: [{
    tabProperties: { tabId: "t.mix", title: "Mix", index: 0 },
    documentTab: {
      body: { content: [
        { sectionBreak: {} },
        { paragraph: { paragraphStyle: { namedStyleType: "NORMAL_TEXT" },
            elements: [
              { textRun: { content: "before ", textStyle: {} } },
              { inlineObjectElement: { inlineObjectId: "kix.m" } },
              { textRun: { content: " after\n", textStyle: {} } },
            ] } },
      ] },
      inlineObjects: {
        "kix.m": { inlineObjectProperties: { embeddedObject: {
          imageProperties: { contentUri: "https://lh3.example/m" }, size: {},
        } } },
      },
      lists: {},
    },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.writable, true);
  assertEquals(t.readonlyReason, null);
  assertEquals(t.markdown, "!> before ![image:kix.m] after\n");
  assertEquals(t.images[0].frozen, true);
  // Missing dimensions come through as null (never 0).
  assertEquals(t.images[0].widthPt, null);
  assertEquals(t.images[0].heightPt, null);
});

Deno.test("renderTabRequests: known image line emits insertInlineImage + correct index accounting", () => {
  const images = { "kix.a": { uri: "https://signed/a", widthPt: 200, heightPt: 100 } };
  // image (own line, NOT last) then a text line.
  const reqs = renderTabRequests("t.X", plainTab(2), "![image:kix.a]\nafter\n", images) as any[];
  // image = 1 UTF-16 unit at index 1, WITH objectSize; no paragraph style.
  assertEquals(reqs[0], { insertInlineImage: {
    location: { tabId: "t.X", index: 1 }, uri: "https://signed/a",
    objectSize: { width: { magnitude: 200, unit: "PT" }, height: { magnitude: 100, unit: "PT" } },
  } });
  // paragraph-terminating newline at index+1 (image was not the last line).
  assertEquals(reqs[1], { insertText: { location: { tabId: "t.X", index: 2 }, text: "\n" } });
  // "after" now starts at index 3 (image 1 + newline 1).
  assertEquals(reqs[2], { insertText: { location: { tabId: "t.X", index: 3 }, text: "after" } });
  assertEquals(reqs[3], { updateParagraphStyle: {
    range: { tabId: "t.X", startIndex: 3, endIndex: 8 },
    paragraphStyle: { namedStyleType: "NORMAL_TEXT" }, fields: "namedStyleType" } });
  assertEquals(reqs.length, 4);
});

Deno.test("renderTabRequests: image as the LAST line adds no trailing newline (drift-safe)", () => {
  const images = { "kix.a": { uri: "https://signed/a", widthPt: 10, heightPt: 20 } };
  const reqs = renderTabRequests("t.X", plainTab(2), "text\n![image:kix.a]\n", images) as any[];
  // "text\n" occupies 5 units (indices 1..5) → image inserts at index 6.
  const last = reqs[reqs.length - 1] as any;
  assertEquals(last, { insertInlineImage: {
    location: { tabId: "t.X", index: 6 }, uri: "https://signed/a",
    objectSize: { width: { magnitude: 10, unit: "PT" }, height: { magnitude: 20, unit: "PT" } },
  } });
  // No stray "\n" insert after the final image (the mandatory final mark supplies it).
  const trailingNewlines = reqs.filter((r: any) => r.insertText?.text === "\n");
  assertEquals(trailingNewlines.length, 0);
});

Deno.test("renderTabRequests: image without dimensions omits objectSize", () => {
  const reqs = renderTabRequests("t.X", plainTab(2), "![image:kix.a]\n", { "kix.a": { uri: "https://signed/a" } }) as any[];
  assertEquals(reqs[0], { insertInlineImage: { location: { tabId: "t.X", index: 1 }, uri: "https://signed/a" } });
  assertEquals(reqs.length, 1);
});

Deno.test("renderTabRequests: unmapped image id throws UnmappedImageError", () => {
  const err = assertThrows(
    () => renderTabRequests("t.X", plainTab(2), "![image:kix.zzz]\n"),
    UnmappedImageError,
  ) as UnmappedImageError;
  assertEquals(err.objectId, "kix.zzz");
});
