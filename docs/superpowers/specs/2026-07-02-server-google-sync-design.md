# Server-Side Google Calendar Sync — Design

**Date:** 2026-07-02 · **Status:** approved to build (Drew waived review; spec is for Claude + agents)
**Ground truth:** `.superpowers/sdd/sync-architecture-brief.md` (file:line map of everything referenced here). Read it before implementing.

## Goal

Google Calendar ↔ Supabase syncs on a server schedule for ANY connected user — Mac, iPhone, and Google stay live-linked with nothing open. Seamless > featureful: no duplicates, no lost user edits, calm failure.

## What changes conceptually

Today: the Mac polls Google every 30s in-memory (`externalEvents`), never persists Google rows, and mirrors some Atlas events to Google (write-back). The phone reads Supabase only — so Google events don't exist for it.
After: a **Supabase scheduled function is the single owner of Google↔DB sync** (both directions). Google-origin events become real `events` rows. The Mac stops talking to Google entirely when server sync is on; both apps just read/write Supabase (which they already do well).

## Architecture (v1)

1. **Connect flow (v1 = Mac hands off):** Mac already completes desktop OAuth (loopback+PKCE) and holds a refresh token in Keychain. On "enable server sync" (Settings → Calendars), the Mac POSTs its refresh token to a new edge function `google-connect` (Supabase JWT auth), which stores it in **Supabase Vault** and upserts a `google_connections` row. The Mac then flips its local mode (below). Phone-only/web connect flow is a documented follow-up, not v1.
2. **Schema migration (BEFORE any sync runs):**
   - `google_connections`: `user_id uuid PK references auth.users`, `vault_secret_id uuid` (refresh token in Vault), `calendar_id text default 'primary'`, `sync_token text`, `last_synced_at timestamptz`, `status text default 'active'` (`active|error|revoked`), `last_error text`. RLS: owner can select status fields + delete (disconnect); token/vault access is service-role only.
   - Dedupe then constrain: delete older duplicates sharing `(user_id, google_event_id)` (keep newest `updated_at`/ctid), then `create unique index on events(user_id, google_event_id) where google_event_id is not null`.
   - `events.updated_at timestamptz default now()` + update trigger, if absent — needed for newest-wins.
3. **Sync runner:** `google-sync` edge function invoked by **pg_cron + pg_net every 5 minutes** (service key from Vault; chunk users, ~20/invocation, stagger). Per user:
   - Refresh access token (client id+secret of the existing desktop OAuth client as function secrets — valid for installed-app refresh tokens). On `invalid_grant`: mark `status='revoked'`, surface in app, never retry-loop.
   - **Pull:** `events.list(calendarId, syncToken)` incremental; on 410 GONE fall back to a full window (−30d…+365d) and store the new syncToken. Map → upsert `events` rows on `(user_id, google_event_id)`: Google-origin rows carry `google_event_id`, title/times/all-day/notes; space = the user's default/first space (server never guesses semantics). `status=cancelled` → delete the row **unless** it's an Atlas-origin mirror (see push), in which case clear its `google_event_id` instead (the Atlas event survives; Google-side deletion of a mirror un-mirrors, never destroys user data).
   - **Push (write-back):** Atlas-origin rows (`google_event_id is null`, user opted into mirroring — same setting the Mac used) created/updated since `last_synced_at` → insert to Google, write the returned id into `google_event_id`. Updates to already-mirrored rows → PATCH. **Newest-wins** on conflict: compare Google `updated` vs row `updated_at`; loser is overwritten, no merge (design decision B4 from the 2026-06-29 spec, finally implemented — the server IS the reconciler that spec wanted).
4. **Mac migration (the dedupe-with-Mac requirement):** one gate — `serverSyncEnabled` (read from `google_connections.status == 'active'` at bootstrap). When TRUE the Mac: stops the 30s Google polling, stops ALL write-back/backfill (`AppState.shouldWriteBack` short-circuits), stops reaping based on live Google reads, and stops merging in-memory `externalEvents` for Google (Google events now arrive as DB rows via normal `loadAll()` — `EventRow.toDomain()` already derives `source == .google`, and the existing refresh paths render them read-only-appropriately). When FALSE: exactly today's behavior. **Single-owner invariant: at no time do both the Mac and the server write to Google for the same user.** The unique index is the belt-and-suspenders behind it.
5. **Phone:** zero changes required — it already reads Supabase and refreshes on foreground/pull. Settings' "Syncs via your Mac" copy becomes "Synced automatically" when `google_connections.status == 'active'` (read via a small select; graceful fallback to current copy).

## Failure & trust

- Per-user isolation: one user's token failure never blocks the batch (try/catch per user, record `last_error`).
- Function-level: idempotent by construction (upsert on unique key) so a crashed run re-runs safely.
- Observability v1: `last_synced_at`/`last_error` on the connection row; Mac Settings shows them ("Last synced 2m ago" / calm error + Reconnect button).

## Out of scope (v1)

Web/phone-initiated OAuth connect; multiple calendars (primary only, column exists); attendee/recurrence editing (recurring events sync as Google sends instances — read-only mirror behavior unchanged); Gmail/Drive anything.

## Verification

- Migration: unit-testable SQL (duplicate-seed → dedupe → constraint holds).
- `google-sync`: deploy to prod ref `jxrmozhgsebwtbdleyxp`; integration-verify with Drew's real account — create in Google → row appears ≤5 min; create Atlas event with mirror on → appears in Google exactly once; delete the Google copy → Atlas event survives un-mirrored; edit both sides → newest wins. Phone shows Google events with Mac CLOSED (the original bug, dead).
- Mac: build green; with server sync on, network log shows zero Google API calls from the Mac.
