# Atlas landing page

Static, no build step. Deploy the `landing/` folder to Vercel (or any static host).
Every page loads `/styles.css`; `index.html` and `support.html` also load
`/main.js`. `compare/` and `admin.html` add their own page-specific CSS on top.
Serve the folder over HTTP when developing (`python3 -m http.server`) — links are
root-absolute, so `file://` won't resolve them.

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
      <p>A planner for Mac, iPhone, and iPad.</p>
    </div>
    <div class="site-foot__meta">
      <p>Two students, one app.</p>
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

**Screenshots** — every product image is worn by the device it came from. The
frames are CSS only (no mockup PNGs) and share one radius, bezel, and shadow, so
they stay consistent wherever they are reused. Always set `width`/`height` on the
`<img>` so the aspect ratio is reserved before it loads. Web-ready WebP files
live in `assets/screens/` (Mac shots 1200-1900px wide, iPhone shots 600/900px).
Every Mac shot also has a `-m` twin: a tighter crop of the one region that
carries the message, served under 640px through `<picture><source media>`, so a
phone gets a readable zoom instead of a shrunken window. Regenerate them from
the Retina sources with the crop table in the shot-export script (mild contrast
lift → LANCZOS downscale → light unsharp mask).

A whole Mac window sits in a MacBook. A cropped *region* of a window never does
— it takes `<figure class="shot shot--plain">`, which is hairline, radius, and
shadow only:

```html
<figure class="shot">
  <div class="laptop">
    <div class="laptop__screen">
      <img src="/assets/screens/….webp" width="1600" height="1000" alt="…" />
    </div>
    <div class="laptop__base" aria-hidden="true"></div>
  </div>
</figure>
```

An iPhone:

```html
<figure class="shot iphone">
  <span class="iphone__island" aria-hidden="true"></span>
  <img src="/assets/screens/….webp" width="600" height="1301" loading="lazy" alt="…" />
</figure>
```

Something that already carries its own shape (the menu-bar popover) takes
`<figure class="shot shot--float">`, which is radius and shadow only. Put three
phones side by side with `<div class="phones">` — under 640px that turns into a
scroll-snap strip on its own.

The frames are deliberately minimal: the iPhone is a ~3px ink rim inside a 1px
light-metal edge, with the screen radius set to the body radius less the rim so
the corners stay concentric; the MacBook is a matching thin rim with a camera
notch and a flat base lip. If a frame ever starts reading as a slab, that is the
bug — the screenshot is meant to dominate.

## Endpoints

`main.js` holds two Supabase function URLs at the top: `TRACK_DOWNLOAD_ENDPOINT`
(fired on any `[data-download]` click) and `SUPPORT_ENDPOINT` (the support form).
`admin.html` calls `admin-stats` behind its code gate.

The comparison page keeps its "Updated" date in one place: `const CHECKED_ON` at
the top of `compare/compare.js` feeds the byline, the sources note, and the meta
description.
