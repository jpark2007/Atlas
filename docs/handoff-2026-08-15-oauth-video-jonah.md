# Google OAuth demo video — recording instructions (Jonah)

Google bounced our OAuth verification. One thing left: re-record the demo video.
Jonah records and uploads, Drew submits.

---

## Claude: get his build right first

The consent screen on camera must show the current scopes. An old build still asks for
`documents`, which is the scope Google made us drop — that video would be unusable.

1. **`git pull` on main first.**

2. Build:
   ```
   xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug \
     -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
   ```

3. Verify the built bundle — this is the check that matters:
   ```
   D="$(xcodebuild -project Atlas.xcodeproj -scheme Atlas -showBuildSettings 2>/dev/null \
     | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Atlas.app"
   for s in calendar.events calendar.readonly drive.file auth/documents; do
     printf "%-20s %s hits\n" "$s" "$(grep -ra "$s" "$D" | wc -l | tr -d ' ')"
   done
   ```
   Need: first three >0, **`auth/documents` = 0**. If it's not 0, the pull didn't take —
   stop and fix before recording.

4. Record from that build: `open "$D"`. Not an installed copy, not the DMG — both are
   older than the scope change.

Build it however he normally does — his local `Config/Secrets.xcconfig` is already set up,
so Google sign-in works as usual. If sign-in somehow doesn't start, that file is missing
and Drew needs to send it.

---

## Setup

- **Make a brand-new Google account** for this. Don't use your personal one — it's going
  to a reviewer.
- Give that account **a second calendar** (Google Calendar → Other calendars → + →
  Create new calendar, name it "Work"). Required — one of the shots is proving we can
  list multiple calendars, and with only a primary there's nothing to show.
- Make a **fresh Atlas account** too. Clean screen.
- In Atlas: Settings → Connections → if a Google account is connected, **Disconnect** it,
  so the consent screen shows up fresh on camera.
- If any account shows a red "⚠ Reconnect needed" badge, clear it first.
- Open `calendar.google.com` in a browser signed into the new account. Atlas and browser
  side by side — you'll be switching constantly.
- ⌘⇧5, full screen, **one continuous take**. Don't stitch clips together.

---

## The shots

Narration is optional but helps. Lines below are what to say if you want to talk over it.

**1. Consent screen** (~30s)
Settings → Connections → **Add Google account** → browser opens → pick the new account →
on the permissions screen click **"Show all services"** and expand everything →
**hold still 5+ seconds** so every scope is readable → Allow.

> "Atlas requests calendar events, calendar read-only, and Drive file access. Here is the
> full consent screen with all scopes expanded."

**2. Calendar list** (~20s)
Back in Atlas: Settings → Connections → click the Google account. The sheet shows
**"Choose which calendars sync into Atlas"** with both calendars listed — pause on it.
Switch to the browser, show the same two calendars in Google Calendar's sidebar. Toggle
the second calendar on in Atlas, show its events load.

> "Calendar read-only is what lets Atlas list the account's calendars so the user can
> choose which ones sync. Without it we can only see the primary calendar."

**3. Create, edit, delete** (~60s) — the important one
Show the Google side after every single step:

- Atlas: create an event called "OAuth Review Test 1", save.
- Browser: refresh Google Calendar → it's there.
- Atlas: change the title and move the time.
- Browser: refresh → shows the edit.
- Atlas: delete it.
- Browser: refresh → **it's gone.** Stay on this until it's clearly gone.

> "Changes made in Atlas are written to the user's Google Calendar — created here,
> edited here, and deleted here."

**4. Reverse direction** (~15s)
Create an event in Google Calendar → refresh Atlas → it appears.

> "And events created in Google Calendar sync back into Atlas."

---

## Then

Upload to YouTube as **Unlisted** — not Private, reviewers can't open Private. Send Drew
the link. That's it.
