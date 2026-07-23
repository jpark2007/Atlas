/**
 * Atlas — shared ICS (RFC 5545 subset) parser + Canvas course-routing helpers.
 *
 * Extracted verbatim from canvas-sync (0012) so BOTH canvas-sync and feeds-sync
 * (the generalized multi-feed runner) parse identically. canvas-sync stays
 * deployed as a compatibility endpoint and imports these; feeds-sync imports the
 * same parser and — for feed_type='canvas' — the same course-routing helpers.
 *
 * Pure (no network / DB), so unit-testable the way google_pull's isChanged is.
 */

// ── ICS parsing (the RFC 5545 subset Canvas / generic feeds emit) ──────────────

/** RFC 5545 line unfolding: a continuation line begins with SPACE or TAB; join it
 *  to the previous logical line, dropping that one leading whitespace char. */
export function unfold(raw: string): string[] {
  const physical = raw.split(/\r\n|\r|\n/);
  const out: string[] = [];
  for (const line of physical) {
    if (out.length > 0 && (line.startsWith(" ") || line.startsWith("\t"))) {
      out[out.length - 1] += line.slice(1);
    } else {
      out.push(line);
    }
  }
  return out;
}

/** RFC 5545 TEXT unescape: \\n / \\N → newline, \\, → comma, \\; → semicolon,
 *  \\\\ → backslash. Single pass so an escaped backslash never re-triggers. */
export function unescapeText(v: string): string {
  let out = "";
  for (let i = 0; i < v.length; i++) {
    if (v[i] === "\\" && i + 1 < v.length) {
      const n = v[i + 1];
      if (n === "n" || n === "N") out += "\n";
      else if (n === "," || n === ";" || n === "\\") out += n;
      else out += n; // unknown escape → keep the escaped char literally
      i++;
    } else {
      out += v[i];
    }
  }
  return out;
}

export interface PropLine {
  name: string;
  params: Map<string, string>;
  value: string;
}

/** Parse one unfolded content line "NAME;PARAM=VAL;…:VALUE" into name/params/value.
 *  Splits on the first colon and semicolons that are NOT inside a quoted string. */
export function parseLine(line: string): PropLine | null {
  let inQuote = false;
  let colon = -1;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') inQuote = !inQuote;
    else if (c === ":" && !inQuote) { colon = i; break; }
  }
  if (colon === -1) return null;
  const left = line.slice(0, colon);
  const value = line.slice(colon + 1);

  const parts: string[] = [];
  let cur = "";
  inQuote = false;
  for (const c of left) {
    if (c === '"') { inQuote = !inQuote; cur += c; }
    else if (c === ";" && !inQuote) { parts.push(cur); cur = ""; }
    else cur += c;
  }
  parts.push(cur);

  const name = parts[0].toUpperCase();
  const params = new Map<string, string>();
  for (let i = 1; i < parts.length; i++) {
    const eq = parts[i].indexOf("=");
    if (eq > 0) {
      params.set(parts[i].slice(0, eq).toUpperCase(), parts[i].slice(eq + 1).replace(/^"|"$/g, ""));
    }
  }
  return { name, params, value };
}

/** Offset (localWall − UTC) in ms of `tzid` at the instant `utcDate`. Uses Intl
 *  formatToParts to read the zone's wall-clock, then differences it against UTC. */
export function tzOffsetMs(tzid: string, utcDate: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tzid, hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const p: Record<string, string> = {};
  for (const part of dtf.formatToParts(utcDate)) p[part.type] = part.value;
  let hour = Number(p.hour);
  if (hour === 24) hour = 0; // some engines render midnight as 24
  const asUTC = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), hour, Number(p.minute), Number(p.second));
  return asUTC - utcDate.getTime();
}

/** Wall-clock time in `tzid` → the UTC instant. Two-pass to land DST transitions
 *  correctly. Returns null if the TZID is unknown (Intl throws). */
export function zonedWallToUTC(y: number, mo: number, d: number, h: number, mi: number, s: number, tzid: string): Date | null {
  try {
    const guess = Date.UTC(y, mo - 1, d, h, mi, s);
    let utc = guess - tzOffsetMs(tzid, new Date(guess));
    utc = guess - tzOffsetMs(tzid, new Date(utc)); // refine across a DST edge
    return new Date(utc);
  } catch {
    return null;
  }
}

export interface ICSDate {
  iso: string;
  allDay: boolean;
}

/**
 * Parse a DTSTART/DTEND value + params into a UTC ISO instant.
 *   • VALUE=DATE "YYYYMMDD"            → all-day → UTC midnight of that date
 *                                        (the app's server all-day convention,
 *                                        identical to google-sync's interval()).
 *   • "YYYYMMDDTHHMMSSZ"               → exact UTC instant.
 *   • TZID=Zone; "YYYYMMDDTHHMMSS"     → wall time resolved through the zone → UTC.
 *   • floating "YYYYMMDDTHHMMSS"       → no tz on the server → read as UTC.
 */
export function parseICSDate(value: string, params: Map<string, string>): ICSDate | null {
  const m = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
  if (!m) return null;
  const [, y, mo, d, hh, mi, ss, z] = m;
  const isDate = params.get("VALUE") === "DATE" || !hh;
  if (isDate) {
    return { iso: `${y}-${mo}-${d}T00:00:00.000Z`, allDay: true };
  }
  if (z === "Z") {
    return { iso: new Date(`${y}-${mo}-${d}T${hh}:${mi}:${ss}Z`).toISOString(), allDay: false };
  }
  const tzid = params.get("TZID");
  if (tzid) {
    const inst = zonedWallToUTC(Number(y), Number(mo), Number(d), Number(hh), Number(mi), Number(ss), tzid);
    if (inst) return { iso: inst.toISOString(), allDay: false };
  }
  // Floating: no Z, no (valid) TZID. The server has no per-user tz — read as UTC.
  return { iso: new Date(`${y}-${mo}-${d}T${hh}:${mi}:${ss}Z`).toISOString(), allDay: false };
}

export interface VEvent {
  uid?: string;
  summary?: string;
  description?: string;
  location?: string;
  url?: string;
  dtstart?: ICSDate | null;
  dtend?: ICSDate | null;
}

/** ICS text → the VEVENTs it contains (only the fields Canvas / generic feeds populate). */
export function parseICS(raw: string): VEvent[] {
  const events: VEvent[] = [];
  let cur: VEvent | null = null;
  for (const line of unfold(raw)) {
    if (line === "BEGIN:VEVENT") { cur = {}; continue; }
    if (line === "END:VEVENT") { if (cur) events.push(cur); cur = null; continue; }
    if (!cur) continue;
    const p = parseLine(line);
    if (!p) continue;
    switch (p.name) {
      case "UID":         cur.uid = p.value.trim(); break;
      case "SUMMARY":     cur.summary = unescapeText(p.value); break;
      case "DESCRIPTION": cur.description = unescapeText(p.value); break;
      case "LOCATION":    cur.location = unescapeText(p.value); break;
      case "URL":         cur.url = p.value.trim(); break;
      case "DTSTART":     cur.dtstart = parseICSDate(p.value, p.params); break;
      case "DTEND":       cur.dtend = parseICSDate(p.value, p.params); break;
    }
  }
  return events;
}

// ── Course → project routing (ports the client matcher, a0e36ac) ────────────────

export interface Project {
  id: string;
  space_name: string;
  name: string;
  code: string | null;
  canvas_course: string | null; // explicit course link (0032); overrides code/name match
}

/** normalize a course code the way the client matcher did: strip whitespace, uppercase. */
export function normalizeCode(s: string): string {
  return s.replace(/\s+/g, "").toUpperCase();
}

/** Split a Canvas SUMMARY "Title [COURSE CODE]" into a clean title + the bracket. */
export function extractCourse(summary: string): { title: string; code: string | null } {
  const m = summary.match(/\s*\[([^\]]+)\]\s*$/);
  if (!m || m.index === undefined) return { title: summary.trim(), code: null };
  return { title: summary.slice(0, m.index).trim(), code: m[1].trim() };
}

/** Match a bracket course label to a project. An explicit user link (0032:
 *  projects.canvas_course, set from this same feed label in the Mac class picker)
 *  wins outright; otherwise the auto match — code first (normalized), then exact
 *  name. The explicit link is how a course whose bracket matches no code/name still
 *  files under the right class. */
export function matchProject(label: string | null, projects: Project[]): Project | null {
  if (!label) return null;
  for (const p of projects) {
    if (p.canvas_course && p.canvas_course === label) return p; // explicit user link
  }
  const nc = normalizeCode(label);
  const nn = label.toLowerCase().trim();
  for (const p of projects) {
    if (p.code && normalizeCode(p.code) === nc) return p; // primary: code
  }
  for (const p of projects) {
    if (p.name.toLowerCase().trim() === nn) return p;       // secondary: exact name
  }
  return null;
}
