# Atlas — Setup & Manual Steps (for the two of us)

This is the list of things **only a human can do** — account creation, API keys, OAuth.
Everything else (schema, code, wiring) is handled in the app. Ordered by when we need it.

> Rule: **never commit keys.** They go in a local, git-ignored config (see "Secrets" at the bottom).
> `.gitignore` already blocks `.env`, `*.local`, `secrets.plist`, `Config/Secrets.xcconfig`.

---

## 1. Supabase  ← do this first (the backend)

This powers accounts, data sync, and hides our API keys.

1. Go to https://supabase.com → sign in with GitHub → **New project**.
2. Name it `atlas`, pick a region near you, set a strong DB password (save it).
3. Once it provisions, go to **Project Settings → API** and copy:
   - **Project URL** (e.g. `https://xxxx.supabase.co`)
   - **anon public key**
4. Paste both to me. I'll wire auth + the schema (Spaces/Projects/Tasks/etc.).
5. Later, in **Authentication → Providers**, we'll enable **Email** and **Sign in with Apple**.

**Free tier is fine** for us + early users. (Heads-up: a free project pauses after ~1 week of zero activity — won't happen once we use it daily.)

---

## 2. OpenRouter  ← for the AI brain (NL capture, bucketing)

1. https://openrouter.ai → sign in → **Keys** → create a key.
2. Add a little credit (GPT-4o-mini is very cheap).
3. **Do NOT put this in the app.** Paste it to me; it gets stored as a Supabase **Edge Function secret** so it's never in the client.

---

## 3. Google Cloud OAuth  ← Calendar sync is now LIVE; Drive/Gmail still to come

Powers Google Calendar sync (live), Notes ↔ Google Docs, Drive folders, and (future)
email capture. Done once for the whole app — every account just clicks "Connect Google".

1. https://console.cloud.google.com → new project `Atlas`.
2. **APIs & Services → Enable APIs**: Google Calendar API, **Google Docs API**
   (Notes ↔ Docs), Google Drive API, and Gmail API (the last two for future Drive
   folders / email capture).
3. **OAuth consent screen**: External, status **Testing**, add yourself + Jonah as
   test users (this avoids the "access blocked / app not verified" wall at consent).
4. **Credentials → Create OAuth client ID → Desktop app** (named e.g. "Atlas LM").
   The app uses the Authorization-Code-with-**PKCE** flow over a **loopback redirect**
   (`http://127.0.0.1:<ephemeral-port>`), so there is **no** Supabase/Web redirect URL
   to configure for this client.
5. Copy the **Client ID + Client Secret** → paste to me. They go in the **git-ignored
   `Atlas/Config/Secrets.xcconfig`** (fed into `Info.plist` at build time), NOT into
   committed source. For a Desktop client the secret isn't a hard boundary — PKCE is
   the real protection.

> Note: "Sign in with Google" for *user accounts* (if/when enabled) is a separate
> Supabase social-login OAuth client (Web type, Supabase redirect URL) — distinct from
> this Desktop client, which is only for the Calendar/Docs/Drive data integrations.

---

## 4. Canvas Calendar Feed  ← school assignments + due dates

> Our schools (Rutgers, Princeton) **disable student API tokens**, so Atlas uses the
> read-only **Calendar Feed** instead — no token, no admin needed. See
> [specs/2026-07-01-canvas-ics-sync-design.md](./specs/2026-07-01-canvas-ics-sync-design.md).

1. In your school's Canvas: **Calendar** (left nav) → scroll the right sidebar to
   **"Calendar Feed"** → copy the URL (`https://<school>/feeds/calendars/user_….ics`).
2. Paste it into Atlas → **Settings → Integrations → Canvas Calendar Feed URL**.
3. Each person does this for their own Canvas. The URL is a read-secret — treat it like a
   password (anyone with it can read your calendar).

---

## 5. Apple signing  ← per developer, via Secrets.xcconfig

- **Your team id is NOT in git.** `project.yml` reads `DEVELOPMENT_TEAM` from the
  git-ignored `Config/Secrets.xcconfig` — each developer builds with their own team.
  Setup (once): Xcode → **Settings → Accounts** → add your Apple ID (a **free**
  account is fine for local builds) → copy your Personal Team's **Team ID** → add
  `DEVELOPMENT_TEAM = <your team id>` to `Config/Secrets.xcconfig` → `xcodegen generate`.
- Without it, Xcode shows "requires a development team" — pick a team manually in
  Signing & Capabilities (that choice is wiped every `xcodegen generate`, hence the
  xcconfig).
- CLI builds don't need any of this: `xcodebuild … CODE_SIGNING_ALLOWED=NO`.
- Distribution is a **notarized DMG** (Developer ID, owner's paid account) — NOT the
  Mac App Store. End users never deal with teams/signing; this section is dev-only.
- Note: the global pill hotkey needs **App Sandbox OFF**, which limits Mac App Store
  distribution — fine for personal/direct distribution.

---

## Running the app (no account needed — works on mock data today)

```bash
cd "atlas life manager"
xcodegen generate            # regenerates Atlas.xcodeproj from project.yml
open Atlas.xcodeproj         # then hit ▶ Run in Xcode
```
Or build from CLI:
```bash
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

> `Atlas.xcodeproj` is git-ignored on purpose — it's generated. Commit `project.yml` + Swift source, not the project file. After pulling, run `xcodegen generate`.

---

## Secrets (where keys actually go)

- **Client (Swift):** only the Supabase **URL** + **anon key** (these are safe to ship). Stored in a git-ignored `Atlas/Config/Secrets.xcconfig`.
- **Server (Supabase Edge Functions):** OpenRouter key, Google client secret — set as Supabase secrets, never in the app. (Canvas uses a client-side read-only feed URL — no server secret.)

When you have the keys from steps 1–2, paste them here in chat and I'll place them correctly.
