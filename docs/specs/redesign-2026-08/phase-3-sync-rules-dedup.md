# Phase 3 — Sync Rules, Cross-Calendar Dedup, Apple-from-iPhone (agreed 2026-08-24)

Part of the 2026-08 redesign. Status: **rules agreed; display-time event dedup implemented (`collapsingDuplicates` — `AtlasCore/.../CalendarSync.swift:113`); task-level and syllabus-accept dedupe still open.**

## Sync direction rules (refined)

**Inbound: pull everything.** Google, Apple, Canvas/ICS all flow in so Atlas understands the real schedule. (Already true.)

**Outbound defaults — each with a visible Settings toggle:**

| Atlas object | Pushed to Google/Apple? | Notes |
|---|---|---|
| Events | **ON** | Existing behavior; space→Google-account routing stands |
| Work sessions | **ON** | Reserved time IS busy time. Title prefix below |
| Deadlines | **OFF** | Atlas-native; optional later |
| Tasks | **NEVER** | Not a toggle. Atlas is the home of tasks |

**Work-session mirror labeling:** external calendars can't carry our styling, so mirrored sessions get a title prefix — default **"Work: "** ("Work: English essay"). Human-readable over cryptic ("WS:" fails the normal-human test). Prefix template adjustable in Settings.

## Cross-calendar deduplication (hard requirement)

Problem: the same real-world event can arrive from multiple sources (school ICS + Google, Google + Apple, two ICS feeds). Today all dedup is same-external-ID only; nothing catches "same title + same/overlapping time."

Design (client-side, display-time — **required** because Apple events are never persisted, they're in-memory per view):

- New pure function in `AtlasCore/CalendarSync.swift` (alongside `excludingOwnMirrors`, the existing seam): `collapsingDuplicates(...)` over the merged native+external pool.
- **Match rule:** normalized-title similarity (case/whitespace/punctuation-insensitive, prefix-tolerant) AND time overlap (identical start, or overlap above a threshold for same-day events). Conservative: when unsure, show both.
- **Winner order:** Atlas-native > Google > Apple/ICS (prefer the writable copy). Collapsed duplicates aren't deleted — losers hide behind the winner; the shown event gets a small "also in …" source note in its detail popover.
- Server-side: also dedupe identical VEVENTs across *feeds* in `feeds-sync` (same UID/title+time arriving via two feeds currently creates two rows).
- Class-meeting attribution (Phase 1) runs on the deduped pool: a lecture arriving from school ICS and Google is one block, tagged to its Class.
- Unit-test heavy — this is pure-function territory; test with real-world near-miss cases (e.g. "BIO 201 Lecture" vs "BIO201 - Lecture").

## Apple Calendar from iPhone

Connecting Apple Calendar must be possible from **either** the Mac app or the iOS app (today it's Mac-only). iOS gains the EventKit connect + read path; same display-time merge/dedup rules apply. Write-back settings remain device-local per existing design.

## Account deletion hygiene (settled, from same discussion)

- **Add Sign in with Apple token revocation** to the delete-account edge function (App Store guideline 5.1.1(v) — do BEFORE App Store submission).
- Clear local leftovers on account deletion: Mac capture-history JSON, iOS pending-capture queue UserDefaults. "Clean and proper" is the bar.
- Confirmed behavior: delete → cascade wipe → re-sign-in with Apple = fresh account with starter seed. This is the supported "reset all my data" path.
