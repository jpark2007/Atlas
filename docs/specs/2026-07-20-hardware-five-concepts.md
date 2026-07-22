# 2026-07-20 — Atlas hardware: 5 concepts, one page each

Quick comparison sheet for the Jonah discussion. Dispatch/Standfile numbers come from the
hardware lens in `2026-07-20-v2-ideas.md`; Totem, Card, and Wall Calendar are new estimates
in the same spirit. **All costs are low-volume (100–500 unit) planning numbers — price-check
before committing to anything.** The life-size split-flap ("Marquee") is already killed
(BOM $450–650, retail $599–799 — category error vs a $99/yr app) and is deliberately NOT
one of the five; concept #5 is its affordable replacement.

Cert rule of thumb (from the v2 doc): any radio must be a pre-certified module (ESP32/Nordic)
→ ~$1.5k FCC verification per product. No radio + no battery = no cert file at all.

---

## 1. Atlas Totem — desk object showing "the one thing now"

A small anodized-aluminum wedge (or walnut block) on your desk with an e-ink face that shows
exactly one thing: the current time-block / next deadline, pulled from Atlas over WiFi.
Glanceable, silent, no notifications.

- **Size:** ~100 × 80 × 30 mm wedge, ~150–200 g.
- **Materials:** CNC or extruded anodized aluminum shell (walnut variant later), 4.2" e-ink
  panel (~$15–20), ESP32 WiFi module, USB-C powered (no battery = simpler, always-on desk use).
- **BOM:** ~$40–60. **Retail:** $99–129.
- **Cert:** ~$1.5k (modular WiFi).
- **Why it works:** the physical version of the software Today Card; e-ink + metal reads
  premium; no moving parts.
- **Risk:** "why not just glance at my phone" — lives or dies on the aesthetic.

## 2. Atlas Card — pocket e-ink day card

A credit-card-inspired e-ink card (realistically ~100 × 65 × 6 mm — true credit-card thickness
isn't feasible cheaply) that you sync in the morning (USB-C or BLE) and carry. Shows today's
schedule + top 3 tasks; the image persists with zero power. This is the "e-ink day card" Drew
already liked in the v2 pass — plug-in charging confirmed acceptable.

- **Size:** ~100 × 65 × 6 mm, ~40 g.
- **Materials:** 2.9–3.7" e-ink panel (~$8–15), nRF52/ESP32-C3 BLE module, small LiPo or
  supercap, aluminum unibody frame + glass.
- **BOM:** ~$25–40. **Retail:** $59–79.
- **Cert:** ~$1.5k (modular BLE) + battery shipping compliance if LiPo.
- **Why it works:** cheapest *connected* object; e-ink's "image stays with no power" is the
  whole magic trick; fits a pocket/laptop sleeve.
- **Risk:** syncs once a day or it's stale; thinness expectations vs engineering reality.

## 3. Dispatch — thermal receipt printer (the v2 hero pick)

Palm-sized anodized thermal printer. Prints the Sunday week-in-review receipt, a morning
day-dispatch, and focus-session stamps. Carried over verbatim from the v2 doc where it's the
**PURSUE (hero)** pick.

- **Size:** ~90 × 90 × 60 mm.
- **Materials:** anodized aluminum shell, off-the-shelf 58 mm thermal mechanism, ESP32 WiFi,
  USB-C power. Paper is commodity (~$0.60/roll) — margin is the hardware, not refills.
- **BOM:** ~$80–110. **Retail:** $149–179.
- **Cert:** ~$1.5k (modular WiFi).
- **Why it works:** ritual + shareable physical artifact; the software weekly receipt
  validates demand before any tooling is paid for.
- **Risk:** thermal fades (delight object, not archive); jammed printer = unplugged printer.

## 4. Standfile — stand + paper day-card refills (the no-cert gateway)

A machined/anodized aluminum stand that holds a printed day card (from Dispatch, or cards you
print/write yourself), plus cotton-rag refill decks ($9/60). Zero electronics.

- **Size:** ~80 × 60 × 40 mm stand; A7-ish cards.
- **Materials:** anodized aluminum (or brass accent), cotton-rag card stock.
- **BOM:** ~$14–26. **Retail:** $39–49.
- **Cert:** **none** — no radio, no battery. Safest possible first ship.
- **Why it works:** gets a branded object on desks for near-zero regulatory/engineering risk;
  natural Dispatch accessory.
- **Risk:** standalone it's "a $45 stand for cards I make myself" — only sings paired with
  Dispatch or the software Today Card.

## 5. Atlas Wall Calendar — the affordable version of the life-size one

What the killed Marquee split-flap wanted to be, at 1/4 the cost: a framed **13.3" e-ink
panel** on the wall showing the month/week view from Atlas, refreshed a few times a day over
WiFi. Silent, paper-like, no glowing screen in the room.

- **Size:** ~310 × 240 × 15 mm framed (roughly an iPad-Pro-sized "paper" calendar);
  10.3" variant (~$220 retail) if the panel price kills it.
- **Materials:** 13.3" e-ink panel (**$100–150 at low volume — this panel IS the product
  cost**), aluminum or oak frame, ESP32 WiFi, USB-C or flat wall cable.
- **BOM:** ~$180–260. **Retail:** $349–399.
- **Cert:** ~$1.5k (modular WiFi).
- **Why it works:** the only concept that's *shared/ambient* (roommates, family) rather than
  personal; closest to the original "electric calendar on the wall" dream at a shippable price.
- **Risk:** still the most expensive of the five; competes with $300 LCD calendars (Skylight)
  that have color and touch — the pitch has to be "paper, not another screen."

---

## Comparison at a glance

| # | Concept | Size class | BOM | Retail | Cert cost | Radio/battery |
|---|---------|-----------|-----|--------|-----------|---------------|
| 1 | Totem | palm desk object | $40–60 | $99–129 | ~$1.5k | WiFi, no batt |
| 2 | Card | pocket | $25–40 | $59–79 | ~$1.5k | BLE + LiPo |
| 3 | Dispatch | palm desk object | $80–110 | $149–179 | ~$1.5k | WiFi, no batt |
| 4 | Standfile | palm desk object | $14–26 | $39–49 | none | none |
| 5 | Wall Calendar | wall, ~A4+ | $180–260 | $349–399 | ~$1.5k | WiFi, no batt |

**Standing decisions that frame this:** v2 doc's line strategy is Dispatch + Standfile as the
disciplined two-SKU launch (each extra radio = another cert file to maintain); hardware is
gated behind the "get users before hardware" metric to be agreed with Jonah; software Today
Card wallpaper ships first as the cheap demand test for any of these.
