# Google OAuth Verification — Action Plan

**Goal:** get Atlas's Google OAuth client out of the 100-user cap and stop the
`admin_policy_enforced` hard-block on Google Workspace for Education domains
(e.g. Rutgers).

**Status quo:** App = External / In production / **Unverified**. Scopes requested:
`calendar.events` (sensitive), `documents` (sensitive), `drive.file` (non-sensitive,
no review), `openid`, `email` (non-sensitive). No restricted scopes → **standard
verification only, no CASA security assessment needed.**

---

## 1. Checklist

Work top to bottom — each step gates the next.

### A. Domain verification (Search Console)
- [ ] Confirm the production landing domain is locked in (per `landing/copy.md` it was still slated for "a free subdomain" — **pin the real domain before anything else**, every later step references it).
- [ ] https://search.google.com/search-console → Add property → verify the domain (DNS TXT record is easiest if you own the apex domain; HTML file method if on a Vercel subdomain you don't control DNS for).
- [ ] Same Google account/user that owns Search Console verification must be the one adding "Authorized domains" in the Cloud Console consent screen (or be granted access) — mismatched owners is a common silent blocker.

### B. OAuth consent screen branding
Console: https://console.cloud.google.com/apis/credentials/consent
- [ ] **App name**: "Atlas" (must match what the demo video and landing page show — reviewers cross-check).
- [ ] **App logo**: 120×120 PNG required for brand review. **Gap: none exists in `landing/` today** (site only has an inline SVG brand mark) — export one before submitting or brand review stalls.
- [ ] **User support email**: `lets.flowstate@gmail.com`.
- [ ] **App homepage**: the verified domain from step A (must be publicly reachable, describe what Atlas is — index.html already does this).
- [ ] **App privacy policy link**: `https://<domain>/privacy.html` — must be live at a URL under an authorized domain, not just a repo file.
- [ ] **App Terms of Service link**: `https://<domain>/terms.html`.
- [ ] **Authorized domains**: add the verified domain from step A.
- [ ] **Developer contact email**: `lets.flowstate@gmail.com`.
- [ ] Fix the privacy-policy content gaps in §4 below **before** submitting — reviewers read the linked page, not this doc.

### C. Scope verification submission
Console: same consent screen → "Prepare for verification" / OAuth consent screen → Scopes
- [ ] Add scopes: `.../auth/calendar.events`, `.../auth/documents`, `.../auth/drive.file`, `openid`, `email`.
- [ ] Paste the justifications from §2 below into each sensitive scope's justification field.
- [ ] Upload/link the demo video (§3) — YouTube **unlisted**, not private (Google's review bot can't auth to private videos).
- [ ] Submit for verification. Expect an email thread from Google's OAuth API team at the Cloud Console contact email — reply-all promptly, they close stale threads after ~1-2 weeks of silence.

---

## 2. Scope justifications (ready to paste)

**`.../auth/calendar.events` (sensitive)**
> Atlas is a native macOS/iOS life-manager app that unifies a user's calendars
> from multiple sources (Apple Calendar, Google Calendar, Canvas) into one
> timeline. Users connect one or more Google accounts — routed per workspace
> (e.g. personal vs. school) — and Atlas keeps their Google Calendar events in
> two-way sync with the corresponding events in Atlas: creating an event in
> Atlas writes it to the user's Google Calendar, and edits made in Google
> Calendar (including while Atlas is closed, via a server-side sync runner)
> flow back into Atlas. We request `calendar.events` — not full `calendar`
> access — because we only need to read and write the user's own events, not
> manage calendar settings, ACLs, or other calendars.

**`.../auth/documents` (sensitive)**
> Atlas's Notes feature offers optional two-way editing with Google Docs: a
> user can link an Atlas note to a Google Doc, edit either one, and have
> changes round-trip via a Markdown conversion. We request `documents` because
> we need to read and write the content of the specific Google Doc the user
> has linked — not manage Drive-wide file organization or sharing, which is
> why file access/selection itself is scoped separately under `drive.file`.

**`.../auth/drive.file` (non-sensitive — no scope-justification review required)**
> Used only for files the user explicitly picks via Google's file picker (e.g.
> selecting which Doc to link to a note, or a future Drive-based notes
> import). Atlas never receives blanket access to a user's Drive.

**`openid` / `email` (non-sensitive)** — used for Sign in with Google account identification only; no justification field required.

---

## 3. Demo video script (2-3 min, unlisted YouTube)

Record screen only, no editing required beyond trimming. Narrate briefly over each shot — reviewers want to *see* the scope used, not hear marketing copy.

1. **(0:00-0:20) Consent screen.** Show the Google OAuth consent screen mid-flow: app name "Atlas", logo, and the scope list visibly requesting Calendar events and Docs access. Pause on this frame for a couple seconds.
2. **(0:20-0:35) Sign-in complete.** Show Atlas's Connections/Settings screen listing the connected Google account.
3. **(0:35-1:20) `calendar.events` in action.**
   - Create a new event in Atlas, show it appear in Google Calendar (web or app) within the sync window.
   - Then edit/move an event directly in Google Calendar and show it updating back in Atlas — this demonstrates the *two-way* claim made in the justification, not just a one-way push.
4. **(1:20-2:10) `documents` in action.**
   - In Atlas, open a note linked to a Google Doc, make an edit, show the same content updated in the actual Google Doc (open it in a browser tab).
   - Edit the Google Doc directly, show it round-trip back into the Atlas note.
5. **(2:10-2:30) Close.** Briefly show the disconnect control (proves user control over the connection, which reviewers look for).

Upload unlisted, paste the link in the verification form's "demo video" field, and don't take it down — Google re-checks it if the app is re-reviewed later (annual re-verification for sensitive scopes).

---

## 4. Privacy-policy gaps (read from `landing/privacy.md`)

**What's there today** — quoted:
- "If you connect Google Calendar, Atlas keeps your events in sync in both directions... your Google **refresh token** is stored **encrypted in Supabase Vault, reachable only by our server, and never returned to any app or client**... The permission we request is limited to your Google Calendar."
- "Google Drive import (coming, not yet in the app)... will use Google's `drive.file` permission... isn't shipped yet."
- No mention anywhere of Google Docs / `documents` scope.
- No mention of the words "Google API Services User Data Policy" or "Limited Use" anywhere in the document.

**Gaps to fix before submitting:**
- [ ] **Missing Limited Use disclosure (blocking).** Google requires an explicit statement, typically verbatim-adjacent: *"Atlas's use and transfer to any other app of information received from Google APIs will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements."* This sentence does not exist in the policy today and is checked directly by reviewers — add it as its own subsection, not buried in prose.
- [ ] **No Google Docs / `documents` scope disclosure.** The privacy policy only describes Calendar and a *future* Drive import; it says nothing about the Notes ↔ Google Docs round-trip feature that actually requests the `documents` scope. Add a subsection parallel to the existing "Google Calendar (two-way sync)" one, naming the scope, what's read/written (linked Doc content only), and that it's not blanket Drive access.
- [ ] **`drive.file` section is stale/inaccurate.** It's currently written as "coming, not yet in the app" — if `drive.file` is requested in the live OAuth client today (as stated in this task's context), the policy is describing a scope as unshipped that's actually already being granted. Update to reflect current reality (used for user-picked file selection in the Docs-linking flow), or drop `drive.file` from the live client if it truly isn't used yet — a policy/scope mismatch is a rejection reason on its own.
- [ ] **No explicit data-retention statement for Google data.** Policy says the refresh token is "stored encrypted... deleted on disconnect" (good), but doesn't state how long synced calendar/event content or Doc content persists after disconnect, or confirm it isn't used for anything besides the stated sync purpose. Add one line: data obtained via Google APIs is used solely to power the described sync features, not for ads, not shared with third parties beyond the AI capture provider (which doesn't touch Google-sourced content), and is deleted on account/connection deletion.
- [ ] **No mention of what's read vs. written per scope.** For `calendar.events`, explicitly state Atlas reads and writes event title/time/attendees/description as needed for sync — reviewers want scope-to-data-field specificity, not just "your Google Calendar."
- [ ] **Relative links, no absolute domain yet.** `copy.md` confirms links are relative ("hosted later on a free subdomain"). The consent screen requires an absolute, publicly resolvable privacy-policy URL under an authorized domain — this must be finalized before submission (see §1.A).

---

## 5. Timeline & what changes

| Stage | Typical duration |
|---|---|
| Brand verification (logo, name, homepage, domain match) | A few days, can run in parallel with scope prep |
| Scope verification (sensitive scopes, standard track, no CASA) | ~1-2 weeks after a clean submission |
| Back-and-forth email thread | Add time per round-trip; Google's OAuth team replies from a Cloud-Console-linked address — reply promptly, threads go stale/close after ~1-2 weeks of silence |

**Common rejection reasons (avoid these on the first pass):**
- Privacy policy link doesn't match the domain on the consent screen, or the linked page doesn't mention the specific scopes/Limited Use language.
- Demo video shows the app generally but never actually exercises the sensitive scope (e.g. shows Calendar view but never demonstrates a write-back to Google Calendar).
- Generic/boilerplate scope justification ("we need calendar access to sync calendars") instead of naming the actual Atlas feature and data flow.
- Requesting a broader scope than the feature needs (e.g. full `calendar` instead of `calendar.events`) — not applicable here since scopes are already minimal, but double-check no broader scope crept into the OAuth client config vs. what's documented.

**Before vs. after approval:**
- **Before (now):** every new Google sign-in counts against the 100-lifetime-user cap regardless of whether it's a new or returning user in some flows; Google Workspace for Education admins (Rutgers, etc.) can and do hard-block unverified third-party apps org-wide, surfacing as `Error 400: admin_policy_enforced` — no user-side workaround, only the admin can allowlist it or Atlas gets verified.
- **After approval:** cap is lifted, unverified-app warning screen disappears for consumer Gmail accounts, and Workspace domains that don't specifically restrict third-party apps will generally allow sign-in.
- **Still possible post-verification:** Workspace/Education admins can independently restrict *specific* third-party apps even after Google verification — some university IT departments require a separate allowlist request per app regardless of Google's verification status. If Rutgers (or others) keep blocking after Atlas is verified, that's a separate per-institution allowlisting ask to their IT, not a Google-side issue.
