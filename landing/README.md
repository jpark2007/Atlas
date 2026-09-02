# Atlas landing page

Static, no build step. Deploy the `landing/` folder to Vercel (or any static host).
`index.html`, `support.html`, `privacy.html`, `terms.html` share `styles.css` +
`main.js`. Serve the folder over HTTP when developing (`python3 -m http.server`) —
links are root-absolute, so `file://` won't resolve them.

## Shared chrome

The header, footer, and buttons are page-agnostic. Any page can adopt them by
copying the markup below; no home-page CSS is required.

**Header** — the brand `<svg>` is the one in `index.html`; copy it verbatim.

```html
<header class="site-head">
  <div class="wrap site-head__inner">
    <a class="brand" href="/" aria-label="Atlas Life Manager — home">
      <svg class="brand__mark" viewBox="0 0 239.908 383.028" fill="currentColor" aria-hidden="true">…</svg>
      <span class="brand__word">Atlas</span><span class="brand__suffix">Life Manager</span>
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="/#features">Features</a>
      <a href="/#why">Why we built it</a>
      <a class="site-nav__cta" href="/#download">Download</a>
    </nav>
  </div>
</header>
```

**Footer**

```html
<footer class="site-foot">
  <div class="wrap site-foot__inner">
    <div class="site-foot__brand">
      <span class="brand__word">Atlas</span><span class="brand__suffix">Life Manager</span>
      <p>A life manager for Mac, iPhone, and iPad. Built in the open.</p>
    </div>
    <div class="site-foot__meta">
      <p>Made by Andrew Khalil and Jonah Park.</p>
      <p><a href="mailto:drewkhalil@gmail.com">drewkhalil@gmail.com</a></p>
      <p class="site-foot__links">
        <a href="/support.html">Support</a> <span aria-hidden="true">·</span>
        <a href="/privacy.html">Privacy</a> <span aria-hidden="true">·</span>
        <a href="/terms.html">Terms</a> <span aria-hidden="true">·</span>
        <a href="/compare/">Compare</a> <span aria-hidden="true">·</span>
        <a href="/admin.html" rel="nofollow">Owners</a>
      </p>
      <p class="site-foot__copy">&copy; 2026 Atlas</p>
    </div>
  </div>
</footer>
```

**Buttons** — `.btn.btn--primary` for a plain ink button; `.app-btn.app-btn--primary`
for the Mac download (ink, with the laptop glyph) and `.app-btn.app-btn--store` for
Apple's App Store badge image. Wrap a download/badge pair in `.teasers__btns`.

**Screenshots** — wrap every product image in `<figure class="shot">`. The
`.shot img` rule supplies the hairline, radius, and shadow; set `width`/`height`
on the `<img>` so the aspect ratio is reserved before it loads. Web-ready WebP
files live in `assets/screens/` (Mac shots 1600px wide, iPhone shots 600px).

## Endpoints

`main.js` holds three Supabase function URLs at the top: `WAITLIST_ENDPOINT`
(unused by the current pages, kept for other flows), `TRACK_DOWNLOAD_ENDPOINT`
(fired on any `[data-download]` click), and `SUPPORT_ENDPOINT` (support form).

**Staging → real Supabase:** `supabase-staging/` is a copy only. To ship it: move
`supabase-staging/functions/waitlist/` into the app's `supabase/functions/`, move
`supabase-staging/migrations/0001_waitlist.sql` into `supabase/migrations/`
(rename with a fresh timestamp), then `supabase db push` and
`supabase functions deploy waitlist --no-verify-jwt`.
