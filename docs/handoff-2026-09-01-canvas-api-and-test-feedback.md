# Handoff — Canvas API deep-sync idea + Drew's live-test feedback (2026-09-01, afternoon)

Raw capture of Drew's feedback while testing the density/syllabus batch (built earlier today —
see `docs/handoff-2026-09-01-mac-density-syllabus.md` for that batch). Deliberately **not**
investigated or triaged — a new session picks this up, digs in, and plans. Screenshots referenced
are from Drew's 12:05–12:10 PM test run on the dev build with his real account.

---

## 1. Canvas API deep sync (the big idea)

**Motivation:** the Canvas ICS feed carries **date-only** due dates (proven today — it caused the
UTC-midnight bug). Atlas now renders them date-only, but the *exact* due time (e.g. 5:00 PM, not
11:59 PM) is simply absent from ICS. Assuming end-of-day "could fuck someone over." The Canvas
REST API has exact `due_at` timestamps, plus **announcements** (Drew wants to know when
announcements come in), points, submission status, and the syllabus page itself.

**Constraints from Drew:**
- Only worth doing if it works at the schools that matter — **specifically Rutgers and Princeton**
  (Jonah). Not interested in any per-school application/approval process.
- Model would be **per-student personal access tokens**, not an institutional developer key.
- **Rutgers finding:** Drew checked — token generation appears **administrator-restricted** on
  Rutgers Canvas ("shows as administrator restricted my ability to make a key"), so a student
  token may not be obtainable there. Needs verification: exact wording/place he saw it, whether
  it's the "+ New access token" button on /profile/settings, and whether Princeton allows it.
- Acceptable fallback: keep ICS as the base layer; API is an optional "connect deeper" upgrade
  where a token can be generated. If Rutgers truly blocks student tokens, the idea may be dead
  for Drew's own account — decide after verifying.
- Prior discussion in the earlier /btw aside reached the same shape: **park as a spec'd follow-up
  ("Canvas API deep sync — personal token, optional, ICS fallback")** — this doc is that parking spot.

## 2. Dashboard "Due Today" rows don't say which class

Screenshot: Due Today section shows "Introduction, Prerequisites review — No time planned" with
only the space's green dot. Drew: "besides saying no time planned ik u have green dot. but tell
me what class it is." → Due Today rows need the class chip/name like Today's Focus rows have.
(They were Calc I tasks.)

## 3. Class-page EVENTS section is a flat unscoped dump

Screenshot: Calc I class page, "EVENTS 18" — Quiz 1…9, Midterm Exam #1… each on its own card,
all reading "12 AM · 1h". Two asks:
- **Scope events like tasks are now scoped** — either collapse into the same This week /
  Rest of September / October… folds, or merge events INTO those folds alongside tasks ("when u
  see this week u see events and or tasks for this week… same for rest of september etc").
  Drew asked "that makes sense?" — direction confirmed by him, exact form open.
- **"12 AM · 1h" rendering:** syllabus-committed exam/quiz events sit at midnight with a default
  60-min duration (SyllabusDraft default). Reads as garbage. Likely wants all-day/date-only
  treatment for events whose source had no time (same philosophy as the task fix), or at least
  not "12 AM".

## 4. Re-scan UX + no clean delete of a previous scan (the 200% bug)

Screenshot: Calc I Grading header shows **200%** and Office Hours still shows the hallucinated
"Tue 2–4pm, Rm 312" from the OLD scan.
- Drew did **not** re-upload; the 200% is the old scan's six weights **plus** a newer commit's
  weights stacked in `class_info` — "thats bc we dont have a clean way to delete."
- Needs: a visible way to **replace/clear a previous scan's contribution** (meeting pattern,
  class info, and its created tasks/events) — re-scan should offer "replace what the last scan
  added" instead of stacking. Note the earlier handoff (C8) asked "should a scan ever overwrite
  meeting_pattern outright?" — this is the same family: neither silent overwrite nor silent
  stacking; show a diff/choice.
- Also answer surfaced during testing: rescan entry point = class page → "Scan a syllabus."
  Old hallucinated office-hours string still lives in prod `class_info` for Calc I — cleanup
  needed (new prompt prevents new ones, doesn't fix stored data).

## 5. "Read all 6" / class-info **Edit** opens a bare square textbox

Drew: "read all 6 or edit on there should be cleaner again popup not j square textbox."
The 4C cards shipped today, but the detail/edit surfaces behind them (`ClassInfoSheet`, the
class-info editor) are still the plain sheet with raw text boxes. Redesign those to match the
new card language (clean popup, structured rows).

## 6. Syllabus meetings × already-imported ICS schedule: auto-match the section

If a class's schedule was already imported (semester-wizard ICS / existing MEETS blocks), a later
syllabus scan that returns multiple sections should **match against the existing schedule and
pre-pick the student's section automatically** (e.g. existing Tu 2:00 block ⇒ that's his
recitation), instead of asking or importing all. Manual picker stays as fallback.

## 7. New intake type: teacher-posted **course schedule** documents

Drew has an example in `~/Downloads` — a General Psychology schedule the professor posted
(separate from the syllabus). Asks:
- A place/affordance to add a **schedule document** per class (alongside syllabus scan).
- The parser must handle that format — including "general calendar month view kinda" layouts
  (grid/calendar-shaped schedules, not just tables/lists).
- **Non-negotiable, same rule as syllabus dedupe:** importing a schedule must never duplicate
  items that already exist from Canvas or a prior syllabus scan — "it should be aware and
  conscious of that when adding items and that's the benefit of ai." The SyllabusDedupe matcher
  from today's batch is the natural reuse point.

## 8. Working notes from the same test run (context, no action decided)

- The new 3-step review wizard DID render for the General Chemistry scan (screenshot: Meetings
  step, 8 editable rows with section labels + day pills) — the paste/PDF intake and wizard are live.
- "1 new course found — Canvas is sending items Atlas has no class for" banner still showing in
  the sidebar during all of this (untriaged; may be the ACCP/other feed item).
- Dashboard Today's Focus correctly shows Canvas tasks date-only (Sep 9) next to syllabus tasks
  at 11:59 PM — the all-day fix verified live.

## Suggested next-session order (loose, Drew hasn't prioritized)

1. Quick wins: #2 class chip on Due Today; #3 events scoping + "12 AM" rendering.
2. #4 scan replace/clear semantics + prod cleanup of Calc I class_info (200%, fake office hours).
3. #5 class-info popup redesign.
4. #6 section auto-match from existing schedule.
5. #7 schedule-document intake (new scan type; reuse dedupe).
6. #1 Canvas API deep sync — verify Rutgers/Princeton token availability FIRST; it gates everything.
