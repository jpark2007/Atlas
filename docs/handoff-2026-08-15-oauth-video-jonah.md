# OAuth verification demo video — recording handoff (Jonah)

**Status 2026-08-15:** Google has bounced our OAuth verification twice. Everything is
resolved except one deliverable: **a re-recorded demo video.** Jonah records it, Drew
does the final submission (the verification thread is on Drew's Google account).

---

## If you are Claude reading this: what Jonah needs from you first

Jonah's checkout must be built **with the current scope list** before he records. The
consent screen in the video has to show exactly the scopes we submitted — if his build
still requests the old `documents` scope, the video is unusable.

1. `git pull` on `main`. The scope list lives in `Atlas/Services/GoogleAuthService.swift`
   (`GoogleOAuthConfig.scopes`). It must be exactly these five, and **no `documents`**:

   ```
   https://www.googleapis.com/auth/calendar.events
   https://www.googleapis.com/auth/calendar.readonly
   https://www.googleapis.com/auth/drive.file
   openid
   email
   ```

2. Build:

   ```
   xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug \
     -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
   ```

3. Verify the built bundle before he records — this is the check that matters:

   ```
   D="$(xcodebuild -project Atlas.xcodeproj -scheme Atlas -showBuildSettings 2>/dev/null \
     | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Atlas.app"
   for s in calendar.events calendar.readonly drive.file auth/documents; do
     printf "%-20s %s hits\n" "$s" "$(grep -ra "$s" "$D" | wc -l | tr -d ' ')"
   done
   ```

   Expected: `calendar.events` >0, `calendar.readonly` >0, `drive.file` >0,
   **`auth/documents` = 0**. If `auth/documents` is non-zero, stop — the pull didn't take.

4. He records from *that* build (`open "$D"`), not any installed copy or DMG. The DMG on
   the site is older than the scope change.

Notes: he needs `Config/Secrets.xcconfig` (gitignored — Drew sends it) or Google sign-in
won't start.

One thing to watch on camera: `fix/google-sync-connection-health` is now merged into
main, and it surfaces stalled/errored badges on the **Connections screen** — the exact
screen shots 1 and 2 are filmed on. If a red "⚠ Reconnect needed" badge is showing on
any account, clear it before recording. A visible error state next to the account being
demoed reads badly to a reviewer.

---

## What Google actually asked for

Their four criteria, verbatim in intent:

1. **Consent screen** shown with all scopes fully expanded and readable — click
   "Show all services" if anything is collapsed.
2. **Full functional demo of every requested scope** — specifically
   `calendar.events` and `calendar.readonly`.
3. **Source-account impact** — for write/delete, show the change reflected in the
   user's actual Google account, not just in Atlas.
4. **Scope matching** — the scopes the app requests must exactly match the Cloud
   Console config.

The previous video failed #2 and #3. It never showed the calendar list (so
`calendar.readonly` looked unjustified) and never cut to Google Calendar to prove the
writes landed.

---

## Setup before recording

- Use the **reviewer test Google account** — Drew will text the login. Do not use a
  personal account: whatever account is on camera must be the one whose credentials
  Drew sends the reviewer, or they can't reproduce it.
- That account needs **at least two calendars** (primary + one secondary, e.g. "Work").
  With only a primary there is nothing for the calendar-picker shot to show, and
  `calendar.readonly` is exactly the scope under question.
- Create a **fresh Atlas account** — clean onboarding, no half-built spaces on screen.
- In Atlas: Settings → Connections → the Google account → **Disconnect**, so the
  consent screen appears fresh on camera.
- Open `calendar.google.com` in a browser logged into the same test account. Put Atlas
  and the browser side by side — you'll switch constantly.
- Record with ⌘⇧5, full screen, one continuous take. Stitched clips that skip the
  consent screen get rejected.

---

## Shot list

**1 — Consent screen (~30s)**
Settings → Connections → under GOOGLE, **Add Google account** → browser opens → pick the
test account → on the permissions screen click **"Show all services"** and expand every
collapsed row → **hold still on it 5+ seconds** so all five scopes are readable →
Continue/Allow.

**2 — `calendar.readonly` (~20s)**
Back in Atlas: Settings → Connections → click the Google account. The detail sheet shows
**"Choose which calendars sync into Atlas"** with the account's calendar list — pause
here. Switch to the browser and show the *same* list in Google Calendar's sidebar. Then
toggle a secondary calendar on and show its events appear in Atlas.

Why this shot exists: `calendar.events` alone cannot enumerate calendars —
`calendarList.list` 403s without a `calendar.readonly` grant, so the picker silently
falls back to primary-only. This shot is the visible justification for the scope.

**3 — `calendar.events` write + source-account impact (~60s)**
This is the part the last video was missing. Every step shows the Google side.

- Create an event in Atlas named "OAuth Review Test 1" → save.
- Browser → refresh Google Calendar → show it exists there.
- Atlas → edit it (change title and move the time).
- Browser → refresh → show the edited title and new time.
- Atlas → delete it.
- Browser → refresh → show it is **gone**. Don't cut away before it's visibly gone.

**4 — Read direction (~15s)**
Create an event in Google Calendar → sync/refresh Atlas → show it appear.

---

## Handoff back to Drew

Upload to YouTube as **Unlisted** (not Private — reviewers can't open Private). Title it
something like "Atlas — Google OAuth scope demo", and add the scopes in the description.
Send Drew the link; he replies on the verification thread and submits.
