# Notes ↔ Google Drive — Architecture & Scope Decision

**Status:** Investigation complete, decision pending (partner reviewing). Last updated 2026-06-29.

**The question:** How should Atlas store project/class notes in Google Drive so they sync
both ways and can be edited in Google Docs — given Atlas will be **multi-user / public** and
wants to avoid Google's verification/audit wall where possible?

---

## What we proved live (two probes on a real Google account)

Test harness: `docs/experiments/picker-folder-cascade-test.html` (Google Picker + Drive API,
`drive.file` then `drive.readonly`).

1. **`drive.file` + pick a FOLDER → sees NOTHING inside it.** Picked "Pingry" (which contained a
   real Doc); `files.list` returned **0 files**. A picked folder grants only its *name + id*, never
   its contents.
2. **`drive.file` + pick a FILE → full access to that file.** Picked the Doc directly → listed and
   **read its content** fine. This is the "import" path: one pick per file (batch multi-select OK),
   then it syncs forever.
3. **`drive.readonly` + pick a folder → sees EVERYTHING**, including files never picked, files
   **added later**, and reflects **deletions**. Full "watch a folder" dream — but this is a
   **restricted** scope.

**Conclusion:** auto-discovering files in a folder is impossible on `drive.file` and requires a
restricted scope (`drive.readonly`/`drive`).

---

## The scope / audit reality (cited research, 2026)

| | `drive.file` | `drive.readonly` / `drive` |
|---|---|---|
| Tier | non-sensitive | **restricted** |
| Folder auto-watch | ❌ create + pick-to-import only | ✅ see everything, incl. future files |
| Verification | none | brand + restricted-scope review |
| Security audit (CASA) | **none** | **annual**, required for public apps |
| User cap (unverified) | none | **100 users, permanent project ceiling** |

**CASA cost (the audit):** Google charges **$0**; you pay a third-party assessor. For an app this
size it's **CASA Tier 2 ≈ $540–$2,000/year recurring** (TAC Security ~$540, a Google-discounted
rate, first-hand confirmed). The "$15k–$75k" figure in older blogs is the legacy/Tier-3 pen-test
regime — **not** what a small app pays.

**Verification timeline:** ~6–12 weeks. **Prereqs before applying:** verified domain, privacy
policy on that domain, public homepage, a YouTube video of the OAuth consent flow, per-scope
justification.

**The 100-user cap** is counted over the project's entire lifetime and **cannot be reset** — you
cannot grow past 100 users on a restricted scope until verification completes.

**Open wildcard:** CASA is triggered by user data flowing *through your own server*. A strictly
client-side / on-device app *might* skip the security assessment (still needs verification). Atlas
being native *could* matter — but a sync backend (multi-device, AI) almost certainly re-triggers it.
Unsettled; no official Google ruling as of 2026.

Sources: restricted-scope verification (developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification),
CASA tiering (appdefensealliance.dev/casa/casa-tiering), assessor pricing (switchlabs.dev,
meetorbis.com CASA write-up), 100-user cap (support.google.com/cloud/answer/7454865).

---

## The partner's (friend's) model — Workspace Shared Drives

**What he built:** As **admin of a Google Workspace org**, his app was **"Internal."** He created a
**Shared Drive** with: a root master + an archive; a folder auto-created per project; Google Docs
inside = notes, other files = view-only; archive holds everything but is hidden from the app.
Searchable. Auto-everything.

**Why it worked:** **Internal apps are fully exempt** from verification, CASA, and the 100-user cap.
Inside an org you get full `drive` scope and Shared Drives for free.

**Why it struggles public (his own worry, confirmed):**
1. Consumer Gmail users **don't have Shared Drives** (Workspace-only) → all data would live in
   *Atlas's* org, not the user's own Drive (cost, ownership, scrutiny; breaks "my notes in my Drive").
2. The Internal exemption **only covers users inside the org**. External consumer signups →
   app needs the verified restricted scope again → back to the audit.

**The path it actually points to — B2B / per-org:** Sell Atlas to a school/company (already on
Workspace) and deploy as an Internal/Marketplace app inside *their* org → his full auto-everything
model, **free, no audit, no cap**, per org. Strong fit for a student app (e.g. Pingry).

---

## Options on the table

- **A — `drive.file` (consumer, free forever):** Atlas-created notes sync both ways automatically;
  pre-existing/shared docs adopted once via batch picker; new external files need a re-pick. No audit,
  unlimited users, no infrastructure.
- **B — `drive.readonly` (consumer, full magic):** point at a folder, everything auto-syncs incl.
  future files. Free to 100 users, then ~$540–2k/yr audit + 6–12wk verification + domain/policy/video.
- **C — Per-org Internal (B2B, full magic, free):** the friend's Workspace/Shared-Drive model,
  deployed per school/company org. No audit. Data lives in the org, not personal Drives.

A and C are not exclusive — Atlas could ship consumer on `drive.file` **and** an org edition on Internal Workspace.

---

## Recommendation (current)

**Build on `drive.file` first.** It's free, unlimited, needs zero verification infrastructure, and
covers the everyday flow (notes born in Atlas) completely. It survives every later decision —
`drive.readonly` is purely additive, and a per-org edition is a separate deployment. Add the
restricted scope or the org edition later, once there's traction and the company footprint
(domain, privacy policy) you'll have by then anyway. Nothing is lost by waiting.

## Open items
- Confirm Atlas's primary distribution: public-consumer vs per-org (schools) vs both → picks A/B/C.
- "Nightshift" Workspace org — could it host an Internal deployment? Only helps if Atlas users are
  inside that org, not external consumers.
- Friend doing his own research pass; client-side-only CASA exemption worth a definitive check.
