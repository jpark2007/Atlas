# Handoff — 2026-07-16 late night · DMG finish line + web Sign-in-with-Apple

**For the next Claude session.** Read this whole doc first. Standing rules (non-negotiable,
from memory): ALL subagents on **Opus** (Sonnet where overkill) — NEVER Fable; the main
loop orchestrates/reviews/deploys/verifies/commits, never writes implementation code;
Mac build check = `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug
-destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` (mobile: scheme
`AtlasMobile`, `generic/platform=iOS Simulator`); UI is never "done" until Drew visually
confirms; migrations via `supabase db push --linked < /dev/null`, functions via
`supabase functions deploy <fn> --project-ref jxrmozhgsebwtbdleyxp` (**waitlist must
keep `--no-verify-jwt`**); push to git when a wave completes.

## Where things stand (all pushed, tree clean at handoff)

Tip of main includes tonight's three completed waves — all **deployed to prod**:

1. **UI-feedback wave** (@3c81db4): PROJECT COLOR popover, sidebar project dots,
   click-to-edit project title, per-project Add Task, recurring-event collapse on space
   pages, Canvas honest colors + course↔class mapping (migration 0032, course picker on
   class pages), real Atlas logo on the landing site + 120px consent PNG.
2. **Polish-2 wave** (@1c21491): sign-in flicker REAL fix (it was MockData pre-render,
   never a disk cache — UI gated on `loadedUserID == auth user`; menu-bar popup gated
   too), read-only date fields as plain text, 32-swatch + hex color picker (hex parsing
   in AtlasCore `ColorToken`), Help & Tips in both Settings, mobile batch (caption white
   bands, overscroll 300→120, FAB 96→68, month-popup day list + "Visit this day").
3. **Security/perf wave** (@6226936): full audit run + all High findings fixed —
   capture endpoint real JWT auth + 8k input cap, DB rate limiter (migration 0033,
   per-endpoint budgets), drive-import 50-file cap + 10MB doc refuse, SSRF `url_guard`
   on Canvas fetches, cron gate = exact service-key only, 0034 revokes, sessions +
   Canvas token → Keychain (one-time UserDefaults adoption, no logout), landing CSP/
   HSTS/`.vercelignore` + waitlist honeypot `referral_code` (verified live), ⌘K perf
   fix (was re-searching on every hover; now cached per query edit).
4. **After that**: mobile Settings hub (@ merge "settings hub" — Account/Integrations/
   Notifications/General/Help & Tips subpages with chevrons) and the DMG work below.

Site live at **https://atlaslm.vercel.app** (Drew renamed the domain 07-16; the old
`atlas-landing-woad.vercel.app` now 307-redirects there — same Vercel project
`atlas-landing`, `landing/.vercel/project.json` link still correct, deploy as before).
Hardened deploy verified: headers live, `supabase-staging/` 404s, honeypot present.
NOTE: `atlas-landing.vercel.app` (no suffix) is a DIFFERENT project — never deploy there.

## DMG status — one script-run from done

- `scripts/release-dmg.sh` exists and works: xcodegen → Release archive → Developer ID
  sign → verify → DMG → notarize → staple → Gatekeeper check. Flags: `--skip-notarize`,
  `--notarize-only <dmg>`. Output `dist/Atlas-0.9.0.dmg`.
- Notary credentials: keychain profile **`atlas-notary`** exists and validated
  (created by Drew tonight).
- Developer ID cert in login keychain: `Developer ID Application: ANDREW ALEX KHALIL
  (2WA54D67Y8)`.
- **Sign In with Apple cannot ship in a Developer ID build — Apple policy**, confirmed
  via Apple's supported-capabilities table (ADP ✓ / Developer ID ✗) and DTS forum
  statements. We burned an hour on portal ping-pong before finding this: the portal
  happily shows SIWA on a Developer ID profile while generating profile files WITHOUT
  the entitlement. Do not retry the profile route.
- Resolution (MERGED, archive verified green): Release signs with
  `Atlas/Atlas-DeveloperID.entitlements` (= Atlas.entitlements minus applesignin), needs
  NO provisioning profile; Apple button hidden at runtime via
  `AuthService.appleSignInAvailable` (reads the binary's own signed entitlement).
  Debug/dev/iOS keep native SIWA untouched.

**To finish the DMG (next session, ~15 min):**
1. `./scripts/release-dmg.sh` (full run; notarization usually 2–15 min).
2. Copy `dist/Atlas-0.9.0.dmg` → `landing/downloads/Atlas.dmg` (dir exists, .gitkeep).
3. `cd landing && vercel deploy --prod --yes` — this also takes the already-committed
   download button + favicon live (current live site still shows "Coming soon", which
   is correct while no DMG exists — no dead link).
4. `curl -I https://atlaslm.vercel.app/downloads/Atlas.dmg` → 200, then
   download + open on a Mac to confirm Gatekeeper accepts (stapled).
5. Send Drew the link for Jonah.
   Consider whether to commit the DMG to git (it's a binary; committing to `landing/downloads/`
   is simplest for Vercel, but large-binary-in-git is ugly — Vercel deploys the working
   dir, so an uncommitted DMG in `landing/downloads/` still deploys; decide and be
   consistent about rebuilds).

## Slight issues / gotchas from tonight (read before touching)

- **iOS "cannot find KeychainStore in scope" build failure = stale DerivedData**, not a
  code bug. `rm -rf build` + `xcodebuild clean build` fixed it (CLAUDE.md gotcha
  re-confirmed; archive runs dirty the intermediates). Both platforms verified green
  after clean.
- **Portal change made tonight:** `com.atlaslm.Atlas` App ID's Sign In with Apple was
  switched from "grouped under AtlasMobile" to **primary App ID** (matches the
  `applesignin=Default` entitlement the app always shipped). Expected impact: none —
  but Drew should confirm Mac dev-build Apple sign-in still works on next launch. If
  Supabase ever rejects with an audience error, add `com.atlaslm.Atlas` to Supabase →
  Auth → Providers → Apple → authorized client IDs.
- A provisioning profile "Atlas Developer ID" exists in the portal and is installed
  locally (~/Library/MobileDevice/Provisioning Profiles/). It is now UNNECESSARY
  (harmless; ignore it).
- The DMG build embeds the real `Config/Secrets.xcconfig` (gitignored) — testers need
  nothing. Jonah still needs that file sent directly for his own dev builds.
- **DMG beta sign-in is email/password only** (Apple button hidden). Drew's own
  account is SIWA-created, so he can't log into the DMG build itself until web-SIWA
  lands — he tests with dev builds, fine. Fresh testers sign up with email.

## NEXT FEATURE (Drew approved direction): web-based Sign In with Apple for the DMG

Goal: DMG users get the Apple button back via browser flow (Supabase OAuth), like
Slack/Notion. Same team-scoped Apple user id → same Atlas account either way.

1. **Drew portal steps (walk him through click-by-click, verify each artifact
   immediately like tonight):** (a) Identifiers → new **Services ID** (e.g.
   `com.atlaslm.atlas.web`), enable Sign In with Apple, primary App ID =
   `com.atlaslm.Atlas`, register domain + return URL
   `https://jxrmozhgsebwtbdleyxp.supabase.co/auth/v1/callback`; (b) Keys → new key with
   Sign In with Apple → download the **.p8** (ONE-TIME download), note Key ID.
2. **Supabase dashboard**: Auth → Providers → Apple — set Services ID as client id,
   generate the client secret from the .p8 (Supabase docs have the JWT recipe; secret
   expires ≤6 months — note a renewal reminder), add both `com.atlaslm.Atlas` and the
   Services ID to authorized client IDs so native + web coexist.
3. **Client (Opus agent):** in `SignInView`/`AuthService`, when
   `appleSignInAvailable == false`, the Apple button (un-hide it) runs the web flow:
   Supabase `/auth/v1/authorize?provider=apple` in the browser → loopback/deep-link
   return → session tokens (mirror the existing Google-connect loopback pattern in
   `GoogleAuthService`). Careful with rule 5 / session handling: store via the same
   KeychainStore path.

## Drew owes / open

- Visual pass on tonight's everything (esp. title-edit, Add Task, course picker, hex
  picker, mobile settings hub, month popup, ⌘K feel after the caching change).
- Mobile TestFlight re-archive + upload (Xcode → AtlasMobile → Archive → Distribute)
  so Jonah/testers get tonight's mobile work.
- Audit leftovers accepted-for-now: verify Supabase Auth requires email confirmation
  (audit M4 — invite flow trusts JWT email); runner connection-ownership check (L2);
  `search_path` hardening (L3); `chmod 600` local secret files (L5).
- Perf deferred: month-view O(days×events) re-filter per render (top scaling risk);
  optional ⌘K body-prefix cap (Drew/Jonah semantics call).
- Later per memory: onboarding tutorial/tooltips; file-import-from-PC design (size
  caps, Supabase Storage bucket); Supabase Pro at ~100–200 real actives (free plan
  verdict: fine to ~300, egress is the first cliff; AWS credits = not worth it —
  decision: STAYING on Supabase).
