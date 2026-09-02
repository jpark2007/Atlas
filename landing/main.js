/* =====================================================================
   Atlas landing — download beacon, scroll reveals, support form.
   No dependencies.
   ===================================================================== */

/* TRACK_DOWNLOAD_ENDPOINT — a non-blocking beacon fired when the "Download for
   Mac" button is clicked, so the owner dashboard can count DMG downloads. Never
   delays or blocks the actual download. */
const TRACK_DOWNLOAD_ENDPOINT =
  "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/track-download";

/* SUPPORT_ENDPOINT — the support page's form. Files the message as a bug_reports
   row (platform "web"), landing in the same owner dashboard as in-app reports. */
const SUPPORT_ENDPOINT =
  "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/support-request";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/* ---- download beacon ------------------------------------------------
   Count DMG downloads without getting in the way. `sendBeacon` (POST, no
   preflight, no body) queues the request and returns instantly, so the click
   proceeds to the download uninterrupted; a fetch keepalive is the fallback.
   Any failure is silently ignored — a missed count never blocks a download.
   -------------------------------------------------------------------- */
(function initDownloadBeacon() {
  const btns = document.querySelectorAll("[data-download]");
  if (!btns.length) return;
  btns.forEach((btn) =>
    btn.addEventListener("click", () => {
      try {
        if (navigator.sendBeacon) {
          navigator.sendBeacon(TRACK_DOWNLOAD_ENDPOINT);
        } else {
          fetch(TRACK_DOWNLOAD_ENDPOINT, { method: "POST", keepalive: true }).catch(() => {});
        }
      } catch (_) {
        /* never let tracking interfere with the download */
      }
    })
  );
})();

/* ---- scroll moments -------------------------------------------------
   One IntersectionObserver drives every entrance. Hidden states are CSS,
   gated by the
   `anim` class the <head> adds only when motion is allowed. If that class
   is absent (no JS, or reduced-motion), the page is already fully static.
   -------------------------------------------------------------------- */
(function initMotion() {
  const animOn = document.documentElement.classList.contains("anim");

  if (!animOn || !("IntersectionObserver" in window)) {
    document
      .querySelectorAll("[data-reveal]")
      .forEach((el) => el.classList.add("is-visible"));
    return;
  }

  /* --- prep: split display headlines into word masks --- */
  document
    .querySelectorAll(".hero__title, .feature__title, .capture__title, .band__title, .cta-band__title")
    .forEach(splitWords);

  /* --- prep: wrap each kicker's label so it can settle after the dash --- */
  document.querySelectorAll(".kicker").forEach((k) => {
    const label = document.createElement("span");
    label.className = "kicker__label";
    while (k.firstChild) label.appendChild(k.firstChild);
    k.appendChild(label);
  });

  /* --- one observer for every entrance --- */
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const el = entry.target;
        el.classList.add("is-visible");
        io.unobserve(el);
      });
    },
    { threshold: 0.2, rootMargin: "0px 0px -8% 0px" }
  );

  document
    .querySelectorAll("[data-reveal], .split")
    .forEach((el) => io.observe(el));

  /* ---------- word splitter (preserves <em> wrappers) ---------- */
  function splitWords(el) {
    const counter = { n: 0 };
    const built = document.createElement("span");
    walk(el, built, counter);
    el.textContent = "";
    while (built.firstChild) el.appendChild(built.firstChild);
    el.classList.add("split");
  }

  function walk(node, target, counter) {
    node.childNodes.forEach((child) => {
      if (child.nodeType === 3) {
        child.textContent.split(/(\s+)/).forEach((tok) => {
          if (tok === "") return;
          if (/^\s+$/.test(tok)) {
            target.appendChild(document.createTextNode(" "));
            return;
          }
          const w = document.createElement("span");
          w.className = "w";
          const inner = document.createElement("span");
          inner.className = "w-in";
          inner.textContent = tok;
          inner.style.transitionDelay = (counter.n * 0.05).toFixed(2) + "s";
          counter.n++;
          w.appendChild(inner);
          target.appendChild(w);
        });
      } else if (child.nodeType === 1) {
        const clone = child.cloneNode(false);
        walk(child, clone, counter);
        target.appendChild(clone);
      }
    });
  }
})();

/* ---- capture demo ---------------------------------------------------
   Four beats, all driven off one `data-state` on the stage:
     typing  — the sentence writes itself, character by character
     reading — a sweep crosses the box and lights the tokens Atlas found
     flying  — each lit token flies (FLIP: measured start → measured target)
               out of the sentence into the card that will hold it
     done    — the cards stand, "3 added to your week" confirms, then a fade
               resets and the whole thing runs again.
   The finished sentence and cards are already in the markup, so this only
   runs when motion is allowed; otherwise the section is its own end state.
   It starts when the stage is at least half on screen, and starts over from
   the top whenever it leaves and comes back. Replay restarts it by hand.
   -------------------------------------------------------------------- */
(function initCaptureDemo() {
  const stage = document.querySelector("[data-capture]");
  if (!stage || !document.documentElement.classList.contains("anim")) return;

  const line = stage.querySelector("[data-cap-line]");
  const fliers = stage.querySelector("[data-cap-fliers]");
  const replay = document.querySelector("[data-capture-replay]");
  const toks = Array.from(line.querySelectorAll(".cap-tok"));
  const lands = Array.from(stage.querySelectorAll("[data-land]"));

  /* The sentence's own child nodes, each with its finished text, so the
     typewriter refills them in order instead of rebuilding the markup. */
  const segs = Array.from(line.childNodes)
    .filter((n) => n.nodeType === 3 || n.classList.contains("cap-tok"))
    .map((node) => ({ node, text: node.textContent }));
  const chars = segs.reduce((n, s) => n + s.text.length, 0);

  const timers = [];
  let typer = null;
  let onScreen = false;

  const at = (ms, fn) => timers.push(setTimeout(fn, ms));

  function halt() {
    timers.splice(0).forEach(clearTimeout);
    if (typer) { clearInterval(typer); typer = null; }
  }

  function typed(n) {
    let left = n;
    for (const s of segs) {
      const take = Math.max(0, Math.min(s.text.length, left));
      s.node.textContent = s.text.slice(0, take);
      left -= take;
    }
  }

  function reset() {
    halt();
    stage.dataset.state = "idle";
    typed(0);
    toks.forEach((t) => t.classList.remove("is-lit", "is-gone"));
    lands.forEach((el) => { el.style.opacity = ""; });
    fliers.textContent = "";
  }

  /* FLIP: measure where each token is, measure where it is going, then send
     a copy of it along that vector while the real one dims out. */
  function fly() {
    const base = stage.getBoundingClientRect();
    toks.forEach((tok, i) => {
      const target = lands[i];
      if (!target) return;
      const from = tok.getBoundingClientRect();
      const to = target.getBoundingClientRect();
      const css = getComputedStyle(tok);

      const el = document.createElement("span");
      el.className = "cap-flier";
      el.textContent = tok.textContent;
      el.style.left = from.left - base.left + "px";
      el.style.top = from.top - base.top + "px";
      el.style.fontSize = css.fontSize;
      el.style.color = css.color;
      el.style.background = css.backgroundColor;
      fliers.appendChild(el);

      const scale = Math.max(0.3, Math.min(1, to.width / Math.max(from.width, 1)));
      const dx = to.left - from.left;
      const dy = to.top - from.top;

      tok.classList.add("is-gone");
      target.style.opacity = "0";
      at(40 + i * 110, () => {
        el.style.transform = "translate(" + dx + "px," + dy + "px) scale(" + scale + ")";
        el.style.opacity = "0.9";
      });
      at(40 + i * 110 + 640, () => {
        el.remove();
        target.style.opacity = "1";
      });
    });
  }

  function run() {
    reset();
    stage.dataset.state = "typing";
    let n = 0;
    typer = setInterval(() => {
      typed(++n);
      if (n < chars) return;
      clearInterval(typer);
      typer = null;
      sort();
    }, 24);
  }

  function sort() {
    at(280, () => { stage.dataset.state = "reading"; });
    toks.forEach((t, i) => at(500 + i * 195, () => t.classList.add("is-lit")));

    const read = 500 + toks.length * 195 + 250;
    at(read, () => { stage.dataset.state = "flying"; fly(); });

    const landed = read + 40 + (toks.length - 1) * 110 + 640;
    at(landed + 140, () => { stage.dataset.state = "done"; });
    at(landed + 3200, () => { stage.dataset.state = "fading"; });
    at(landed + 3800, () => { if (onScreen) run(); else reset(); });
  }

  if (replay) {
    replay.hidden = false;
    replay.addEventListener("click", run);
  }

  reset();

  /* Half of the stage on screen starts it. On a phone the stage can be taller
     than the window, so ask for whatever share of it a window can actually
     show, capped at half. */
  const share = Math.max(
    0.08,
    Math.min(0.5, (window.innerHeight * 0.55) / Math.max(stage.offsetHeight, 1))
  );
  new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.intersectionRatio >= share - 0.001) {
          if (!onScreen) { onScreen = true; run(); }
        } else if (entry.intersectionRatio === 0 && onScreen) {
          onScreen = false;
          reset();
        }
      });
    },
    { threshold: [0, share] }
  ).observe(stage);
})();

/* ---- support form ---------------------------------------------------
   A honeypot in, one status line out. Present only on support.html, so bail
   quietly everywhere else.
   -------------------------------------------------------------------- */
(function initSupportForm() {
  const form = document.querySelector("[data-support]");
  if (!form) return;

  const subject = form.querySelector('input[name="subject"]');
  const email = form.querySelector('input[name="email"]');
  const message = form.querySelector('textarea[name="message"]');
  const honeypot = form.querySelector('input[name="referral_code"]');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector("[data-status]");
  const idleLabel = button ? button.textContent : "Send it";

  function setStatus(text, kind) {
    if (!status) return;
    status.textContent = text || "";
    if (kind) status.dataset.kind = kind;
    else delete status.dataset.kind;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const body = (message.value || "").trim();
    const addr = (email.value || "").trim();

    if (body.length < 2) {
      setStatus("Tell us what's happening first.", "error");
      message.focus();
      return;
    }
    // An address is optional, but a mistyped one means a reply that never lands.
    if (addr !== "" && !EMAIL_RE.test(addr)) {
      setStatus("That email doesn't look right. Mind checking it?", "error");
      email.focus();
      return;
    }

    button.disabled = true;
    button.setAttribute("aria-busy", "true");
    button.textContent = "Sending…";
    setStatus("", null);

    try {
      const res = await fetch(SUPPORT_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: body,
          email: addr,
          subject: (subject.value || "").trim(),
          referral_code: (honeypot && honeypot.value) || "",
        }),
      });
      if (!res.ok) throw new Error("Request failed: " + res.status);

      form.dataset.done = "true";
      message.value = "";
      if (subject) subject.value = "";
      setStatus(
        addr
          ? "Got it. We'll read this and write back."
          : "Got it. We'll read this — add an email next time if you want a reply.",
        "success",
      );
    } catch (err) {
      setStatus("That didn't send. Give it another try?", "error");
      button.disabled = false;
      button.removeAttribute("aria-busy");
      button.textContent = idleLabel;
    }
  });
})();
