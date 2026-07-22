# 2026-07-20 — Atlas hardware one-pager: the Card + the Dial

Two NFC objects, both passive (no battery, no radio, no firmware, no FCC cert file).
Positioning per Drew: **companions to the app, sold slightly above production cost** — the
hardware exists to enhance the app's appeal, not to be a margin line. Not standalone
products, not a plan bonus. Supersedes the 5-concept sheet
(`2026-07-20-hardware-five-concepts.md`) for the Jonah conversation.

Market check: **Bloom Card** ($39, Shark Tank, 3k+ reviews, 50k+ customers, plus a $59 Pod
and a dial) proves the "NFC object locks your apps" category. Their card must carry their
whole business; ours rides a $99/yr app — that's why near-cost pricing is a weapon they
can't copy.

---

## Behavior rules (shared brain, lives in the app)

- **Locking** uses Screen Time / FamilyControls — the hard block is real, not a nudge.
- **Committed timers are sealed.** If you set 15 min, the card/dial can NOT end it early.
  The tap only exits *open-ended* locks.
- **3 emergency bypasses per month** override anything. (Maybe: earn one back via
  completed focus hours — decide later.)
- **Stopwatch mode** (Drew 07-20): a tap can also start an *open* session — counts up like
  a stopwatch until you tap again to unpause/end. For "I'm working until I'm done" days.
- **Auto-lock from class blocks** = opt-in settings toggle ("Guard my class blocks"),
  default OFF. Concept liked, not committed.
- Unlock screen shows Atlas context ("paper due in 14h") — the thing Bloom can never say.

---

## 1. The Atlas Card

Wallet card. Verbs: (a) key to your phone lock, (b) tap-in/out stopwatch sessions,
(c) social handshake — the tag carries a URL, so tapping it on ANYONE's phone (no Atlas
installed) opens schedule-share / join-my-space.

**Production reality:** a full-metal card blocks NFC. Options, per-unit at ~500 units:

| Build | Feel | Unit cost |
|-------|------|-----------|
| Matte-black PVC, custom print, NTAG213/215 | Bloom-equivalent | ~$0.60–1.50 |
| Metal-composite hybrid (metal face, antenna layer), laser engraved | premium, heavy | ~$3–6 |
| Stainless w/ chip window | maximal | ~$8–12 — skip for v1 |

Plus sleeve/packaging ~$1–2. **Landed cost ~$3–8 (composite build) → sell $10–15.**
No cert, no tooling, sample runs in ~2 weeks from standard card vendors.

## 2. The Atlas Dial ("the Totem")

Palm-size puck. **Ritual: twist the dial to a duration, flip it over, tap your phone on
it → a sealed focus session starts.** The flip is the commitment gesture (screen-side
down = phone parked on top of it, face down, for the session).

**How it stays passive:** the dial rotates an internal disc holding 4–6 NTAG stickers;
the selected position aligns one tag under the tap window. Phone reads "45 min" because
the *mechanism* chose which tag it can see. No sensors, no battery — the electronics are
in the phone, the object is pure machining.

**Production, per-unit at ~250–500 units (CNC, no injection tooling for v1):**

| Part | Cost |
|------|------|
| CNC aluminum body + rotating disc (2 parts, anodized) | ~$10–18 |
| Detent (ball + spring), NTAG stickers ×6, base pad | ~$2–3 |
| Packaging | ~$2 |

**Landed ~$14–23 → sell $29–39.** Injection-molded version later cuts unit cost ~60% but
needs $3–8k tooling — volume decision, not a v1 decision. No cert (passive tags only).

---

## Open items

- Flip detection is implicit (you tap after flipping) — the flip itself isn't sensed.
  Fine for v1; honest limitation.
- Duration steps on the dial: propose 15 / 25 / 45 / 60 / 90 / ∞(stopwatch).
- Card NFC on the social verb needs one hosted URL per card (unique ID printed at
  encode time) — trivial server-side, decide URL scheme before ordering.
- Bloom comparison for the pitch: they sell the lock; we sell the *life manager with a
  physical key* — schedule/deadline context, session data feeds focus stats + weekly
  receipt, and near-cost pricing.
