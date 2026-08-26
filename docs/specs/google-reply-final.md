# The Google reply — final, paste-ready

Reply **directly in the Aug 4 thread** (`api-oauth-dev-verification-reply+1sk56t206k3fs1d@google.com`).
Send **only after** the console is saved and submitted — they read console state at reply time.

Swap `[LINK]` for the unlisted YouTube URL. Nothing else needs editing.

---

Hello,

Following up on your August 4 message regarding project atlas-500710. We have re-recorded the
demonstration video and addressed the branding findings.

**Video (unlisted):** [LINK]

- **Consent screen:** shown at 0:32 with all requested scopes expanded and readable on screen.
- **In-app functionality — `calendar.readonly`:** at 1:04, Atlas lists the connected account's
  calendars so the user chooses which ones sync. Without this scope Atlas cannot enumerate
  calendars and the user is limited to their primary calendar only.
- **In-app functionality — `calendar.events`:** demonstrated end to end — an event created and
  edited at 1:36, and deleted at 2:30.
- **Source account impact:** those changes are shown in Google Calendar itself — the event and
  its note at 2:07, and the emptied slot after deletion at 2:42.
- **`drive.file`:** this scope is visible on the consent screen in the video. Your August 4
  message asked for in-app demonstrations of the two calendar scopes, so the video focuses on
  those; we are glad to record a `drive.file` walkthrough as well if you would like one.

**Scopes:** the application and the Cloud Console both request exactly
`https://www.googleapis.com/auth/calendar.events`,
`https://www.googleapis.com/auth/calendar.readonly`, and
`https://www.googleapis.com/auth/drive.file`.
`https://www.googleapis.com/auth/documents` has been removed from both. Document editing works
entirely under `drive.file` via the Google Picker.

**Branding:** we have also addressed the branding findings. The application is now named
"Atlas Life Manager" on the OAuth consent screen, matching the name shown on our homepage at
https://www.atlaslm.net, and the logo has been updated to our own mark — the same one used in
the site header and favicon. It does not resemble or reference any other brand.

**Test credentials and navigation:**
- Download: https://www.atlaslm.net — Atlas.dmg (notarized; drag to Applications)
- Atlas account: `google.oauth.review@atlas-test.dev` / `AtlasReview!2026`
- Steps: open Atlas → sign in with the credentials above → Settings (⌘,) → Calendars →
  "Add a Google account…" → complete Google consent → click the connected account's row to see
  its calendar list. Create an event on any day in the calendar view to see it written to the
  connected Google Calendar.

There are no authentication blockers on the test account — no phone verification, no payment
requirement. Atlas is a native macOS app; the publishing status remains In Production.

Please let us know if anything further is needed.

Best,
Andrew Khalil — Atlas
