# Atlas landing page

Static, no build step. Deploy the `landing/` folder to Vercel (or any static host) — `index.html`, `privacy.html`, `terms.html` share `styles.css` + `main.js`; open `index.html` locally and it just works.

**Waitlist endpoint:** set `WAITLIST_ENDPOINT` at the top of `main.js` to your deployed Supabase function URL (`https://<project-ref>.supabase.co/functions/v1/waitlist`). The form POSTs `{ email }` there.

**Staging → real Supabase:** `supabase-staging/` is a copy only, deployed by nobody from here. To ship it: move `supabase-staging/functions/waitlist/` into the app's `supabase/functions/`, move `supabase-staging/migrations/0001_waitlist.sql` into `supabase/migrations/` (rename with a fresh timestamp), then `supabase db push` and `supabase functions deploy waitlist --no-verify-jwt` (public form, no auth header).
