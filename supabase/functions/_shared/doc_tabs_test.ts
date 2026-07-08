// supabase/functions/_shared/doc_tabs_test.ts
import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
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

Deno.test("positioned (floating) image flags the tab read-only", () => {
  // Floating images live on paragraph.positionedObjectIds, not in elements[] —
  // a full-tab rewrite deletes the tethering paragraph and the image with it.
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
  assertEquals(t.writable, false);
  assertEquals(t.readonlyReason, "positioned image");
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
// heading/list and the tab gets corrupted on write-back.
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
    ] }, lists: {} },
    childTabs: [],
  }] };
  const t = readTabs(doc)[0];
  assertEquals(t.markdown,
    "\\# not a heading\n\\## also not\n\\- not a bullet\n\\1. not numbered\n");
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

// ── Task 3: renderer (markdown → tabId-scoped batchUpdate requests) ─────────
import { renderRequests, UnmappedImageError } from "./doc_tabs.ts";

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
  // md → requests: concatenated insertText payloads must equal the md's plain text
  // MINUS its final "\n" — the tab's mandatory final paragraph mark supplies that,
  // so content-after-write == md exactly.
  const md = "# Head\nplain **bold** and [site](https://x.com)\n- item\n";
  const reqs = renderRequests("t.X", 2, md) as any[];
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
    const reqs = renderRequests("t.X", 2, md) as any[];
    const inserts = reqs.filter((r: any) => r.insertText).map((r: any) => r.insertText.text);
    assertEquals(inserts.join("") + "\n", md, `unstable for ${JSON.stringify(md)}`);
    // Docs rejects empty insertText — none may ever be emitted.
    assertEquals(inserts.every((t: string) => t.length > 0), true, `empty insert for ${JSON.stringify(md)}`);
  }
});

// ── Task 5: image pipeline (harvest + placeholder + re-insert) ──────────────

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
  });
});

Deno.test("image harvest: cropped image flags the tab read-only ('cropped image')", () => {
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
  assertEquals(t.writable, false);
  assertEquals(t.readonlyReason, "cropped image");
  assertEquals(t.images[0].cropLocked, true);
  // Placeholder is still emitted so the editor can display the (read-only) image.
  assertEquals(t.markdown.includes("![image:kix.c]"), true);
});

Deno.test("image harvest: image sharing a line with text flags 'inline image in text'", () => {
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
  assertEquals(t.writable, false);
  assertEquals(t.readonlyReason, "inline image in text");
  // Missing dimensions come through as null (never 0).
  assertEquals(t.images[0].widthPt, null);
  assertEquals(t.images[0].heightPt, null);
});

Deno.test("renderRequests: known image line emits insertInlineImage + correct index accounting", () => {
  const images = { "kix.a": { uri: "https://signed/a", widthPt: 200, heightPt: 100 } };
  // image (own line, NOT last) then a text line.
  const reqs = renderRequests("t.X", 2, "![image:kix.a]\nafter\n", images) as any[];
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

Deno.test("renderRequests: image as the LAST line adds no trailing newline (drift-safe)", () => {
  const images = { "kix.a": { uri: "https://signed/a", widthPt: 10, heightPt: 20 } };
  const reqs = renderRequests("t.X", 2, "text\n![image:kix.a]\n", images) as any[];
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

Deno.test("renderRequests: image without dimensions omits objectSize", () => {
  const reqs = renderRequests("t.X", 2, "![image:kix.a]\n", { "kix.a": { uri: "https://signed/a" } }) as any[];
  assertEquals(reqs[0], { insertInlineImage: { location: { tabId: "t.X", index: 1 }, uri: "https://signed/a" } });
  assertEquals(reqs.length, 1);
});

Deno.test("renderRequests: unmapped image id throws UnmappedImageError", () => {
  const err = assertThrows(
    () => renderRequests("t.X", 2, "![image:kix.zzz]\n"),
    UnmappedImageError,
  ) as UnmappedImageError;
  assertEquals(err.objectId, "kix.zzz");
});
