# Handoff — Google Verification + iOS App Store (2026-08-25, late)

**Status 2026-08-27: superseded.** iOS 1.0 was pulled from App Store review — 1.1 (with iPad
support, no longer iPhone-only) is now the launch build, see `docs/specs/v1.1-plan.md`. Google
OAuth verification is still pending; the privacy-policy fix referenced elsewhere was deployed
2026-08-27. Test counts and commit-state below are a historical snapshot, not current.

Written so a fresh session (or a fresh you, after a restart) can pick this up cold.
Two tracks run in parallel: **Google OAuth verification** and **iOS 1.0 submission**.

Companion docs:
- `docs/specs/google-oauth-verification-runbook.md` — the video + reply, end to end
- `docs/specs/google-branding-handoff.md` — the console-only branding steps

---

## State of the repo

Five commits on `main`, **local only, not pushed**:

| Commit | What |
|---|---|
| `63e0e7d` | iOS wave — class-tap nav, duplicate School, settings identity header, loaders/copy, capture cap, iPhone-only + iOS v1.0 |
| `968e622` | CORS fix + support page + dashboard reopen/delete |
| `64183c3` | Google verification runbook |
| `906d934` | Branding rename (site side) |

**Already deployed to production** (do not re-do): `support-request`, `waitlist`,
`track-download`, `admin-stats` edge functions; landing site (support page + branding rename).

Gates as of that state: Mac build ✅, iOS build ✅, AtlasCore 297 tests ✅, edge 154 tests ✅.

---

# TRACK 1 — Google OAuth verification

Project `atlas-500710` (number 450945006140). Thread:
`api-oauth-dev-verification-reply+1sk56t206k3fs1d@google.com` (may land in spam).

**Two open items — the demo video AND branding.** The Verification Center's "branding has been
verified" banner is stale; the Aug 4 review below it lists three open branding findings, and
verification does not complete while they're open.

## 1a · The video — DONE, awaiting upload

Merged file: **`~/Desktop/atlas-google-oauth-demo.mov`**, 2:52, four takes concatenated with
ffmpeg stream copy (no re-encode). Frame-verified against all four criteria:

| Their criterion | Where | Status |
|---|---|---|
| Consent screen, scopes expanded | 0:32 — the five-line access panel, readable | ✅ |
| In-app functionality · `calendar.readonly` | 1:04 — the picker listing 4 calendars | ✅ |
| In-app functionality · `calendar.events` | 1:36 create + edit, 2:30 delete | ✅ |
| Source account impact | 2:07 event + note in Google Calendar, 2:42 slot empty after delete | ✅ |

One object created → edited → deleted, with Google Calendar confirming each step.
`drive.file` demo was skipped deliberately — the Aug 4 email named only the calendar scopes,
and the consent panel still shows the Drive line on screen.

Recorded on Drew's own Google account (final decision); the reviewer gets the separate test
account in the reply.

### Upload it — YouTube, **Unlisted** (Private is an automatic fail)

Title:
```
Atlas — Google OAuth Demo (calendar.events, calendar.readonly, drive.file)
```

Description:
```
Demonstration video for Google OAuth API verification.
Project: atlas-500710 (Project Number 450945006140)
App: Atlas — a native macOS life manager (calendar, tasks, school).

Scopes requested by the app and configured in the Cloud Console:
• https://www.googleapis.com/auth/calendar.events
• https://www.googleapis.com/auth/calendar.readonly
• https://www.googleapis.com/auth/drive.file

What this video shows:
0:16 — Connecting a Google account from Atlas (Settings → Calendars)
0:32 — The OAuth consent screen with all requested scopes expanded and readable
0:48 — Naming the connected account and choosing where its events land
1:04 — calendar.readonly: Atlas lists every calendar in the account so the user
       chooses which ones sync. Without this scope Atlas cannot enumerate
       calendars and the user is limited to their primary calendar only.
1:36 — calendar.events: creating an event in Atlas, then editing it
2:07 — Source account impact: the event, and the note added in Atlas, shown in
       Google Calendar itself
2:30 — calendar.events: deleting that event in Atlas
2:42 — Source account impact: the event is gone from Google Calendar

Contact: drewkhalil@gmail.com
```

## 1b · Branding — site done, console pending

Decision: the product presents as **Atlas Life Manager** (matches atlaslm.net; "Atlas LM" was
rejected for reading as "language model"). In-app product name stays "Atlas" — Google only
compares the consent screen against the homepage.

Site side is **deployed**: wordmark lockup, titles, social card. Console steps are in
`google-branding-handoff.md` — app name, logo (`landing/assets/atlas-logo-120.png`), scope
check, URLs.

## 1c · Send the reply

Runbook Step 4 has the full email. Add the branding paragraph from the branding handoff.
**Console must be saved and submitted before the email** — they read console state at reply time.

## Order for track 1
Console name → logo → confirm 3 scopes → confirm URLs → upload video unlisted → send reply.

---

# TRACK 2 — iOS 1.0 App Store submission

App Store Connect record already exists: team **AtlasLM**, app **Atlas**, iOS 1.0, Prepare for
Submission. Bundle `com.atlaslm.AtlasMobile`, widgets `com.atlaslm.AtlasMobile.widgets`, app
group `group.com.atlaslm.mobile`.

## Decisions already made
- **iPhone only** for 1.0 (`TARGETED_DEVICE_FAMILY: "1"`). iPad would put a stretched phone UI
  in front of a reviewer.
- **iOS versions independently at 1.0** — the Mac stays on its own 0.10.x / Sparkle channel.
- **Free, no IAP, all territories.** No payment mentions anywhere in the iOS app (external
  payment links without the entitlement are a rejection).
- **Widgets ship**, but only after Drew reviews them on device.
- **A separate dedicated review account** — not Drew's, not the Google reviewer's — and it is
  **kept after approval** (every update is re-reviewed; a dead demo login is an instant reject).
- **TestFlight full pass before submitting.**

## 2a · Device pass — BLOCKING, Drew only

The five iOS fixes build clean but a green build proves nothing about UI. On a real iPhone:

- [ ] Tasks → tap a class row → it opens **that** class, and the back arrow works.
- [ ] Tasks shows School **once** — no second "SCHOOL" space group with per-class subsections.
- [ ] Settings opens with the identity header (avatar + your email) at the top; tapping it
      reaches sign-out and delete-account.
- [ ] Loading states show the Atlas loader (clay arc on a thin ring), not the gray pinwheel.
- [ ] School zero state and the wizard both say "Add your classes".
- [ ] A capture over 20,000 characters stops with "That's as much as one capture can hold".

Anything wrong here comes back to code before anything else proceeds.

## 2b · Screenshots

**The gotcha that broke the last attempt:** an iPhone 16 base shoots **1179×2556**, which is not
an accepted App Store size (6.5" wants 1242×2688 or 1284×2778; 6.9" wants 1290×2796). That's why
the earlier upload failed on the same phone.

**Plan:** Drew shoots at native 1179×2556, then they get **inset into a 1290×2796 canvas** with a
caption headline above each — no upscaling, no softness, and it reads as a designed store page.
(Alternative: sign into the iPhone 16 Pro Max simulator and shoot natively at 1290×2796.)

Five shots, in order — the first three carry the install sheet:
1. **Calendar / Today** with a Late group and due markers visible
2. **Capture** showing result chips (Class ▾ / Type ▾ / Due ▾)
3. **Class hub**
4. **Tasks** (after the duplicate-School fix)
5. **Widgets on a home screen** (after the widget review)

Drew's own data is on these by his decision.

## 2c · App Store Connect fields — copy is drafted, paste-ready

**Subtitle** (30 max) — pick one:
- `Your semester, in one place` (27) ← recommended
- `Classes, deadlines, calendar` (28)
- `School, calendar, and tasks` (27)

**Promotional text** (170 max):
```
Type what's on your mind and Atlas sorts it into your calendar, your classes, and your task
list. Your semester, without the spreadsheet.
```

**Description**:
```
Atlas is a planner for students that keeps your calendar, your classes, and everything you owe
in one place.

CAPTURE, DON'T ORGANIZE
Type or say what's on your mind — "chem lab writeup due friday, gym at 5" — and Atlas sorts it
out: what's an event, what's a task, which class it belongs to, when it's due. Fix anything it
got wrong with a tap on a chip. Your draft is saved as you type, so nothing is lost if you get
interrupted.

BUILT AROUND YOUR SEMESTER
Set up a term once and your classes hang off it, with meeting times, assignments and notes in
one place per class. Scan a syllabus from your camera roll and Atlas pulls the dates out of it.
Canvas and any other school calendar connect by link.

ONE CALENDAR, NOT FOUR
Connect Google Calendar and your events sync both ways. Add Apple Calendar to see everything
side by side. Deadlines are shown as deadlines, not as blocks that pretend the work is done —
and anything late is pinned, in amber, until you actually handle it.

WIDGETS AND NOTIFICATIONS
See what's next on your home screen or lock screen. Get a daily digest, event reminders, and
nudges for what's overdue — each one switchable.

Atlas is free while we're building it. Your data is yours: never sold, never used for
advertising, and deletable from Settings at any time.
```

**Keywords** (100 max, no spaces after commas) — 98 chars:
```
student,planner,calendar,school,classes,syllabus,assignments,tasks,notes,canvas,deadlines,semester
```

**Support URL**: `https://www.atlaslm.net/support.html` (built and live this session)
**Marketing URL**: `https://www.atlaslm.net`
**Privacy Policy URL**: `https://www.atlaslm.net/privacy.html`
**Copyright**: `2026 Andrew Khalil`
**Version**: `1.0` · **Release**: manually release after approval (recommended — you choose the
moment rather than being surprised)

**App Review Information → Notes**:
```
Atlas is a student planner for calendar, tasks, notes and coursework.

Sign-in is required — please use the account provided above. It is seeded with classes, tasks
and events so the app is populated on first launch.

Google Calendar and Canvas connections are OPTIONAL and not needed to review the app. All core
functionality (capture, calendar, tasks, classes, notes, widgets) works on the provided account
without connecting anything.

Suggested walkthrough:
1. Sign in with the credentials above.
2. Capture tab — type "essay draft due friday" and tap Sort. The result appears as a card with
   Class / Type / Due chips you can correct.
3. Schedule tab — the day's events, deadlines shown as due markers, and anything late pinned
   at the top.
4. Tasks tab — open work grouped by space or by due date. The School section at the top lists
   classes; tapping one opens that class.
5. Settings — Account, Calendars, Capture & Tasks, Notes & Files, App & Help. Account deletion
   is under Account.

The app uses on-device speech recognition for voice capture (microphone permission) and reads
Apple Calendar if the user grants access. Neither is required to review.
```

**App Privacy (nutrition labels)** — verified against the code: the app has **zero** third-party
SDKs (only `supabase-swift`). No analytics, no trackers, no ad frameworks.
- Data used to track you: **None**
- Data linked to you: **Contact Info** (email address, for account), **User Content** (tasks,
  events, notes the user creates), **Identifiers** (user ID)
- Data not linked to you: none
- All of it is collected for **App Functionality** only.

**Age rating**: 4+ — no objectionable content, no user-generated content shared between users
(there is no user-to-user sharing anywhere in the iOS app; collaboration is Mac-side only).

**Export compliance**: already declared in the plist (`ITSAppUsesNonExemptEncryption: false`).

## 2d · The review account

Create `apple.review@atlas-test.dev` (or similar), seed it with a term, a few classes, tasks
with due dates, and a handful of events so App Review opens a populated app — an empty state
invites a "placeholder content" rejection. Needs Drew's go-ahead since it writes to prod.
**Keep it forever.**

## 2e · Archive → TestFlight → submit

1. `xcodegen generate` (project.yml already carries iPhone-only + 1.0)
2. Xcode → scheme AtlasMobile → Any iOS Device → **Product → Archive**
   (requires Drew's signing identity — cannot be done headless)
3. Organizer → **Distribute App → App Store Connect → Upload**
4. **One upload, two uses:** that build feeds both TestFlight and App Store review. There is no
   separate "upload for the store" step.
5. TestFlight internal → Drew's full pass on a real device
6. Attach the build to the 1.0 version in ASC, fill everything in 2c, **Add for Review**

## Order for track 2
Device pass → screenshots → seed review account → fill ASC → archive → upload → TestFlight pass
→ submit.

---

## Open questions for Drew

1. Subtitle — which of the three?
2. Go-ahead to create and seed the `apple.review` account in prod?
3. ASC fields — should the next session drive Playwright through the Prepare-for-Submission page
   while you're logged in, or do you want to paste the copy above yourself?
4. Push the five local commits?

## Useful commands

```bash
# gates
xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Atlas.xcodeproj -scheme AtlasMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
cd AtlasCore && swift test
deno test supabase/functions/_shared/

# deploys (already done this session — for reference)
supabase functions deploy <name> --no-verify-jwt
cd landing && vercel --prod
```
