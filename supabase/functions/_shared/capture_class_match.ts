/**
 * Deterministic class attribution for capture — the backstop behind the prompt.
 *
 * Why: the prompt already ships the user's class roster, but a cheap model still
 * drops `projectName` on obvious coursework ("chem lab writeup" landing in School
 * with no class). Asking harder in the prompt narrows the gap; it never closes it.
 * So after the model answers, THIS module re-reads each item's own text against
 * the roster and attaches the class when the text names exactly one — and only
 * then. It never guesses between two plausible classes, and never invents a
 * project that isn't in the user's space.
 *
 * The same alias table feeds the prompt (`classAliasHint`) and the backstop, so
 * what the model is told matches what the server will enforce.
 *
 * Pure — no network, no Deno APIs — so it unit-tests alongside the other
 * `_shared/*.ts` + `*_test.ts` pairs.
 */

/** A project as the client sends it: a bare name (legacy) or the rich object. */
export type RosterProject =
  | string
  | { name: string; code?: string; overview?: string; isClass?: boolean };
export type RosterSpace = { name: string; projects: RosterProject[] };

/**
 * Subject aliases. `key` is matched as a substring of the class name (or of its
 * code's letter prefix); `aliases` are the whole words a capture actually uses.
 * Deliberately short and unambiguous — every entry here is a word that, on its
 * own, names one subject. Vague stems ("comp", "lab", "gen") are excluded on
 * purpose: a false attach is worse than no attach.
 */
const SUBJECT_ALIASES: { key: string; aliases: string[] }[] = [
  { key: "chemistry", aliases: ["chem", "chemistry"] },
  { key: "organic", aliases: ["orgo", "organic"] },
  { key: "biology", aliases: ["bio", "biology"] },
  { key: "anatomy", aliases: ["anat", "anatomy"] },
  { key: "psychology", aliases: ["psych", "psychology"] },
  { key: "sociolog", aliases: ["soc", "sociology"] },
  { key: "anthropolog", aliases: ["anthro", "anthropology"] },
  { key: "philosoph", aliases: ["phil", "philosophy"] },
  { key: "calculus", aliases: ["calc", "calculus"] },
  { key: "calc", aliases: ["calc", "calculus"] },
  { key: "algebra", aliases: ["algebra"] },
  { key: "geometry", aliases: ["geometry"] },
  { key: "statistic", aliases: ["stat", "stats", "statistics"] },
  { key: "physics", aliases: ["phys", "physics"] },
  { key: "writing", aliases: ["writing", "composition", "english"] },
  { key: "english", aliases: ["english"] },
  { key: "literature", aliases: ["lit", "literature", "english"] },
  { key: "history", aliases: ["hist", "history"] },
  { key: "econom", aliases: ["econ", "economics"] },
  { key: "government", aliases: ["gov", "government"] },
  { key: "accounting", aliases: ["acct", "accounting"] },
  { key: "computer", aliases: ["cs", "computer"] },
  { key: "nursing", aliases: ["nursing"] },
  { key: "spanish", aliases: ["span", "spanish"] },
  { key: "french", aliases: ["french"] },
];

/**
 * Words that appear in class names but name no subject. A capture saying "lab"
 * or "general" must never pull a class out of the roster on its own.
 */
const NAME_STOPWORDS = new Set([
  "general", "intro", "introduction", "introductory", "principles", "fundamentals",
  "foundations", "college", "honors", "advanced", "beginning", "elementary",
  "survey", "seminar", "topics", "lab", "laboratory", "lecture", "recitation",
  "studies", "study", "course", "class", "section", "and", "the", "for", "with",
]);

/** Lowercase alphanumeric words. "Chem lab writeup" → ["chem","lab","writeup"]. */
function tokens(text: string): string[] {
  return text.toLowerCase().match(/[a-z0-9]+/g) ?? [];
}

/** Does `hay` contain `needle` as a contiguous run of whole tokens? */
function containsSequence(hay: string[], needle: string[]): boolean {
  if (!needle.length || needle.length > hay.length) return false;
  for (let i = 0; i + needle.length <= hay.length; i++) {
    let hit = true;
    for (let j = 0; j < needle.length; j++) {
      if (hay[i + j] !== needle[j]) { hit = false; break; }
    }
    if (hit) return true;
  }
  return false;
}

/** One roster class, pre-tokenized for matching. */
type Candidate = {
  name: string;
  nameTokens: string[];
  codeTokens: string[];
  /** Distinctive words of the name (≥4 chars, not a stopword). */
  distinctive: string[];
  /** Whole words a capture might use for this class ("chem", "chemistry"). */
  aliases: Set<string>;
  isClass: boolean;
};

function toCandidate(p: RosterProject): Candidate | null {
  const name = (typeof p === "string" ? p : p?.name ?? "").trim();
  if (!name) return null;
  const code = typeof p === "string" ? "" : (p.code ?? "").trim();
  const isClass = typeof p === "string" ? false : p.isClass === true;

  const nameTokens = tokens(name);
  const codeTokens = tokens(code);
  const distinctive = nameTokens.filter(
    (w) => w.length >= 4 && !NAME_STOPWORDS.has(w) && !/^\d+$/.test(w),
  );

  const aliases = new Set<string>();
  // A code's letter prefix is itself how people talk: "CHEM 101" → "chem".
  const codeAlpha = codeTokens.find((t) => /^[a-z]+$/.test(t));
  if (codeAlpha && codeAlpha.length >= 2) aliases.add(codeAlpha);
  const haystack = `${name} ${code}`.toLowerCase();
  for (const entry of SUBJECT_ALIASES) {
    if (haystack.includes(entry.key)) {
      for (const a of entry.aliases) aliases.add(a);
    }
  }

  return { name, nameTokens, codeTokens, distinctive, aliases, isClass };
}

/**
 * The candidate classes of one space. Projects explicitly flagged `isClass` win;
 * when a client sends none (legacy bare-name payloads), every project in the
 * space is a candidate so those users still get attribution.
 */
function candidates(space: RosterSpace): Candidate[] {
  const all = (space.projects ?? [])
    .map(toCandidate)
    .filter((c): c is Candidate => c !== null);
  const classes = all.filter((c) => c.isClass);
  return classes.length ? classes : all;
}

/** Strong evidence: the text spells out the class's code or its full name. */
function strongMatch(text: string[], c: Candidate): boolean {
  return (c.codeTokens.length > 0 && containsSequence(text, c.codeTokens)) ||
    (c.nameTokens.length > 0 && containsSequence(text, c.nameTokens));
}

/** Soft evidence: a distinctive name word, or a known alias, as a whole word. */
function softMatch(text: string[], c: Candidate): boolean {
  return text.some((t) => c.distinctive.includes(t) || c.aliases.has(t));
}

/**
 * The one class `text` names, or null. Conservative by construction: strong
 * evidence is considered first, and at EITHER tier two matching classes mean
 * null — never a coin flip between the user's classes.
 */
export function matchClass(text: string, space: RosterSpace): string | null {
  const words = tokens(text);
  if (!words.length) return null;
  const pool = candidates(space);

  const strong = pool.filter((c) => strongMatch(words, c));
  if (strong.length === 1) return strong[0].name;
  if (strong.length > 1) return null;

  const soft = pool.filter((c) => softMatch(words, c));
  return soft.length === 1 ? soft[0].name : null;
}

/**
 * Snap a model-supplied project name onto the space's exact spelling. Tolerates
 * case ("general chemistry"), stray whitespace, and the model echoing the code
 * or description back ("General Chemistry [CHEM 101]"). Returns null when the
 * name matches nothing in the space — a project the user doesn't have is worse
 * than none, since it renders as unassigned anyway and loses the color cascade.
 */
export function canonicalProjectName(name: string, space: RosterSpace): string | null {
  const want = tokens(name);
  if (!want.length) return null;
  const pool = (space.projects ?? [])
    .map(toCandidate)
    .filter((c): c is Candidate => c !== null);

  const exact = pool.find((c) =>
    c.nameTokens.length === want.length && containsSequence(want, c.nameTokens)
  );
  if (exact) return exact.name;
  // "General Chemistry [CHEM 101]" — the real name is inside what came back.
  const embedded = pool.filter((c) => containsSequence(want, c.nameTokens));
  return embedded.length === 1 ? embedded[0].name : null;
}

/**
 * The alias hint for one class's prompt line, e.g. ` (aka chem, chemistry)`.
 * Empty when the class has no known short forms, so the prompt stays terse.
 */
export function classAliasHint(p: RosterProject): string {
  const c = toCandidate(p);
  if (!c) return "";
  const nameWords = new Set(c.nameTokens);
  const extra = [...c.aliases].filter((a) => !nameWords.has(a)).sort();
  return extra.length ? ` (aka ${extra.join(", ")})` : "";
}

/**
 * The deterministic pass over the model's items. For every non-update item:
 * canonicalize a supplied `projectName` against the item's own space, and when
 * none survives, try to recover one from the item's own text. Items whose space
 * isn't in the roster are left exactly as the model returned them — attaching a
 * class from a different space would mislabel it (and the client drops a project
 * that doesn't belong to the task's space anyway).
 *
 * Returns new objects; the input is not mutated.
 */
export function applyClassBackstop(
  items: Record<string, unknown>[],
  spaces: RosterSpace[] | undefined,
): Record<string, unknown>[] {
  const roster = (spaces ?? []).filter(
    (s) => s && typeof s.name === "string" && s.name.trim().length > 0,
  );
  if (!roster.length) return items;

  return items.map((raw) => {
    if (!raw || typeof raw !== "object") return raw;
    // An update patches an item the user already filed — its project is theirs.
    if (typeof raw.kind === "string" && raw.kind.toLowerCase() === "update") return raw;

    const spaceName = typeof raw.spaceName === "string" ? raw.spaceName.trim() : "";
    const space = roster.find(
      (s) => s.name.trim().toLowerCase() === spaceName.toLowerCase(),
    );
    if (!space) return raw;

    const supplied = typeof raw.projectName === "string" ? raw.projectName.trim() : "";
    let resolved = supplied ? canonicalProjectName(supplied, space) : null;
    if (!resolved) {
      const title = typeof raw.title === "string" ? raw.title : "";
      const notes = typeof raw.notes === "string" ? raw.notes : "";
      resolved = matchClass(`${title} ${notes}`, space);
    }

    const item = { ...raw };
    // Drop the key entirely when there's no class, keeping the wire shape every
    // shipped client already decodes (projectName absent = unassigned).
    if (resolved) item.projectName = resolved;
    else delete item.projectName;
    return item;
  });
}
