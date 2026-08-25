/**
 * Tests for the deterministic class-attribution backstop. Pure string matching —
 * no network — so `deno test` here stays green alongside the other _shared tests.
 *
 * The roster is Drew's real repro case: "Chem lab writeup on genetics" landed in
 * the School space with NO class while these four classes existed.
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyClassBackstop,
  canonicalProjectName,
  classAliasHint,
  matchClass,
  type RosterSpace,
} from "./capture_class_match.ts";

const SCHOOL: RosterSpace = {
  name: "School",
  projects: [
    { name: "College Writing", isClass: true },
    { name: "General Chemistry", isClass: true },
    { name: "Calc I", isClass: true },
    { name: "General Psychology", isClass: true },
  ],
};

const CODED: RosterSpace = {
  name: "School",
  projects: [
    { name: "Introduction to Biology", code: "BIO 201", isClass: true },
    { name: "General Chemistry", code: "CHEM 101", isClass: true },
  ],
};

// ── matchClass: the repro ──────────────────────────────────────
Deno.test("matchClass attaches the chemistry class to a chem lab writeup", () => {
  assertEquals(matchClass("Chem lab writeup on genetics", SCHOOL), "General Chemistry");
});

Deno.test("matchClass resolves the other short forms in the same roster", () => {
  assertEquals(matchClass("Psych reading", SCHOOL), "General Psychology");
  assertEquals(matchClass("Calc problem set", SCHOOL), "Calc I");
  assertEquals(matchClass("English essay draft", SCHOOL), "College Writing");
});

// ── matchClass: conservatism ───────────────────────────────────
Deno.test("matchClass returns null when the text names no subject", () => {
  assertEquals(matchClass("Finish the lab writeup", SCHOOL), null);
  assertEquals(matchClass("Study for the exam", SCHOOL), null);
});

Deno.test("matchClass never guesses between two plausible classes", () => {
  const twoChem: RosterSpace = {
    name: "School",
    projects: [
      { name: "General Chemistry", isClass: true },
      { name: "Organic Chemistry", isClass: true },
    ],
  };
  assertEquals(matchClass("chem lab writeup", twoChem), null);
});

Deno.test("matchClass does not match a stopword shared by class names", () => {
  assertEquals(matchClass("general notes", SCHOOL), null);
});

Deno.test("matchClass requires whole words — 'writeup' is not 'writing'", () => {
  const writingOnly: RosterSpace = {
    name: "School",
    projects: [{ name: "College Writing", isClass: true }],
  };
  assertEquals(matchClass("lab writeup", writingOnly), null);
});

// ── matchClass: codes and full names ───────────────────────────
Deno.test("matchClass matches a spelled-out course code", () => {
  assertEquals(matchClass("BIO 201 lab due friday", CODED), "Introduction to Biology");
});

Deno.test("matchClass matches a code's letter prefix as a short form", () => {
  assertEquals(matchClass("bio lab writeup", CODED), "Introduction to Biology");
});

Deno.test("strong code evidence wins over a soft match on another class", () => {
  const mixed: RosterSpace = {
    name: "School",
    projects: [
      { name: "Seminar", code: "CHEM 300", isClass: true },
      { name: "General Chemistry", isClass: true },
    ],
  };
  assertEquals(matchClass("CHEM 300 paper", mixed), "Seminar");
});

// ── legacy bare-name rosters ───────────────────────────────────
Deno.test("matchClass falls back to all projects when none is flagged isClass", () => {
  const legacy: RosterSpace = { name: "School", projects: ["General Chemistry", "Calc I"] };
  assertEquals(matchClass("chem homework", legacy), "General Chemistry");
});

// ── canonicalProjectName ───────────────────────────────────────
Deno.test("canonicalProjectName restores the user's exact spelling", () => {
  assertEquals(canonicalProjectName("general chemistry", SCHOOL), "General Chemistry");
  assertEquals(canonicalProjectName("  General  Chemistry ", SCHOOL), "General Chemistry");
});

Deno.test("canonicalProjectName strips an echoed code", () => {
  assertEquals(canonicalProjectName("General Chemistry [CHEM 101]", CODED), "General Chemistry");
});

Deno.test("canonicalProjectName rejects a project the user does not have", () => {
  assertEquals(canonicalProjectName("Organic Chemistry", SCHOOL), null);
});

// ── classAliasHint (the prompt side of the same table) ─────────
Deno.test("classAliasHint lists the short forms not already in the name", () => {
  assertEquals(classAliasHint({ name: "General Chemistry", isClass: true }), " (aka chem)");
  assertEquals(
    classAliasHint({ name: "Introduction to Biology", code: "BIO 201", isClass: true }),
    " (aka bio)",
  );
});

Deno.test("classAliasHint is empty for a class with no known short form", () => {
  assertEquals(classAliasHint({ name: "Studio Art", isClass: true }), "");
});

// ── applyClassBackstop (the wired pass) ────────────────────────
Deno.test("applyClassBackstop recovers the class the model left out", () => {
  const items = [{ kind: "task", title: "Chem lab writeup", spaceName: "School" }];
  assertEquals(applyClassBackstop(items, [SCHOOL]), [
    { kind: "task", title: "Chem lab writeup", spaceName: "School", projectName: "General Chemistry" },
  ]);
});

Deno.test("applyClassBackstop treats an explicit null like a missing key", () => {
  const items = [{ kind: "task", title: "Psych reading", spaceName: "School", projectName: null }];
  assertEquals(applyClassBackstop(items, [SCHOOL]), [
    { kind: "task", title: "Psych reading", spaceName: "School", projectName: "General Psychology" },
  ]);
});

Deno.test("applyClassBackstop drops a projectName the space does not have", () => {
  const items = [{ kind: "task", title: "Read chapter 4", spaceName: "School", projectName: "Astronomy" }];
  assertEquals(applyClassBackstop(items, [SCHOOL]), [
    { kind: "task", title: "Read chapter 4", spaceName: "School" },
  ]);
});

Deno.test("applyClassBackstop reads the notes when the title says nothing", () => {
  const items = [{
    kind: "task",
    title: "Writeup",
    spaceName: "School",
    notes: "the genetics one for chem",
  }];
  assertEquals(
    (applyClassBackstop(items, [SCHOOL])[0] as Record<string, unknown>).projectName,
    "General Chemistry",
  );
});

Deno.test("applyClassBackstop leaves other spaces' items alone", () => {
  const items = [{ kind: "task", title: "chem lab writeup", spaceName: "Personal" }];
  assertEquals(applyClassBackstop(items, [SCHOOL]), items);
});

Deno.test("applyClassBackstop never touches an update item", () => {
  const items = [{ kind: "update", targetId: "abc", title: "Chem lab", spaceName: "School" }];
  assertEquals(applyClassBackstop(items, [SCHOOL]), items);
});

Deno.test("applyClassBackstop is a no-op without a roster", () => {
  const items = [{ kind: "task", title: "Chem lab writeup", spaceName: "School" }];
  assertEquals(applyClassBackstop(items, []), items);
});
