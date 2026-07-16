# Multi-account Google Calendar — design

**Date:** 2026-07-15 · **Approved by:** Drew (chat) · **Scope:** Mac full manage; iOS display-only (no mobile work in v1) · **Testing:** Drew handles device/E2E pass.

## Summary

Atlas can connect **N Google accounts** (separate logins). Each connection gets a
**user-typed name** ("School") and a **destination space** picked from a dropdown.
All connections read IN — Atlas is the one place you see everything. Writes route
OUT by space: an event syncs to whichever Google account its space is linked to;
**no link → stays in Atlas** (no default fallback — the existing default-space
setting already covers "unassigned → Personal" behavior upstream). Calendar scopes
only; Gmail sync is permanently out of scope (no restricted scopes / CASA).

The one-sentence law: **"An event syncs to the Google account its space is linked
to; an unlinked space stays in Atlas."**

## Decisions made (do not relitigate)

1. Unit = **connection**: (google login, calendar_id `'primary'` for v1, name, space).
   Separate accounts, not multiple calendars of one account — but the schema doesn't
   preclude per-calendar rows later.
2. **One space, one account** — unique on `space_id`. Two accounts feeding one space
   is forbidden in v1.
3. Incoming events land in the connection's linked space, stamped with the
   connection id. Source attribution set at ingest, per connection (CLAUDE.md rule 5).
4. Moving an event between spaces = moving it between Google accounts
   (tombstone-delete from old, create in new — existing machinery, routed).
5. Per-connection status/error/reconnect. One connection can be in `error` while
   others sync on.
6. UI layout A: inline rows in Settings → CALENDARS (name, email muted, status line,
   destination-space dropdown on the row — sibling of the Canvas row); row click →
   small detail sheet (rename, Reconnect, Disconnect, error detail). "Add Google
   account…" button under the list.
7. **One Reconnect** in the detail sheet does BOTH the local OAuth credential AND the
   server vault re-push (`enableServerSync`) — collapses today's two-Reconnect trap.
8. No migration story needed: `google_connections` is empty in prod (2026-07-15).

## Schema (migration 0028)

`google_connections` is currently PK `user_id` (singleton). The table is empty in
prod — **drop and recreate**:

```sql
google_connections (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users on delete cascade,
  name           text not null,                 -- user's label, e.g. "School"
  google_email   text not null,                 -- which login (display + dedupe)
  calendar_id    text not null default 'primary',
  space_id       uuid references spaces on delete set null,  -- routing link; null = read-in only
  vault_secret_id uuid,
  sync_token     text,
  status         text not null default 'active',  -- active | error | revoked
  last_error     text,
  last_synced_at timestamptz,
  claimed_until  timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (user_id, google_email, calendar_id),
  unique (space_id)                              -- one space, one account
)
```

RLS mirrors the current table (owner read; service-role full — check 0006–0009 for
the exact existing policy shapes and keep them).

Related changes, same migration:

- `events` + `google_connection_id uuid references google_connections(id) on delete set null`.
  Runner ignores rows whose gid is set but connection id is null (legacy/detached).
- Single-owner invariant: replace `unique (user_id, google_event_id)` with
  `unique (google_connection_id, google_event_id)` (partial-index caveats: the
  runner's ON CONFLICT must still be inferable — mirror how 0009/C1 did it).
- `deleted_google_events`: add `google_connection_id` (fk, cascade); tombstone PK
  becomes (google_connection_id, google_event_id); keep user_id for the auth.users
  cascade. The 0011/0027 trigger copies `old.google_connection_id`; **skip the
  tombstone when it is null** (nothing to replay). Keep 0027's FK-violation swallow.
- `claim_google_sync_users` RPC (0009): claim due **connection rows**, not users.
  Rename to `claim_google_sync_connections`; same lease/skip-locked semantics,
  oldest `last_synced_at` first.

## Edge functions

- **google-connect**
  - POST `{refreshToken, name, spaceId?, googleEmail}` → insert a connection row +
    vault secret. Reject duplicate (user, email, calendar) with 409. Re-POST for an
    existing row (same user+email+calendar) = reconnect: replace vault secret, reset
    status to active, clear last_error.
  - PATCH `{connectionId, name?, spaceId?}` → rename / re-map (mirror canvas-connect's
    destination PATCH shape). Enforce unique space_id → 409 with a clear message.
  - DELETE `{connectionId}` → remove row + its vault secret. Other connections
    untouched.
- **google-sync**: outer loop per **connection** (claim RPC above). Per-connection
  sync_token, tombstone replay (filtered by connection id), pull (stamp
  `google_connection_id`, land in `space_id`'s space — resolve space name/color at
  ingest), push (only events whose space is this connection's space). Status/error
  writes go to the row. Internals (deterministic ids, google_origin, two-timestamp
  reconcile) unchanged.
- **delete-account**: `google_connections` is no longer `maybeSingle()` — collect ALL
  vault_secret_ids (google plural + canvas), delete user, then purge each
  (post-delete order per 2026-07-15 fix — keep it).

## Mac app

- **GoogleKeychain**: key credentials by connection id (`atlas.google.<connectionId>`),
  not a single slot. This also fixes the 2026-07-15 cross-account-leak gremlin (a
  machine-global credential surviving Atlas account switches). Sign-out clears all.
- **GoogleAuthService**: `connect()` forces Google's account chooser
  (`prompt=select_account consent`) so a second login is pickable. After OAuth,
  return tokens + the granted account email (`id_token`/userinfo) to the caller —
  the caller creates the connection via google-connect POST.
- **AppState**: `googleConnection` (singleton) → `googleConnections: [GoogleConnection]`
  (id, name, email, spaceId, status, lastError, lastSyncedAt). Refresh reads all rows.
  Event write-path: creating/editing/moving an event resolves its space → connection
  and stamps `google_connection_id` locally (server push routes by it).
- **SettingsView → CALENDARS** (layout A):
  - One row per connection: name / muted email / status line ("Connected — last
    synced 2m ago" · "⚠ Reconnect needed") / destination-space dropdown inline
    (visual sibling of the Canvas row's picker).
  - Row click → detail sheet: rename field, Reconnect (local OAuth + enableServerSync
    in one action), Disconnect (danger), status/error detail.
  - "Add Google account…" under the list: OAuth (account chooser) → small sheet:
    name it + pick space → save = google-connect POST → row starts syncing.
  - The old singleton "Sync in the cloud" row and its separate Reconnect disappear;
    cloud sync is now implicit per connection. Apple Calendar row untouched.
- **Space move** of an event: clears gid + tombstones under the old connection,
  restamps the new connection (or none). Follow the existing delete/create mirror
  machinery — do not invent a Google "move" call.

## Error handling

- Connection in `error`/`revoked`: its row shows the warning + Reconnect; other
  connections unaffected (already per-row in the runner claim).
- google-connect PATCH to an occupied space → 409; Settings shows "That space is
  already linked to <name>."
- Deleting a space that a connection points at → `space_id` set null (schema);
  UI shows the row as "read-in only — pick a space".

## Out of scope (v1)

- Multiple calendars per login (schema-ready, no UI).
- iOS manage UI (display works automatically via the normal store).
- Any Gmail scope, ever. Default-fallback write account (add later only if wanted).
