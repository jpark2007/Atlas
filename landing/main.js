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

/* SUPPORT_ENDPOINT — the support page's form. Files the message as a bug_reports
   row (platform "web"), landing in the same owner dashboard as in-app reports. */
const SUPPORT_ENDPOINT =
  "https://jxrmozhgsebwtbdleyxp.supabase.co/functions/v1/support-request";

const COPY = {
  idle: "Notify me",
  sending: "Adding you…",
  success: "You're in. We'll email you when there's news worth sharing.",
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
    .querySelectorAll(".hero__title, .feature__title, .band__title, .waitlist__title")
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

/* ---- support form ---------------------------------------------------
   Same shape as the waitlist: honeypot in, one status line out. Present only
   on support.html, so bail quietly everywhere else.
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
