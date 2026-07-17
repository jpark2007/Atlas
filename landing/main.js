/* =====================================================================
   Atlas landing — waitlist + scroll reveals. No dependencies.
   ===================================================================== */

/* --------------------------------------------------------------------
   WAITLIST_ENDPOINT — the Supabase edge function the form POSTs to.
   Deployed live (no-verify-jwt); nothing else here needs editing.
   -------------------------------------------------------------------- */
const WAITLIST_ENDPOINT =
  "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/waitlist";

/* TRACK_DOWNLOAD_ENDPOINT — a non-blocking beacon fired when the "Download for
   Mac" button is clicked, so the owner dashboard can count DMG downloads. Never
   delays or blocks the actual download. */
const TRACK_DOWNLOAD_ENDPOINT =
  "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/track-download";

const COPY = {
  idle: "Join the waitlist",
  sending: "Adding you…",
  success: "You're on the list. We'll be in touch when it's your turn.",
  errorGeneral: "That didn't go through. Give it another try?",
  errorEmail: "Hmm, that doesn't look like an email. Mind checking it?",
};

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/* ---- waitlist form -------------------------------------------------- */
(function initWaitlist() {
  const form = document.querySelector("[data-waitlist]");
  if (!form) return;

  const input = form.querySelector('input[type="email"]');
  const honeypot = form.querySelector('input[name="referral_code"]');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector("[data-status]");
  const idleLabel = (button && button.textContent.trim()) || COPY.idle;

  function setStatus(message, kind) {
    if (!status) return;
    status.textContent = message || "";
    if (kind) status.dataset.kind = kind;
    else delete status.dataset.kind;
  }

  function resetButton() {
    button.disabled = false;
    button.removeAttribute("aria-busy");
    button.textContent = idleLabel;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const email = (input.value || "").trim();

    if (!EMAIL_RE.test(email)) {
      setStatus(COPY.errorEmail, "error");
      input.focus();
      return;
    }

    button.disabled = true;
    button.setAttribute("aria-busy", "true");
    button.textContent = COPY.sending;
    setStatus("", null);

    try {
      const res = await fetch(WAITLIST_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, referral_code: (honeypot && honeypot.value) || "" }),
      });

      if (!res.ok) throw new Error("Request failed: " + res.status);

      form.dataset.done = "true";
      input.value = "";
      setStatus(COPY.success, "success");
    } catch (err) {
      // Never leave the button stuck in "Adding you…".
      setStatus(COPY.errorGeneral, "error");
      resetButton();
    }
  });
})();

/* ---- download beacon ------------------------------------------------
   Count DMG downloads without getting in the way. `sendBeacon` (POST, no
   preflight, no body) queues the request and returns instantly, so the click
   proceeds to the download uninterrupted; a fetch keepalive is the fallback.
   Any failure is silently ignored — a missed count never blocks a download.
   -------------------------------------------------------------------- */
(function initDownloadBeacon() {
  const btn = document.querySelector("[data-download]");
  if (!btn) return;
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
  });
})();

/* ---- scroll moments -------------------------------------------------
   One IntersectionObserver drives every entrance; one rAF loop drives the
   sphere drift + phone parallax. Hidden states are CSS, gated by the
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
    .querySelectorAll(".hero__title, .feature__title, .waitlist__title")
    .forEach(splitWords);

  /* --- prep: wrap each kicker's label so it can settle after the dash --- */
  document.querySelectorAll(".kicker").forEach((k) => {
    const label = document.createElement("span");
    label.className = "kicker__label";
    while (k.firstChild) label.appendChild(k.firstChild);
    k.appendChild(label);
  });

  /* --- prep: the capture typewriter starts empty --- */
  document.querySelectorAll(".capture__text").forEach((t) => {
    t.dataset.full = t.textContent;
    t.textContent = "";
  });

  /* --- prep: reveal the Personal list so it can cross-fade --- */
  document
    .querySelectorAll('[data-anim="spaces"] .space__list[data-list="personal"]')
    .forEach((ul) => ul.removeAttribute("hidden"));

  /* --- one observer for every entrance --- */
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const el = entry.target;
        el.classList.add("is-visible");
        if (el.dataset.anim === "capture") runCapture(el);
        else if (el.dataset.anim === "spaces") runSpaces(el);
        io.unobserve(el);
      });
    },
    { threshold: 0.2, rootMargin: "0px 0px -8% 0px" }
  );

  document
    .querySelectorAll("[data-reveal], [data-anim], .split")
    .forEach((el) => io.observe(el));

  /* --- one rAF loop: hero sphere drift + phone parallax --- */
  const sphere = document.querySelector(".sphere");
  const phones = document.querySelectorAll('[data-anim="phone"]');
  let lastY = -1;
  (function frame() {
    const y = window.scrollY;
    if (y !== lastY) {
      lastY = y;
      if (sphere) {
        sphere.style.transform =
          "translate3d(0," +
          (y * -0.045).toFixed(1) +
          "px,0) rotate(" +
          (y * 0.02).toFixed(2) +
          "deg)";
      }
      const vh = window.innerHeight;
      phones.forEach((p) => {
        const r = p.getBoundingClientRect();
        const raw = ((r.top + r.height / 2 - vh / 2) / vh) * -48;
        const off = Math.max(-24, Math.min(24, raw));
        p.style.transform = "translate3d(0," + off.toFixed(1) + "px,0)";
      });
    }
    requestAnimationFrame(frame);
  })();

  /* ---------- capture: typewriter → arrow → chips → confirm ---------- */
  function runCapture(el) {
    const text = el.querySelector(".capture__text");
    const chips = el.querySelectorAll(".chip");
    const full = (text && text.dataset.full) || "";
    let i = 0;

    (function type() {
      if (!text) return finish();
      text.textContent = full.slice(0, i);
      if (i < full.length) {
        const pause = full[i] === " " ? 46 : 24;
        i++;
        setTimeout(type, pause);
      } else {
        setTimeout(finish, 260);
      }
    })();

    function finish() {
      el.classList.add("show-arrow");
      chips.forEach((chip, n) =>
        setTimeout(() => chip.classList.add("is-in"), 240 + n * 150)
      );
      setTimeout(() => el.classList.add("is-done"), 240 + chips.length * 150 + 140);
    }
  }

  /* ---------- spaces: auto-flip School → Personal → School once ---------- */
  function runSpaces(el) {
    const show = (which) => {
      el.querySelectorAll(".space__tab").forEach((t) =>
        t.classList.toggle("space__tab--active", t.dataset.tab === which)
      );
      el.classList.toggle("show-personal", which === "personal");
    };
    setTimeout(() => show("personal"), 1000);
    setTimeout(() => show("school"), 2300);
  }

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
