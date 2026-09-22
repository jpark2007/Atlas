# Handoff — first user reports, owner inbox, Mac 0.14.2 (2026-09-22)

Atlas has its first organic users. All three open bug reports so far came from one Apple-relay signup (Toronto Metropolitan, joined 09-11 on Mac 0.14.1 + iOS 1.2): overdue assignments showing urgent, can't delete a space, and Apple Calendar events not showing their calendar's colour. They waited ~11 days for a reply — there was no dashboard to see the reports land. That gap is closed below, and the three bugs are fixed on `release/mac-0.14.2`, pending Drew's remaining visual checks and a release.

---

## 1. Owner dashboard — deployed, live

`landing/admin.html` + the `admin-stats` edge function + migration `0052` (`fixed_at`/`replied_at` on `bug_reports`). Commits `4a3ec78`, `3c43d67`.

Four tabs:
- **Inbox** — open reports, oldest first, each labeled "waiting Nd", turns red after 24h with no reply.
- **Resolved** — resolved/fixed/replied timestamps.
- **Users** — per-user roster: platforms + versions, last seen, report count, scan count, Canvas/Google connection status.
- **Overview** — the existing charts plus version spread and week-one retention.

Every report shows the reporter's email via a server-side account lookup. A Fixed toggle marks `fixed_at`; replying stamps `replied_at` — that's what drives the Inbox "waiting" clock.

Also fixed in the same pass: `admin-stats`'s rate limiter was counting every dashboard-code attempt, including correct ones, toward the limit. `refundRateLimit` in `_shared/rate_limit.ts` now refunds a valid-code hit, so only wrong codes count.

### Gotcha: this repo has no `supabase/config.toml`
`supabase functions deploy admin-stats` with no flag **re-enables gateway JWT** and every call 401s (`UNAUTHORIZED_NO_AUTH_HEADER`). `admin-stats` and `waitlist` need `--no-verify-jwt`; `syllabus-scan` keeps gateway JWT (deploy it with no flag). Before/after any deploy of these functions, probe with an unauthenticated `curl` to confirm the mode didn't flip.

---

## 2. Overdue-assignments root cause — deployed, live

Strong hypothesis, not provable after the fact: with no term window given to the model, the `syllabus-scan` prompt never stated today's date, so a yearless syllabus date ("Sept 21") got a model-guessed year that was often in the past — everything on the syllabus then read as overdue.

Fix: `scanDateContext` (`_shared/syllabus_scan.ts`) now always states the local "today" in the prompt and resolves yearless dates into a fixed one-year window starting 90 days before today. Deployed — affects all clients immediately, no client update needed.

Ruled out during triage: the UI reading a non-due date field, and an all-day/timezone decode bug.

Side finding, not the cause of this bug, left alone: scanned date-only items commit `all_day=false` at 23:59 local (`capture_normalize.ts:150`), while `SyllabusDraft.swift:75`'s `commitsAllDay` check assumes 00:00. Inconsistent but harmless to the overdue calculation.

---

## 3. Mac 0.14.2 — branch `release/mac-0.14.2`, not yet released

Drew has visually passed space delete, calendar colours, and the bug-report attachment. Not yet released.

- **Delete Space** in the sidebar context menu. Blocked if the space has projects, classes, tasks, events, or notes, is shared, or is the last remaining space; default-space settings self-heal if they pointed at the deleted one. Duplicate space names are refused case-insensitively.
- **Apple Calendar colour**: events now render in their source Apple calendar's colour, with a per-calendar override in Settings (Mac and iOS). Stored per-device in `UserDefaults` under `calendar.apple.calendarColors` — EventKit calendar ids differ per device, so this can't sync as-is; the UI notes that. iOS now also honours `apple_calendar_default_space`. The iOS side of the colour picker ships with the next iOS build, not with 0.14.2.
- **Bug reports now always carry a log.** `AtlasLog.reportAttachment` adds a timezone/locale/OS context line; previously an empty in-memory log sent `null` and the dashboard had nothing to show.
- **One shared colour picker** (`AtlasTheme.Colors.palette`) now backs spaces, projects, classes, Apple calendar overrides, and both the New Space and Add Class sheets. Colours store as hex so older installed clients still render the new colours correctly.
- `scripts/release-dmg.sh` now deletes `dist/export` after building the DMG — a stray `Atlas.app` was showing up in Spotlight search.

### Still needs Drew's check before shipping
- Overdue-scan fix: paste a yearless syllabus into a class with no term window and confirm every resolved date lands in 2026, not 2025.
- The duplicate-space-name rejection message reads correctly.

Once both pass: bump `MARKETING_VERSION` in `project.yml` to 0.14.2 and run `scripts/release-dmg.sh` from `release/mac-0.14.2`.

---

## 4. Open / next

- **Reply to the Toronto Metropolitan user** after 0.14.2 ships. Their fix for the duplicate "School" space: turn School mode off to reveal their empty duplicate, then delete it — `AppState+School.swift`'s `visibleSpaces`/`isEmptyLegacySchoolSpace` hides any empty space literally named "School", which was meant for the legacy seeded one but also hides a user-created one of the same name. Worth narrowing that check to only the legacy seeded space rather than any empty "School".
- **Drew's own bug, not yet triaged**: checking off a task from the overdue popup doesn't remove it from the popup, and the dashboard's check-off animation sometimes glitches. Plan is to trace every check-off code path and route them all through one shared function rather than patching each site.
- **Calendar colours on iOS**: code is done, just waiting on the next iOS release to ship.

---

## 5. Where things live

| What | Where |
|---|---|
| Owner dashboard UI | `landing/admin.html` |
| Dashboard data + rate-limit refund | `supabase/functions/admin-stats/`, `supabase/functions/_shared/rate_limit.ts` |
| Inbox/Resolved timestamps | migration `0052_bug_reports_fixed_replied.sql` (or equivalent, check `supabase/migrations/`) |
| Overdue-date fix | `supabase/functions/_shared/syllabus_scan.ts` (`scanDateContext`) |
| Space delete + guard rails | `Atlas/Data/AppState.swift`, sidebar context menu |
| School-mode visibility bug | `Atlas/Data/AppState+School.swift` (`visibleSpaces`, `isEmptyLegacySchoolSpace`) |
| Apple calendar colour override | Settings (Mac + iOS), `UserDefaults` key `calendar.apple.calendarColors` |
| Bug report log attachment | `AtlasLog.reportAttachment` |
| Shared colour palette | `AtlasTheme.Colors.palette` |
| Release script fix | `scripts/release-dmg.sh` |

---

## 6. Gotcha worth knowing

Deploying `admin-stats` or `waitlist` without `--no-verify-jwt` silently flips the function back behind Supabase's gateway JWT and breaks the dashboard for everyone until redeployed correctly — there's no config file in this repo to pin that setting, so it has to be passed on every deploy of those two functions specifically. `syllabus-scan` is the opposite case and must NOT get that flag.
