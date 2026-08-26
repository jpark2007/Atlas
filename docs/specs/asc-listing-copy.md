# App Store Connect — iOS 1.0 listing copy (paste-ready)

Rewritten 2026-08-26 after Canvas was removed from iOS. The previous draft promised
Canvas on iPhone and named the wrong review account — both were rejection risks.

---

## Subtitle (30 max)
```
Your semester, in one place
```
*(27 chars. Alternates: `Classes, deadlines, calendar` (28) · `School, calendar, and tasks` (27))*

---

## Promotional Text (170 max)
```
Type or say what's on your mind and Atlas sorts it into your calendar, your classes, and your task list. Your semester, without the spreadsheet.
```

---

## Description (4,000 max)
```
Atlas is a planner for students that keeps your calendar, your classes, and everything you owe
in one place.

CAPTURE, DON'T ORGANIZE
Type or say what's on your mind — "chem lab writeup due friday, gym at 5" — and Atlas sorts it
out: what's an event, what's a task, which class it belongs to, when it's due. Fix anything it
got wrong with a tap on a chip. Your draft is saved as you type, so nothing is lost if you get
interrupted.

BUILT AROUND YOUR SEMESTER
Set up a term once and your classes hang off it, with meeting times, rooms, assignments and
notes in one place per class. Scan a syllabus from your camera roll and Atlas reads the dates,
the grade weights and the late policy off it. If your school publishes a calendar link, connect
it and your classes fill themselves in.

ONE CALENDAR, NOT FOUR
Connect Google Calendar and your events sync both ways. Add Apple Calendar to see everything
side by side. Deadlines are shown as deadlines, not as blocks that pretend the work is done —
and anything late is pinned, in amber, until you actually handle it.

NOTES THAT KNOW WHERE THEY BELONG
Keep lecture notes with the class they came from, so what you wrote in week three is still one
tap from the exam in week ten.

WIDGETS AND NOTIFICATIONS
See what's next on your home screen or lock screen, or your whole week at a glance. Get a daily
digest, event reminders, and nudges for what's overdue — each one switchable.

Atlas is free while we're building it. Your data is yours: never sold, never used for
advertising, and deletable from Settings at any time.
```

**Changed from the old draft:** the line "Canvas and any other school calendar connect by link"
is gone (Canvas setup is Mac-only now). Added rooms, the syllabus detail, and a Notes section —
Notes is a whole tab that the old copy never mentioned.

---

## Keywords (100 max, no spaces after commas) — 98 chars
```
student,planner,calendar,school,classes,syllabus,assignments,tasks,notes,deadlines,semester,due
```
*(dropped `canvas` — do not advertise what iOS no longer does)*

---

## URLs / misc
- **Support URL:** `https://www.atlaslm.net/support.html`
- **Marketing URL:** `https://www.atlaslm.net`
- **Copyright:** `2026 Andrew Khalil`
- **Version:** `1.0`
- **Release:** Manually release this version *(you choose the moment)*

---

## App Review Information

**Sign-In required:** YES
```
User name:  apple.review@atlas-test.dev
Password:   AtlasReview!2026
```
This account is seeded with a full Fall 2026 semester. **Keep it forever** — every future
update is re-reviewed, and a dead demo login is an instant rejection.

**Notes (4,000 max):**
```
Atlas is a student planner for calendar, tasks, notes and coursework.

Sign-in is required — please use the account provided above. It is seeded with a full semester
(five classes, coursework, notes and events) so the app is populated on first launch.

Google Calendar and Apple Calendar connections are OPTIONAL and are not needed to review the
app. Every core feature — capture, calendar, tasks, classes, notes and widgets — works on the
provided account without connecting anything.

Suggested walkthrough:
1. Sign in with the credentials above.
2. Schedule tab — the day's classes, with anything overdue pinned in amber at the top. The
   calendar icon at the top right opens the month view.
3. Capture tab — type "problem set 4 due friday" and tap Sort. The result appears as a card
   with Class / Type / Due chips you can correct before saving.
4. Tasks tab — work grouped by space or by due date. The School section lists the five classes
   with a count of open work; tapping one opens that class, its meeting times and rooms, its
   assignments and its notes.
5. Notes tab — lecture notes, each attached to the class it belongs to.
6. Settings (gear icon, top right) — Account, Calendars, Capture & Tasks, Notes & Files, App &
   Help. Account deletion is under Account.

Voice capture uses on-device speech recognition and requests microphone permission. Apple
Calendar access is requested only if the reviewer chooses to connect it. Neither is required.
```

**Changed from the old draft:** the reviewer account is now `apple.review@atlas-test.dev` (the
old draft still named the Google verification account), every Canvas mention is gone, and the
walkthrough matches the seeded Biology-major data rather than the old placeholder classes.

---

## App Privacy — verified against the code (zero third-party SDKs; only supabase-swift)
- **Data used to track you:** None
- **Data linked to you:** Contact Info (email, for the account) · User Content (tasks, events,
  notes the user creates) · Identifiers (user ID)
- **Data not linked to you:** none
- All collected for **App Functionality** only.

## Other
- **Age rating:** 4+ — no objectionable content, no user-to-user sharing on iOS
- **Export compliance:** already declared (`ITSAppUsesNonExemptEncryption: false` in the plist)
- **Price:** Free, no IAP, all territories
