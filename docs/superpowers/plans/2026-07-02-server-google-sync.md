# Server-Side Google Calendar Sync — Implementation Plan

> Executed via subagent-driven development, Opus implementers. Spec: `docs/superpowers/specs/2026-07-02-server-google-sync-design.md`. Architecture ground truth (file:line map of ALL Mac call sites, token flows, schema): `.superpowers/sdd/sync-architecture-brief.md` — every implementer reads the sections named in its task.

**Goal:** Google ↔ Supabase sync runs server-side on a 5-minute cron for any connected user; the Mac stops talking to Google when server sync is active; no duplicates ever (DB-enforced).

## Global Constraints

- Repo: `/Users/drewkhalil/Documents/atlas life manager` (quote paths — spaces).
- NEVER stage Drew's uncommitted files: entitlements ×2, `AtlasMobileWidgets/SharedSnapshot.swift`, `project.yml`, `AtlasMobile/Assets.xcassets/`.
- Supabase project ref `jxrmozhgsebwtbdleyxp`; deploy functions with `supabase functions deploy <name> --project-ref jxrmozhgsebwtbdleyxp`; migrations live in `supabase/migrations/` (follow existing numbering) and apply with `supabase db push` — if the CLI isn't linked/authed for db push, STOP and report (Drew or controller runs it).
- Secrets via `Deno.env.get` (set with `supabase secrets set`); tokens at rest in Supabase Vault, service-role access only. NEVER commit or print a token/secret value; redact in reports.
- Mac build must stay green: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`. AtlasCore: `cd AtlasCore && swift test` (26 green today).
- Single-owner invariant (spec §4): no code path may let both Mac and server write to Google for one user.
- The sync runner must be idempotent per run and isolate per-user failures (try/catch per user, `last_error` recorded).

---

### Task 1: Schema migration — connections, dedupe, uniqueness, updated_at

**Files:** Create `supabase/migrations/<next>_google_sync.sql`.

Per spec §Architecture-2, in one migration: `google_connections` table (+RLS: owner may `select` non-secret columns + `delete`; all else service-role), events dedupe (delete older rows sharing `(user_id, google_event_id)`, keep the newest by `updated_at`/ctid), partial unique index `events(user_id, google_event_id) where google_event_id is not null`, `events.updated_at` column + `moddatetime`-style trigger if absent (check migrations 0001-000N first for what exists — brief §3). Also `tasks` is untouched this project. Apply with `supabase db push`; verify by seeding two fake-dup rows in a rollback-able check or by querying the index exists (`pg_indexes`). Commit: `feat(db): google_connections, event dedupe + uniqueness, updated_at trigger`

### Task 2: `google-connect` edge function

**Files:** Create `supabase/functions/google-connect/index.ts`.

POST `{refreshToken}` with a real Supabase JWT (verify via `auth.getUser` with the anon/service client — NOT presence-only like capture; this handles a credential). Store the token as a Vault secret (`vault.create_secret` via service-role RPC), upsert `google_connections` (`user_id`, `vault_secret_id`, `status='active'`). Also accept `DELETE` → disconnect (status='revoked', delete vault secret). Deploy + curl-verify both verbs with a test JWT (redact tokens in the report). Commit: `feat(fn): google-connect — vault-stored refresh token, connect/disconnect`

### Task 3: `google-sync` edge function (the runner)

**Files:** Create `supabase/functions/google-sync/index.ts` (+ small shared helpers file in the same dir if warranted).

Per spec §Architecture-3 exactly: batch active connections (limit ~20, oldest `last_synced_at` first); per user — Vault-read refresh token → access token (`GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` secrets; `invalid_grant` → status='revoked'); incremental `events.list` with stored `sync_token`, 410 → full-window resync (−30d…+365d); upsert on `(user_id, google_event_id)` (Google-origin rows: title/start/end/all-day/notes; space = user's first space by created_at — read spaces table; never overwrite `space_name` on existing rows); cancelled → delete row UNLESS it has Atlas-origin markers (mirror: row existed with `google_event_id` set by push — track with `origin` inference per brief §5; simplest robust: rows the server itself created from Google get deleted, rows whose `google_event_id` the push path set get un-mirrored by nulling it — persist which via a new `google_origin boolean` column? NO new columns beyond migration Task 1 — decide from the brief's duplicate-risk matrix and document in code); push Atlas-origin mirror-enabled rows updated since `last_synced_at` (insert → write back `google_event_id`; update → PATCH; newest-wins by comparing timestamps). Auth: the function runs via cron with the service key — require it (reject anon). Idempotent, per-user try/catch, update `last_synced_at`/`last_error`.
If the un-mirror-vs-delete distinction truly cannot be decided without a column, STOP and report NEEDS_CONTEXT proposing the minimal column — do not guess.
Deploy; verify with a curl invoking a single-user sync against Drew's connection once Task 5 has connected it (coordinate with controller — initial deploy may verify with a dry-run mode flag `?dryRun=1` that logs actions without writing; include one). Commit: `feat(fn): google-sync — incremental two-way runner, newest-wins, per-user isolation`

### Task 4: Cron scheduling migration

**Files:** Create `supabase/migrations/<next>_google_sync_cron.sql`.

pg_cron + pg_net: schedule `google-sync` invocation every 5 minutes (POST to the function URL with the service key from Vault/`app.settings` — follow the pattern designed in `docs/notes-gmail-monetization-decision.md:86-123`, brief §3/4). Include the unschedule statement in a comment. Apply + verify `select * from cron.job`. Commit: `feat(db): pg_cron schedule for google-sync every 5m`

### Task 5: Mac — server-sync gate + connect handoff

**Files:** Modify Mac Settings (Calendars section), `AppState` gate sites, `GoogleAuthService` (token handoff) — ALL exact call sites are in brief §1/§4 (polling timer, `shouldWriteBack`, backfill, reap, `externalEvents` merge).

- Settings → Calendars gains "Sync in the cloud" toggle (visible only when Google is connected locally): ON → POST the Keychain refresh token to `google-connect`, on 2xx set local flag + flip mode; OFF → DELETE to `google-connect`, resume local mode.
- Mode flag: read `google_connections.status` at bootstrap (one select via AtlasDB; treat 'active' as server-owned). When server-owned: skip Google polling startup, short-circuit ALL write-back/backfill/reap paths, stop merging Google `externalEvents` (Google rows now arrive via `loadAll()` — `EventRow.toDomain()` already derives source). Show "Last synced Xm ago" from `last_synced_at` + calm error + Reconnect when status='error'/'revoked'.
- When local (default/disconnected): behavior byte-identical to today.
Build Mac + iOS + `swift test`. Commit: `feat(mac): cloud-sync mode — token handoff, single-owner gate, synced-from-DB google events`

### Task 6: Mobile Settings copy (tiny)

**Files:** Modify `AtlasMobile/Views/Settings/SettingsView.swift`.

When a `google_connections` row is active for the user (add a minimal `AtlasDB` select — additive AtlasCore change, keep Mac green), the row reads "Synced automatically"; else current derived copy. Build iOS + Mac + swift test. Commit: `feat(mobile): settings shows cloud-sync status`

### Task 7: Integration verification + final review + push (controller)

End-to-end on Drew's real account per spec §Verification (Google→phone with Mac closed ≤5m; Atlas→Google exactly-once; Google-side mirror delete un-mirrors; newest-wins both ways) — Drew participates (his Google account + device). Whole-project Opus review (diff from plan base). Fix wave. Push.
