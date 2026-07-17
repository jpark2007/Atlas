/**
 * Atlas — Google calendarList helpers (per-calendar selection, 2026-07-17).
 *
 * Pure, network-free helpers shared by google-connect (enumerate + select) and
 * covered by google_calendars_test.ts. The actual calendarList.list fetch and the
 * DB upserts live in the edge function; these are the bits worth unit-testing.
 */

const GCAL_BASE = "https://www.googleapis.com/calendar/v3";

/** A calendar as we store it: id, display name, and whether it's the account primary. */
export interface CalendarEntry {
  calendarId: string;
  summary: string;
  isPrimary: boolean;
}

// The calendarList.list item fields we read.
interface GCalListItem {
  id?: string;
  summary?: string;
  summaryOverride?: string; // user's rename of a shared/subscribed calendar
  primary?: boolean;
  deleted?: boolean;
}

/**
 * Map a calendarList.list payload to our CalendarEntry rows. Drops entries with no
 * id or marked deleted; prefers the user's summaryOverride over the raw summary.
 */
export function parseCalendarList(payload: unknown): CalendarEntry[] {
  const items = (payload as { items?: GCalListItem[] })?.items ?? [];
  const out: CalendarEntry[] = [];
  for (const it of items) {
    if (!it.id || it.deleted) continue;
    out.push({
      calendarId: it.id,
      summary: (it.summaryOverride ?? it.summary ?? it.id).slice(0, 500),
      isPrimary: it.primary === true,
    });
  }
  return out;
}

/**
 * Diff the currently-selected calendar ids against the requested set. `toSelect` and
 * `toDeselect` list only the ids that actually change, so the caller resets sync
 * state / deletes events for the minimum set. `unchanged` is the intersection.
 */
export function diffSelection(
  current: Iterable<string>,
  requested: Iterable<string>,
): { toSelect: string[]; toDeselect: string[] } {
  const cur = new Set(current);
  const req = new Set(requested);
  const toSelect: string[] = [];
  const toDeselect: string[] = [];
  for (const id of req) if (!cur.has(id)) toSelect.push(id);
  for (const id of cur) if (!req.has(id)) toDeselect.push(id);
  return { toSelect, toDeselect };
}

/** Fetch the account's full calendar list (paged). Throws on a non-2xx. */
export async function fetchCalendarList(accessToken: string): Promise<CalendarEntry[]> {
  const entries: CalendarEntry[] = [];
  let pageToken: string | undefined;
  while (true) {
    const params = new URLSearchParams({ maxResults: "250", minAccessRole: "reader" });
    if (pageToken) params.set("pageToken", pageToken);
    const res = await fetch(`${GCAL_BASE}/users/me/calendarList?${params}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) throw new Error(`calendarList ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    for (const e of parseCalendarList(data)) entries.push(e);
    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
  }
  return entries;
}
