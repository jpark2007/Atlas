# Atlas Privacy Policy

**Effective date: August 27, 2026**

Atlas is built by Andrew Khalil and Jonah Park. The best way to reach us is **Report a Bug** inside Atlas, where signed-in users can send questions or issues straight to us. If you can't get into the app, email **drewkhalil@gmail.com**.

Atlas is a native Mac, iPhone, and iPad life manager, free on every platform it runs on. This policy explains what we collect, why, and who touches it. We've kept it specific to what Atlas actually does — no filler about cookies or trackers we don't use.

## The short version

- We store the data you put into Atlas and the email you sign up (or join the waitlist) with.
- We use it to run the app for you. **We don't sell your data and we don't use it for advertising.**
- Connections you choose to add (Google Calendar, Canvas) are stored encrypted on our server and used only to sync your calendar.
- You can delete your account and its data from **Settings** inside Atlas. If you've already removed the app, email **drewkhalil@gmail.com** and we'll do it for you.

## Google user data: what Atlas accesses and how it is used

This section states, permission by permission, exactly which Google user data Atlas requests, what Atlas does with it, and how long it is kept. Atlas requests these permissions only when you choose to connect a Google account; if you never connect one, Atlas requests none of them.

- **See and edit events on your Google calendars** (`calendar.events`) — *What Atlas accesses:* the events on the calendars you choose to sync, including their titles, times, locations, and descriptions. *How Atlas uses it:* to show your Google events inside Atlas alongside your other calendars, and to write back events you create or edit in Atlas so both stay matched. This runs on our server so the sync continues while the app is closed.
- **View your calendars and events** (`calendar.readonly`) — *What Atlas accesses:* the list of calendars in your Google account, including their names, and read access to their events. *How Atlas uses it:* to show you a checklist of your calendars at connect time so you can pick which ones sync, and to read event details during sync. Atlas does not use this permission to modify anything.
- **See and edit only the specific Google Drive files you use with Atlas** (`drive.file`) — *What Atlas accesses:* only files you personally pick through Google's own file picker, or that Atlas creates for you — including the content of a Google Doc you link to an Atlas note. *How Atlas uses it:* to import a file you selected into a project, and to keep a linked note and its Google Doc in sync in both directions. Atlas never receives access to your whole Drive and never sees files you have not explicitly picked.
- **Your email address and Google account identifier** (`email`, `openid`) — *What Atlas accesses:* the email address of the Google account you connect, plus a stable identifier for it. *How Atlas uses it:* solely to identify and label which Google account is connected, so you can tell your accounts apart in Settings. Atlas does not request access to your name, profile picture, contacts, or any other profile information.

**How this data is handled.** Google data is stored in your own account's rows in our Supabase database, protected by per-account row-level security. Your Google **refresh token** is stored encrypted in Supabase Vault, reachable only by our server, and is never returned to any app or client. Google data is used **only** to provide the calendar sync, file import, and note-sync features described above and visible to you in the app.

**What Atlas never does with Google data.** We do not sell it. We do not use it for advertising or to build advertising profiles. We do not use it to train AI or machine-learning models. We do not transfer it to third parties except as needed to provide these features to you. No human at Atlas reads your Google data except with your explicit consent, to provide support you have asked for, to keep the service secure, or where required by law.

**How long it is kept, and how to remove it.** Synced Google events and linked note content remain in your account for as long as your account exists and the connection is active. Disconnecting Google inside Atlas immediately deletes the stored refresh token and stops all further access. Deleting your Atlas account from **Settings** removes your account and its data, including data synced from Google. You can also revoke Atlas's access at any time from your Google Account at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

Atlas's use and transfer of information received from Google APIs to any other app adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.

## The waitlist

If you join the waitlist on our site, we store the email address you submit in our database so we can tell you when Atlas opens up. That email is the only thing the form collects. Our site doesn't set advertising cookies or run third-party trackers. (Our hosting provider may keep standard server request logs, as web hosts do.)

## Your account

Atlas accounts and data run on **Supabase**, our backend and authentication provider. When you create an account, your email and sign-in details are stored there. The data you create in Atlas — spaces, projects, tasks, calendar events, notes, and goals — is stored per-account and protected by row-level security, so only your signed-in account can read your own rows.

## Connections you choose to add

Atlas works fine on its own. These integrations are optional, and each is only active if you turn it on.

### Google API Services User Data Policy

Atlas's use and transfer of information received from Google APIs to any other app will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Data from your connected Google account is used only to power the sync and sign-in features described below, and is stored in your own account's rows in Supabase, with tokens further protected in Vault. We do not sell Google user data, we do not use it for advertising, and no human reads it except with your consent, to provide support you ask for, to keep the service secure, or to comply with the law.

### Google Calendar (two-way sync)

If you connect Google Calendar, Atlas keeps your events in sync in both directions — including while the app is closed — using a server-side sync runner. Atlas reads your Google Calendar events and writes back the events you create or edit in Atlas, so the two stay matched. To do that, your Google **refresh token** is stored **encrypted in Supabase Vault, reachable only by our server, and never returned to any app or client**. We use it only to read and write your calendar events for the sync. You can disconnect at any time; disconnecting deletes the stored token.

### Choosing which calendars sync

When you connect Google Calendar, Atlas also lists the calendars in your account so you can pick which ones to sync with per-calendar checkboxes. This uses Google's read-only calendar permission, which lets Atlas see your calendar names and read event details, so you stay in control of what syncs. Atlas never modifies anything through this permission.

### Your Google account

When you connect Google, Atlas reads the **email address** of that account and a stable identifier for it, so it can identify the connected account and label it in the app. That is the only thing this sign-in permission gives us — Atlas does not request your name, profile picture, or contacts.

### Google Docs (two-way note sync)

Atlas's Notes feature offers optional two-way editing with Google Docs: you can link an Atlas note to a Google Doc, edit either one, and have the changes round-trip via a Markdown conversion. To do that, Atlas reads and writes the content of the specific Google Doc you've linked — nothing else in your Drive. That content is stored as your note's content in your account's rows in Supabase, the same as any other note. We use it only to keep the linked note and Doc in sync; it's never sold, shared with third parties, or used for advertising. You can unlink a note at any time, which stops any further sync with that Doc.

### Canvas (assignments and course events)

If you add a Canvas calendar feed, you paste your personal Canvas feed URL. That URL is itself a secret — anyone holding it can read your feed — so we store it **encrypted in Supabase Vault, server-only**, and use it solely to pull your assignments and course events into Atlas. Canvas data is **read-only**: Atlas never writes back to Canvas. Disconnecting removes the stored feed URL.

### Apple Calendar

On Mac, Atlas can show your Apple Calendar events using macOS's calendar access on your device, if you grant permission.

### AI capture

Atlas has a capture box: you type or paste free text ("essay due Friday, gym 3x this week, dinner Sunday") and Atlas turns it into tasks, events, and notes. To do that, **the text you capture** is sent to our server and then to a third-party AI model provider (currently **OpenRouter**, which routes to a model such as GPT-4o-mini) to classify it. We send only the text you choose to capture, plus the names of your spaces and projects so the item lands in the right place. We don't send the rest of your Atlas data to the model.

### Google Drive (linking and importing files)

Atlas uses Google's `drive.file` permission for the two places where you choose or create files yourself: importing a file through Google's file picker, and linking a Google Doc to a note. It only ever gives Atlas access to the specific files you pick or that Atlas creates for you. Atlas never receives blanket access to your Drive, and never sees files you haven't explicitly picked.

## Who processes your data

We don't sell your data or use it for advertising. We rely on a few service providers to run Atlas, and your data passes through them only to provide the service:

- **Supabase** — database, authentication, encrypted secret storage, and server functions (also where waitlist emails are stored).
- **OpenRouter** — the AI provider that processes capture text.
- **Google and Canvas** — only the accounts you connect, and only for the sync you asked for.

## Keeping data secure

- Per-account row-level security so accounts can't read each other's data.
- Connection secrets (your Google refresh token, your Canvas feed URL) are kept in encrypted Vault storage, reachable only by our server and never returned to a client.

No system is perfectly secure, and Atlas is still changing — see the caveat below.

## Deleting your data

You can delete your account and everything in it from **Settings** inside Atlas, on the Mac, iPhone, or iPad app. That removes your account and its data for good. If you can no longer get into the app, email **drewkhalil@gmail.com** and we'll delete it for you. You can also disconnect Google or Canvas inside Atlas at any time, which immediately removes the stored credential for that connection.

## Children

Atlas isn't directed at children under 13, and we don't knowingly collect their data.

## Things change

Atlas is built by two students. Features, data flows, and this policy will change as we build. When we make a meaningful change, we'll update the effective date and, where we can, notify waitlisted or registered users. Continuing to use Atlas after a change means you accept the updated policy.

## Contact

Andrew Khalil and Jonah Park. The best way to reach us is **Report a Bug** inside Atlas; if you can't get into the app, email **drewkhalil@gmail.com**.
