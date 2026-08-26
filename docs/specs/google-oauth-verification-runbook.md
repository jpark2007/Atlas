# Google OAuth Verification — Everything Left, In Order

**Project:** `atlas-500710` (number 450945006140) · **Status:** one deliverable left — the demo video.
**Thread:** replies go to `api-oauth-dev-verification-reply+1sk56t206k3fs1d@google.com` (may land in spam).

---

## Where this actually stands

Four rounds so far:

| Date | What happened |
|---|---|
| Jul 28 | Automated compliance checklist. |
| Jul 30 | You replied: 4 scopes declared, added `calendar.readonly` to the console, linked the old video. |
| Aug 1 | Three findings: (1) re-record the video, (2) send test credentials, (3) drop `documents` for `drive.file`. |
| Aug 4 | **Only the video.** Names `calendar.events` and `calendar.readonly`. Says nothing about `documents` or Drive. |

**Read this correctly: the scope fight is won.** The Aug 4 email dropping the `documents` pushback means the narrowing was accepted. What's left is a video that proves the two calendar scopes are necessary.

Why the last video failed: you replied to the Aug 1 email *without* a new video, so the reviewer re-watched the old one and re-issued the same finding. There is no shortcut here — the reply must carry a new video link.

### Already verified in code (nothing to do)

- `Atlas/Services/GoogleAuthService.swift:32-34` requests exactly `calendar.events`, `calendar.readonly`, `drive.file`. `documents` is gone and committed.
- `landing/downloads/Atlas.dmg` is v0.10.0, notarized, and contains **zero** `auth/documents` strings — verified by inspecting the shipped binary. The reviewer downloads from the site and gets a build that matches the console.
- `privacy.html` is live and covers all five disclosure bullets plus the Limited Use statement.
- No restricted scopes remain → **CASA does not apply.**

---

## Step 0 — Console audit (5 min, do this first)

Cloud Console → APIs & Services → **Data Access**, project `atlas-500710`.

- [ ] Exactly three scopes listed: `calendar.events`, `calendar.readonly`, `drive.file`.
- [ ] **If `documents` is still there, remove it.** Your Jul 30 reply told them four scopes. Criterion "Scope Matching" fails if the console lists a scope the app no longer requests — no video can save that.
- [ ] Publishing status stays **In Production**. Do not create a new Cloud project — that restarts verification from zero.
- [ ] Save and submit any change.

---

## Step 1 — Prep (20 min, before recording)

**Account decision (final): record on your own account; hand Google their own.** The video
shows your real Atlas + Google account, and the reply hands the reviewer the separate test
account to poke at themselves. That's fine — Google's requirement is that the credentials
*work*, not that they're the ones on camera. Two consequences to respect:

- Your real calendar and school data are on screen for a reviewer to watch. Close anything
  you'd rather not show and pick a demo day that isn't full of personal detail.
- The test account you hand them must reach the same features the video shows, or they'll
  come back saying they couldn't reproduce it.

- [ ] **Your Google account needs a second calendar.** In Google Calendar: *Other calendars → + → Create new calendar*, name it something obvious ("Gym", "Work"), add 2–3 events.
      This is the single thing the last video missed. `calendar.readonly` exists so Atlas can *list* your calendars; with only a primary calendar there is nothing on screen to justify the scope.
- [ ] **Sign into Atlas as yourself** for the recording.
- [ ] **Confirm the reviewer's account still works** before you send: `google.oauth.review@atlas-test.dev` / `AtlasReview!2026`. Sign into it once on the DMG build and make sure it lands in a usable app — an account that dead-ends is the same as no credentials.
- [ ] **Install from the site**, not from Xcode: www.atlaslm.net → Atlas.dmg → Applications. The reviewer downloads the same file.
- [ ] In Atlas → Settings → Calendars, **disconnect any connected Google account** so the consent screen is fresh on camera.
- [ ] QuickTime → New Screen Recording, full screen, mic on so you can narrate.

**One continuous take. No cuts, no stitching.** A stitched video reads as hiding something.

---

## Step 2 — Shot list

| # | Beat | What must be on screen |
|---|---|---|
| 1 | Atlas open, signed in. One line about what the app is. | — |
| 2 | Settings → Calendars → **"Add a Google account…"** | The click |
| 3 | Google consent screen → click **"Show all services"** so scopes expand → **hold still 5+ seconds**, read the three scopes aloud. | All three readable, expanded |
| 4 | Finish consent → the **"Name this Google account"** sheet → name it, pick a space, save. | — |
| 5 | **`calendar.readonly` proof.** Click the Google row → the account panel → **CALENDARS** section: "Choose which calendars sync into Atlas" listing *multiple* calendars. Show the same list in Google Calendar side by side. Uncheck one → it leaves Atlas → re-check it. | The multi-calendar picker. **This is the shot that was missing.** |
| 6 | **`calendar.events` — create.** Make an event in Atlas → switch to Google Calendar in the browser → it's there. | Source-account impact |
| 7 | **Edit.** Change its time or title in Atlas → Google Calendar → the change is reflected. | Source-account impact |
| 8 | **Delete.** Delete in Atlas → Google Calendar → it's gone. | Source-account impact |
| 9 | **Read direction.** Create an event in Google Calendar → back to Atlas → it appears. | — |
| 10 | **`drive.file`** (short — their email didn't ask, but it's a requested scope): open a project → link or create a Google Doc through the picker → show it round-trip. | — |

Steps 6–9 are the entire "maximum extent of user-facing features" criterion. Do each one fully. Don't narrate ahead of what's on screen.

---

## Step 3 — Upload

- [ ] YouTube, **Unlisted** (public also fine — never Private; Private is an automatic fail).
- [ ] Title it for the three scopes, e.g. *Atlas — Google OAuth Demo (calendar.events, calendar.readonly, drive.file)*.
      The old video is titled with four scopes including `documents` — do not reuse it or link it.
- [ ] Watch it back once. If the consent screen isn't readable at full size, re-record. That is the #1 rejection reason.

---

## Step 4 — The reply

Reply **directly to the Aug 4 email in that thread** (not a new message).

> Hello,
>
> Following up on your August 4 message regarding project atlas-500710. We have re-recorded the demonstration video addressing each criterion:
>
> **Video (unlisted):** [LINK]
>
> - **Consent screen:** shown with "Show all services" expanded, all requested scopes readable on screen.
> - **In-app functionality — `calendar.readonly`:** Atlas lists the connected account's calendars so the user can choose which ones sync into Atlas. The video shows this picker alongside the same calendar list in Google Calendar. Without this scope Atlas cannot enumerate calendars and the user would be limited to their primary calendar only.
> - **In-app functionality — `calendar.events`:** demonstrated end to end — an event created, edited, and deleted in Atlas.
> - **Source account impact:** each of those three changes is shown reflected in Google Calendar itself, including the deleted event no longer being present. Events created in Google Calendar are also shown appearing in Atlas.
> - **`drive.file`:** demonstrated by linking a Google Doc to an Atlas project.
> - **Scope matching:** the Cloud Console configuration and the application both request exactly `calendar.events`, `calendar.readonly`, and `drive.file`.
>
> **Scopes:** Confirming narrower scopes — `https://www.googleapis.com/auth/documents` has been removed from both the application and the Cloud Console. Document editing works entirely under `drive.file` via the Google Picker.
>
> **Test credentials and navigation:**
> - Download: https://www.atlaslm.net — Atlas.dmg (notarized; drag to Applications)
> - Atlas account: `google.oauth.review@atlas-test.dev` / `AtlasReview!2026`
> - Steps: open Atlas → sign in with the credentials above → Settings (⌘,) → Calendars → "Add a Google account…" → complete Google consent → click the connected account's row to see its calendar list. Create an event on any day in the calendar view to see it written to the connected Google Calendar.
>
> There are no authentication blockers on the test account — no phone verification, no payment requirement. Atlas is a native macOS app; the publishing status remains In Production.
>
> Please let us know if anything further is needed.
>
> Best,
> Andrew Khalil — Atlas

- [ ] Swap `[LINK]` for the real URL.
- [ ] The credentials above are the reviewer's account, not the one in the video — that's the
      decision, and the email doesn't need to explain it. Just make sure that account works.

---

## Step 5 — After sending

- [ ] Watch the **Verification Center** in Cloud Console — each requirement flips to reviewed there before any email arrives.
- [ ] Expect either an acknowledgement ("still reviewing") or a decision. Turnaround so far has been 2–4 days.
- [ ] **Do not** create a new Cloud project, change scopes, or remove the test account while the review is open.
- [ ] Keep `google.oauth.review@atlas-test.dev` alive until you have a written approval. Delete it only after.

## If it comes back again

Read exactly which criterion is named. The pattern across all four rounds: they re-state only what is still unmet. `documents` disappearing from the Aug 4 email is what tells you that fight ended.

- "Consent screen" named again → the scopes weren't legible at full size. Re-shoot step 3 with a longer hold.
- "In-app functionality" named again → a scope's demo wasn't convincing. For `calendar.readonly` that always means the multi-calendar picker.
- "Source account impact" named again → a write wasn't shown landing in Google Calendar itself.
- "Scope matching" named → the console still disagrees with the app. Back to Step 0.
