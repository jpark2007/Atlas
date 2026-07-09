# Notes + Gmail + Monetization — Decision Doc

**Status:** Decisions pending (you + partner). Last updated 2026-06-29.
**Purpose:** Capture the full reasoning so you can take it to your partner, make the calls in
the "Decisions pending" section, and come back. Nothing here is built yet.

---

## TL;DR — the unified picture

Notes↔Drive and Gmail capture turn out to be **one decision, not two**, because they share a
single Google OAuth app:

- **One OAuth app → one publishing status → one security audit (CASA).**
- **CASA is priced per *app*, not per *scope*.** So the moment Gmail (a restricted scope) commits
  you to CASA, adding `drive.readonly` for the "watch a folder" Notes model costs **$0 extra audit**.
- Therefore: go **restricted scopes** for both (`gmail.readonly` + `drive.readonly`), do **one ~$540/yr
  CASA** at monetization, and ride a **free Testing-mode runway** until you're ready.
- **Money flows only when you monetize.** The validate-with-friends phase costs ≈ **$0**.

---

## The core insight: one app, one audit, one runway

Both features authenticate through the same Google Cloud OAuth client. That client has a single
publishing status (Testing vs Production) and a single verification/audit path. Consequences:

- You can't publish "just the Drive part" — the restricted Gmail scope drags the whole app into the
  CASA process when you publish.
- But the audit covers the whole app at once, so once you're paying for it, **use the best
  (restricted) scopes everywhere.** This **dissolves the old reason to prefer `drive.file`** (which
  existed only to dodge the audit — see `notes-drive-architecture-decision.md`).

---

## Established facts (verified against current Google policy, 2026)

- **Gmail read access = a "restricted" scope.** No body-reading Gmail scope avoids "restricted"
  (`gmail.metadata` gives headers only, no body/snippet — useless for task extraction).
- **"Watch a folder" Notes = `drive.readonly` = also restricted.** Proven live with the localhost
  picker test (`docs/experiments/picker-folder-cascade-test.html`): `drive.file` + pick a folder sees
  *nothing* inside it; `drive.readonly` + pick a folder sees *everything, including files added later*.
- **CASA Tier 2 ≈ $540/yr** via TAC Security (Google's preferred/negotiated lab; others $800–$1,500).
  It's a **DAST scan + self-assessment questionnaire**, *not* a pen-test (that's Tier 3). The old
  "$15k–$75k" figures are the legacy/Tier-3 regime — not what a small app pays.
- **CASA timeline:** assessment ~1–3 weeks; full verification ~6–12 weeks (needs verified domain,
  privacy policy, public homepage, a YouTube video of the consent flow, per-scope justification).
- **Testing mode is free and indefinite, capped at 100 users.** The cap is **lifetime and can't be
  reset** — but it **only counts users who go through Google consent.** Free local-app users who never
  connect Google **don't count.**
- **Testing mode revokes refresh tokens after ~7 days.** This is a property of Testing mode (External
  user type), *not* Gmail — your current Calendar/Drive auth is already subject to it. It doesn't break
  silently: the app catches the `invalid_grant` and shows a one-click "Sign in again"; the background
  scan just pauses until you do. Because all scopes share one consent/token, expiry drops the **whole
  Google connection at once (Calendar included)**, and one re-auth restores everything. **It vanishes
  the moment you publish/verify.**
- **Our server backend means CASA definitely applies.** CASA is triggered by user data flowing through
  *your own server*. A strictly client-side app *might* skip the assessment — but Atlas's Supabase
  backend (server-side tokens + AI processing) re-triggers it. No exemption for us.

### Scope/audit comparison

| | `drive.file` | `drive.readonly` | `gmail.readonly` |
|---|---|---|---|
| Tier | non-sensitive | **restricted** | **restricted** |
| Capability | create + pick-to-import only | watch a folder, incl. future files | read mail bodies |
| CASA audit | none | **annual (~$540)** | **annual (~$540)** |
| 100-user cap (unverified) | none | yes | yes |
| **Cost when bundled with Gmail** | — | **$0 extra (same audit)** | the audit driver |

---

## Timeline / runway — the money question

- **Testing mode = $0, indefinite, ≤100 *Google-connected* users.** Only tax: weekly one-click
  re-consent. Fine for you + a tiny circle; not viable for real users.
- **CASA is the *gate* to publishing past 100 users — not a publish-now-audit-later grace.** You must
  pass it (get the "Letter of Assessment") to unlock >100 users. Start ~6–12 weeks before you hit the wall.
- **The "12 months" is the *recert* clock** — it starts the day you *pass*, and you re-audit annually
  from that date to keep the scopes.
- **Natural alignment:** free local tier is uncapped, so you hit the 100 cap right around ~100 *paying
  connected* users — i.e., exactly when revenue justifies the ~$540 audit + ~$60/mo infra.

---

## Architecture — Gmail → Tasks (converged)

> **Runner:** Supabase **pg_cron + a chunked Edge Function** (not trigger.dev). Everything already
> lives in Supabase (secrets, the existing `capture` AI Edge Function, the token store). Supabase free
> tier bills by *invocation count* (500K/mo), so chunking many accounts per invocation stays free far
> longer than trigger.dev's *duration-based* $5 credit. trigger.dev stays the documented additive
> upgrade for if frequent polling at thousands of accounts ever hurts.

Pipeline, per account, per hourly tick:

1. **Gmail History API (incremental):** store `last_history_id`; fetch only messages new since last
   scan. Never re-read the inbox. (This is the biggest cost saver and the "multiple emails per person"
   answer.)
2. **Regex pre-filter (free):** drop promo / newsletter / `no-reply@` / calendar-invite /
   unsubscribe-header mail *before* any LLM call.
3. **One batched LLM call per account:** pack survivors (subject + first ~500 chars, quoted
   replies/sigs/HTML stripped) into a single OpenRouter request → array of candidate tasks.
4. **Thread dedup** by `threadId` so a long reply chain is one tracked thread, not N calls.
5. **First-scan cap on connect** (e.g., last 7 days / 50 emails) so onboarding a fat inbox isn't a
   one-time token bomb.

UX / data:
- **Per-account on/off switch** (one Atlas login can link several Gmail accounts).
- Drafted tasks **auto-added, tagged `from email`, source-attributed**, into **one shared "From Email"
  tray**, each tagged with which account it came from.
- **Daily morning digest = a review view** over that tray (brief, dismissable, optional macOS
  notification). Digest is a surface, not the creation mechanism — capture is continuous (hourly).
- **Server-side encrypted refresh token** (Supabase) so the cron can run while the app is closed.
- **Model is configurable** (`EMAIL_MODEL` env var) via OpenRouter — start with GPT-4o-mini (proven in
  the existing `capture` fn) or Gemini 2.0 Flash-Lite (cheap + reliable). Don't hardcode.

Cost estimate (300 heavy inboxes = 100 users × 3 accounts, ~12 actionable emails/account/day):
- **OpenRouter:** ~$8/mo daily-batched, ~$12/mo hourly (difference is the repeated instruction prompt).
- **Gmail API:** $0.
- **Supabase:** free tier holds at hourly (≈216K invocations/mo < 500K, even one-per-account).
- Token cost scales linearly with the "actionable emails/day" knob; it's a rounding error vs revenue.

---

## Architecture — Notes ↔ Drive (direction set, full spec to follow)

- **`drive.readonly` folder-watch model:** user picks a folder once → Atlas auto-syncs everything in
  it, including files added later, and reflects deletions. The "dream" from the localhost probe.
- Justified because Gmail already commits us to CASA, so the restricted scope is free to add.
- Detailed design (sync triggers, conflict UX, Markdown interchange, search index) gets its own spec.

---

## Monetization

- **Model: freemium + subscription**, so cost sits behind revenue.
  - **Free tier (unlimited, uncapped):** local tasks, calendar, notes, manual capture, Apple Calendar.
    No Google scopes → doesn't count toward the 100 cap, can go public anytime.
  - **Atlas Pro (paid):** the connected/AI features — Gmail→tasks, Notes↔Drive sync, AI capture,
    Google Calendar write-back. This tier is what flips on when CASA passes + OAuth publishes.
- **Price:** ~$8–12/mo or ~$80–100/yr (annual discount). 14-day Pro trial.
- **Billing:** **Polar** (merchant-of-record — handles tax/VAT, dev-friendly).
- **Distribution:** direct **notarized DMG** (no Mac App Store, keep the full cut). Future **iOS app =
  login-only companion**, no purchases through Apple (Spotify/Netflix model). *Caveat:* Apple
  anti-steering rules mean the iOS app generally can't prompt/link users to subscribe externally —
  already-subscribed users just sign in. (Mobile is parked anyway.)
- **Alignment:** the exact features that cost money (Gmail/Drive/AI) are the exact features behind the
  paywall that fund CASA + infra.

---

## DECISIONS PENDING (you + partner)

1. **Go restricted (`gmail.readonly` + `drive.readonly`) + accept one CASA?**
   *Recommendation: yes* — Gmail forces CASA regardless, so `drive.readonly` folder-watch is free to
   add and gives the best UX. (Alternative: stay `drive.file` for Notes to keep Notes audit-free — but
   that only helps if you *don't* ship Gmail.)
2. **Distribution posture:** pure consumer (this plan) vs *also* a per-org Workspace/B2B edition (the
   partner's Internal-app model — free, no audit, no cap, *per org*). Not mutually exclusive.
3. **Monetization shape:** confirm freemium split, price point, and Polar as the biller.
4. **Client-side-only CASA exemption:** partner was doing a research pass. Our server backend almost
   certainly moots it — confirm and close.
5. **Verify early vs ride Testing:** do CASA sooner to kill the weekly 7-day re-consent, or stay in
   free Testing as long as the small circle tolerates it?

## Open build questions (not blockers — resolved during implementation)

- Gmail scope `readonly` vs `modify` (do we want to mark-as-read / label processed mail?).
- Exact server-side token encryption mechanism (Supabase Vault / pgsodium).
- Data-deletion endpoint (needed for CASA anyway; also powers "disconnect account + wipe").
- First-scan window cap value.
- Relevance = regex pre-filter + model-decides-actionability (direction confirmed).

---

## Sources

- [Restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Manage app audience / 100-user cap](https://support.google.com/cloud/answer/15549945)
- [Using OAuth 2.0 (testing-mode token expiry)](https://developers.google.com/identity/protocols/oauth2)
- [CASA Tier 2 process — App Defense Alliance](https://appdefensealliance.dev/casa/tier-2/tier2-overview)
- [CASA providers & pricing](https://www.switchlabs.dev/post/casa-tier-2-tier-3-security-review-providers-pricing-and-the-cheapest-option)
- [CASA 2025 overview](https://deepstrike.io/blog/google-casa-security-assessment-2025)
- Prior Atlas docs: `notes-drive-architecture-decision.md`, `archive/google-integration-v2.md`, `specs/08-email-capture.md`
