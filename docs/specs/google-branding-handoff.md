# Google Branding Findings — What Only You Can Do

The Verification Center lists **three open branding findings** (last reviewed Aug 4). The
banner above them saying branding "has been verified" is stale — the review below it is what
gates approval. **Verification will not complete while these are open, however good the video
is.** They're separate from the video and get fixed in the same reply.

## The decision behind these steps

The findings all trace to one thing: "Atlas" is a generic name that collides with other brands,
and it doesn't match anything distinctive on the homepage. The fix is to present the product as
**Atlas Life Manager** — what atlaslm.net already abbreviates, distinctive enough for Google's
"uniquely identifies your brand" bar, and no AI connotation ("Atlas LM" was rejected for reading
as "language model").

The in-app product name stays **Atlas**. Google only compares the consent screen against the
homepage.

## Already done (site side, deployed)

- Header and footer wordmark now read **Atlas Life Manager** on every page.
- `<title>` and the social card on the homepage read **Atlas Life Manager**.
- Privacy, Terms and Support titles carry the full name too.
- The name stays visible at phone widths (it shrinks, it never disappears).

Live at https://www.atlaslm.net — verify before you touch the console, since the reviewer
compares the console against whatever the site is serving at that moment.

## Your steps — Cloud Console, project `atlas-500710`

**1 · App name** → *Google Auth Platform → Branding*
- [ ] Set **App name** to exactly `Atlas Life Manager`.
- [ ] It must match the homepage character for character. Not "Atlas", not "AtlasLM".
- [ ] Save.

**2 · Logo** → same Branding page
- [ ] Upload `landing/assets/atlas-logo-120.png` (already the right 120×120, and the same mark
      the site header and favicon use — that sameness is the point).
- [ ] Save. A logo change can trigger a fresh branding review; that's expected and runs in
      parallel with the rest.

**3 · Scope matching** → *Data Access* (this is criterion 4 from the Aug 4 email)
- [ ] Confirm exactly three scopes: `calendar.events`, `calendar.readonly`, `drive.file`.
- [ ] If `documents` is still listed, remove it — your Jul 30 reply declared four scopes.
- [ ] Save and submit changes.

**4 · Homepage / privacy URLs** → Branding page
- [ ] App homepage: `https://www.atlaslm.net`
- [ ] Privacy policy: `https://www.atlaslm.net/privacy.html`
- [ ] Terms: `https://www.atlaslm.net/terms.html`
- [ ] All three must be reachable and on the verified domain.

**5 · The reply** — one email covers video *and* branding. Take Step 4 of
`google-oauth-verification-runbook.md` and add this paragraph before the sign-off:

> **Branding:** we have also addressed the branding findings. The application is now named
> "Atlas Life Manager" on the OAuth consent screen, matching the name shown on our homepage at
> https://www.atlaslm.net, and the logo has been updated to our own mark — the same one used in
> the site header and favicon. It does not resemble or reference any other brand.

## Order

Site is already live, so: console name → logo → scopes → URLs → upload video → send the reply.
Everything in the console must be saved and submitted **before** the email, since the reviewer
checks the console state at the moment they read it.
