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

## 3. Google Cloud OAuth  ← later (Google Calendar / Drive / Gmail)

Needed when we add Google Calendar sync, Drive folders, and email capture.

1. https://console.cloud.google.com → new project `Atlas`.
2. **APIs & Services → Enable APIs**: Google Calendar API, Google Drive API, Gmail API.
3. **OAuth consent screen**: External, add yourself + Jonah as test users.
4. **Credentials → Create OAuth client ID** → Web application. Add the Supabase redirect URL (I'll give you the exact one).
5. Copy the **Client ID + Client Secret** → paste to me (stored server-side).

---

## 4. Canvas token  ← later (school assignments + classes)

1. In your school's Canvas: **Account → Settings → Approved Integrations → + New Access Token**.
2. Name it `Atlas`, generate, copy it immediately (shown once).
3. Paste to me (stored server-side). Each user does this for their own Canvas.

---

## 5. Apple signing  ← only when running on a real iPhone / distributing

- For now the Mac app runs locally unsigned (we build with signing off).
- When you want it on your iPhone or shared: open `Atlas.xcodeproj` in Xcode →
  target **Atlas → Signing & Capabilities** → check **Automatically manage signing** →
  pick your Apple ID team. (Free Apple ID works for personal devices.)
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
- **Server (Supabase Edge Functions):** OpenRouter key, Google client secret, Canvas tokens — set as Supabase secrets, never in the app.

When you have the keys from steps 1–2, paste them here in chat and I'll place them correctly.
