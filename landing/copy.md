# Atlas — Landing Page Copy

Voice: plain, confident, warm. Reads like a magazine intro, not an ad.
Everything below describes what the app does *today*. Nothing here promises a
feature that isn't built. Prelaunch beta, two students, Mac + iPhone.

---

## Hero

**Line (primary):**
Your life doesn't fit in six apps. It fits here.

**Subline:**
Atlas is a native Mac and iPhone app that gathers Apple Calendar, Google
Calendar, and Canvas into one timeline — then turns a plain-English brain-dump
into tasks and events, filed where they belong. Built by two students. In beta
now.

**Alternate hero lines** (if the primary reads too blunt in layout):
- One calendar for your whole life. Actually one.
- Everything you have to do, on a calendar that's finally yours.

---

## Feature moments

### 1 — Unified calendar

**Kicker:** ONE TIMELINE

Apple, Google, and Canvas each hold a piece of your week. Atlas keeps all of it
in a single native calendar — your classes, your meetings, the dentist, the
thing due Thursday — with Google changes flowing both ways, so an edit here is
an edit everywhere. You pick which calendar is your main one. Drag a task onto
an open hour and it's on the schedule.

### 2 — Capture

**Kicker:** SAY IT MESSY

You don't think in tidy rows, so don't type in them. Dump it the way it actually
comes out — "essay due Thursday, gym three times this week, call mom Sunday" — by
typing or just talking. Atlas reads it, splits it into tasks and events, and
files each one into the right part of your life. You see everything it made and
confirm before a single item lands. Nothing gets lost between your head and your
calendar.

### 3 — Spaces and projects

**Kicker:** SCHOOL STAYS SCHOOL

Your life isn't one long list. Atlas keeps it in Spaces — School, Personal,
whatever else you run — with Projects inside them. In School, your Canvas classes
show up as their own projects, assignments and due dates already in place. One
app, but the parts of your life don't bleed into each other unless you want them
to.

### 4 — The phone companion

**Kicker:** THE MOBILE FRONT DOOR

The Mac app is where you plan. The iPhone is for the moment a thought lands while
you're in line for coffee: open it, dump the thought, glance at what's next,
check something off. It's deliberately small — capture and glance, nothing to
get lost in. Whatever you add on your phone is waiting for you on the Mac.

---

## Why we built it

We're Andrew and Jonah — two students who got tired of running our lives across a
calendar, a to-do app, Canvas, and a pile of notes that never talked to each
other. Atlas is the thing we wanted and couldn't find: one place that holds all
of it and does the filing for us. We build it for ourselves first, which is the
whole point — we feel it the second it gets annoying, and we fix it. It's early
and it's honest work. We'd rather show you the real thing than a promise.

---

## Waitlist CTA

**Section heading:** Be an early one.

**Supporting line:** We're letting people in a few at a time. Leave your email and
we'll send the invite when it's your turn.

**Microcopy:**
- Button (default): Join the waitlist
- Button (sending): Adding you…
- Input placeholder: you@email.com
- Reassurance under form: No spam. One email, when it's ready.
- Success: You're on the list. We'll be in touch when it's your turn.
- Error (general): That didn't go through. Give it another try?
- Error (invalid email): Hmm, that doesn't look like an email. Mind checking it?

---

## Teaser download buttons (disabled — "coming soon")

Both buttons are visibly present but inactive before launch.

- Mac button label: Download for Mac
  - Sub-label / badge: Coming soon
- iPhone button label: Get it on iPhone
  - Sub-label / badge: Coming soon

**Optional caption under the pair:** In private beta with our first testers.
Waitlist first, apps next.

---

## Footer

- Atlas — a life manager for Mac and iPhone.
- Made by Andrew Khalil and Jonah Park.
- drewkhalil@gmail.com
- Privacy · Terms   (relative links: /privacy, /terms)
- In beta. Built in the open.
- © 2026 Atlas

---

## Notes for whoever builds the page

- All links relative (e.g. `/privacy`), no absolute domains — hosted later on a
  free subdomain.
- Both download buttons ship disabled with the "Coming soon" badge; they are
  teasers, not links.
- The waitlist form POSTs JSON `{ email }` to a Supabase edge function. Put the
  URL in one obvious const at the top of the page JS: `WAITLIST_ENDPOINT`.
  Handle success and error with the microcopy above; never leave the button in a
  stuck "Adding you…" state on failure.
- Do not add features to the copy that aren't in this doc. Social/sharing, email
  capture, Google Drive, focus timer, and auto-scheduling suggestions are on the
  roadmap, not in the app yet — keep them off the page.
