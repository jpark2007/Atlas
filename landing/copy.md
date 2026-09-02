# Atlas — Landing Page Copy

Voice: plain, second person, concrete. Every headline names an outcome. No
section body runs past three lines at 1280. The page describes what the app
does today — nothing here promises a feature that isn't built.

Rules the page holds to: one accent (clay), one type pair (Fraunces + Nunito),
one CTA verb ("Download"), and the word "free" exactly once. Never call the
apps unfinished or pre-release — they are shipped.

---

## Nav

Features · Why we built it · Download

---

## Hero

**Kicker:** FOR MAC, IPHONE & IPAD

**Headline:**
Your life doesn't fit in six apps. *It fits here.*

**Subhead:**
Atlas is a student planner. Your classes, deadlines, and calendars all live on
one timeline, on every device you own.

**CTAs:** Download for Mac · Apple's "Download on the App Store" badge
**Hint under them:** Free · macOS 14 or later

**Image:** the Mac dashboard in a MacBook, with the iPhone today view standing
in front of its right third and breaking past the base. On a phone the Mac shows
a crop — the clock and the late banner — and the iPhone stays in front of it.

---

## Feature sections

Each is one screenshot, one outcome headline, and at most three lines.

### 1 — One timeline

**Kicker:** ONE TIMELINE
**Headline:** Every calendar you already use, in one day.

Apple Calendar, Google, and Canvas each hold part of your week. Atlas draws them
on the same grid, and Google edits sync both ways.

**Image:** the day view, with three source pills — Canvas, Apple Calendar,
Google — pinned by a leader line to three real events, so the claim is visible
rather than asserted. The pills are an illustration of where a week comes from;
they are annotations on the page, not labels the app draws. Two of the three
show on a phone.

### 2 — Plan the day

**Kicker:** PLAN THE DAY
**Headline:** Drag a task onto your day and it's scheduled.

Anything without a time waits in the Unscheduled tray. Drop one on an open hour
and Atlas books the work session for you.

**Image:** the day view beside the Unscheduled tray. On a phone, a crop of the
tray itself — the "Drag one onto the grid" line, the overdue chips — against a
strip of the grid.

### 3 — Class hub

**Kicker:** CLASS HUB
**Headline:** Scan a syllabus, get the whole class.

Atlas reads meeting times, grading weights, and course policies off the PDF,
then files every Canvas assignment underneath them.

**Image:** a class page built from a scanned syllabus. On a phone, a crop of
the title, the Canvas course, the meeting times, and the grading percentages.

---

## Capture (the animated demo)

**Kicker:** CAPTURE
**Headline:** One sentence becomes three things in your week.

Type it the way you'd say it. Atlas reads the class, the due date, and the
repeat, then files each piece where it belongs.

**Button:** Replay

**The demo** is CSS and `main.js` — no video, no GIF. A capture box types
"chem lab report due friday, gym tue and thu at 7, call advisor about spring
classes", holds a beat on "Atlas is sorting…", then the sentence dims and three
filed rows slide in:

- Chem lab report — General Chemistry · Deadline · Fri
- Gym — Personal · Repeats · Tue & Thu · 7:00 AM
- Call advisor about spring classes — Personal · To do · No date

It runs once when it scrolls into view; Replay restarts it. Under reduced motion
(or with JS off) the rows and the finished sentence are already in the markup, so
the section renders as its own end state and the Replay button never appears.

---

## And from your phone

**Heading:** And from your phone, on the walk back.

**Image:** three iPhone screens — capture sorted, today, tasks by class. On a
phone they become a swipeable strip: one screen nearly full width with the next
peeking, scrolling inside the strip rather than the page.

---

## Menu bar (the page's one ink block)

**Kicker:** MENU BAR
**Headline:** Check the whole day without opening the app.

The month and today's list sit behind the menu-bar icon, with Quick Capture
right there.

**Image:** the menu-bar popover, cropped to itself, with two callouts and
nothing else:

- A leader line into today's list: "Every calendar from every space, in one list"
- Keycaps `⌥` `Space` labelled "Quick Capture from any app". That is the app's
  real global hotkey (`HotkeyDefaults` in `Atlas/Services/HotkeyService.swift`) —
  if it ever changes, change it here too.

---

## Why we built it

**Kicker:** WHY WE BUILT IT
**Signature:** Two students, one app
**Byline:** Two students, one app

**Pull line:** We wanted *one place that holds all of it* and does the filing.

Our own week was spread across a calendar, a to-do app, Canvas, and a pile of
notes that never talked to each other. We use Atlas every day and fix whatever
gets in the way that week.

---

## Download

**Kicker:** GET ATLAS

**Heading:** Atlas is out on Mac, iPhone, and iPad.

**Supporting line:** No invite, no waiting. Download the Mac app, or get it on
the App Store for iPhone and iPad, and start today.

**Buttons:**
- Mac: Download for Mac → `/downloads/Atlas.dmg` (Sparkle handles updates after)
- iPhone & iPad: Apple's badge →
  https://apps.apple.com/us/app/atlas-student-planner/id6786719011

**Beside them:** the App Store QR, captioned "Scan to get it on iPhone or iPad".
Desktop only — a phone just taps the badge.

**Note under the pair:** Requires macOS 14 or later.

---

## Footer

- Atlas — a planner for Mac, iPhone, and iPad.
- Two students, one app.
- drewkhalil@gmail.com
- Support · Privacy · Terms · Compare · Owners
- © 2026 Atlas

---

## Notes for whoever edits the page

- Links are root-absolute (`/#features`, `/privacy.html`) so the same nav and
  footer markup works on every page in the site.
- Both download buttons are live links: the Mac DMG and the App Store listing.
- No email form on the home page. The support page keeps its own.
- Don't add features that aren't shipped. Social/sharing, Google Drive, the
  focus timer, and auto-scheduling suggestions are roadmap, not product.
- Copy tics to keep out: triplet lists, negation-then-reveal sentences, em-dash
  cadence, the same idea said twice in two paragraphs, and any word that frames
  the apps as unfinished or pre-release.
