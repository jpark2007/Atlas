# Calendar Write-Back — Plan & Status

**What this is:** events you create in Atlas can mirror to your real Google
Calendar (Atlas → Google), correctly and under your control. Status below.

_Last updated: 2026-06-29. Code is **implemented, builds green, 220 tests pass** —
awaiting your live confirmation (see Tests)._

---

## Decisions (locked)

1. **Opt-in via a picker.** Settings → Calendars → **"New events go to"**:
   - **Atlas only** — events stay in Atlas (default).
   - **Atlas + Google** — events also push to your Google Calendar.
   - *(Apple as a destination is a later build — EventKit write.)*
2. **Atlas is always the source of truth.** "Atlas + Google" *mirrors* a copy to
   Google; the Atlas copy never disappears. There is no Google-only mode.
3. **No duplicates.** The Google event id is now **persisted**, so editing an event
   after an app relaunch **patches** the same Google event instead of creating a
   second copy.
4. **No double-display.** An Atlas event you pushed to Google is de-duped on read,
   so it shows once (native), not twice (native + read-only Google copy).
5. **Scope:** your **primary** Google calendar only (multi-calendar = later).

## Storage model (how it works)

- **Your Atlas events** live in Supabase (source of truth). If "Atlas + Google" is
  on, a copy is mirrored to Google and the returned `google_event_id` is stored.
- **External events** (Google/Apple reads) are **not stored** — pulled live for the
  visible window each time you open the calendar, held in memory only. Google is the
  source of truth for its own events; we don't warehouse them.
- Caching external events (with sync tokens + webhooks) is a **future** step, only
  needed when the iOS app, a server-side AI brain, or scale demands it.

## What changed in code

- `supabase/migrations/0003_events_google_event_id.sql` — adds `google_event_id`.
- `AtlasDB.EventRow` — maps `google_event_id` ↔ `CalendarEvent.googleEventId`.
- `AppState.shouldWriteBack` — gated on the picker (`calendar.main == "Google"`).
- `SettingsView` — picker is now **Atlas only / Atlas + Google**; stale
  "deferred (v2)" label replaced.
- `CalendarView` — de-dupes pushed events out of the external (read) pool.

## ⚠️ Required step before testing

Apply the new migration to your Supabase project (the persistence column must exist,
or event saves will silently fail):

```bash
supabase db push
# — or paste supabase/migrations/0003_events_google_event_id.sql into the
#   Supabase dashboard → SQL editor and run it.
```

## ✅ Two simple tests (please confirm on a real run)

**Test 1 — Events appear on Google.**
1. Settings → connect Google, set **"New events go to" = Atlas + Google**.
2. Create a new event in Atlas (⌘K → "New Event", or on the calendar grid).
3. Open Google Calendar (phone/web) → the event is there. ✅

**Test 2 — Edits patch, no duplicate (the persistence fix).**
1. With that event pushed, **quit and relaunch** Atlas.
2. Edit the event (change its title or time) in Atlas.
3. Check Google Calendar → the **same** event updated — **not** a second copy. ✅

_Bonus opt-out check: set "New events go to" = **Atlas only**, create an event →
it should **not** appear on Google._

## Deferred (not in this build)

- Apple Calendar write-back (EventKit write) → adds "Apple" to the picker.
- Choosing a non-primary Google calendar.
- Background/incremental sync + offline cache (sync tokens, `events.watch` webhooks).
