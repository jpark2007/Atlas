# Handoff — 2026-07-16 evening · Drew's Mac test-pass feedback

**For the next Claude session.** Drew rebuilt and tested the Mac app after today's waves
and left the feedback below. Read this whole doc, then respond to him point by point and
dispatch the agent plan at the bottom. Standing rules (from memory, non-negotiable):
ALL subagents on **Opus** (Sonnet where overkill) — NEVER Fable; the main loop never
writes implementation code — it orchestrates, reviews, deploys, verifies, commits;
build check = `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug
-destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` (mobile scheme:
`AtlasMobile`, generic/platform=iOS Simulator); UI is never "done" until Drew visually
confirms; migrations/deploys are applied by the orchestrator via `supabase db push
--linked < /dev/null` and `supabase functions deploy <fn> --project-ref
jxrmozhgsebwtbdleyxp`; push to git when a wave completes.

## Where things stand

- Tip of main: `4a46615` (everything pushed, tree clean). Prod: migrations 0027–0031
  applied; google-connect/google-sync/drive-writeback/drive-import/reference-pull/
  delete-account all deployed today. Mac + iOS builds green; AtlasCore tests pass.
- Drew's account = **drewkhalil@icloud.com** (7487ebba…); the old gmail account was
  deleted intentionally. Jonah = jonahpark7@gmail.com.
- Sharing/social work is PARKED per Drew (0030 root fix is live; don't resurrect).
- Drew is testing iOS himself; Apple-Calendar-in-menu-bar he already **approved**.

## What changed since Drew's previous build (context for his feedback)

Mac: (1) dupe fixed twice over — legacy local Google overlay removed + first-sync
adoption in the runner; (2) account-switch data clear (flicker fix — see feedback #1,
it didn't take); (3) editorial STARTS/ENDS date fields; (4) settings regrouped, GOOGLE
cluster, Notes & Docs sign-in row, honest aggregate badge, "Gmail" delabeled;
(5) sign-out/delete now wipe Google keychain; (6) class colors option B — "GRID COLOR"
swatch row on project pages, day/week tiles wear project color, dots stay space color;
(7) inline space rename (click name) + recolor (dot popover) on the space page;
(8) menu-bar + dashboard rail = master feed incl. Apple externals; (9) serif animated
Google-connect return page. Mobile: sectioned settings, read-only Google-connections
+ Notes & Docs rows, Canvas manage kept (verified genuine), day-grid class colors.
Backend: delete-account fixed (tombstone FK + purge ordering), dedicated
google_docs_connections, drive-writeback multi-account fix, membership owner-row
triggers + backfill (0030), projects.color_token (0031).

## Drew's feedback (2026-07-16 ~5pm, verbatim-adjacent) → issues

1. **"I still see the flicker from old account — or do I have to log out once?"**
   The account-switch clear shipped today apparently did NOT fix his case. The fix
   clears state on a switch detected during bootstrap; agent claimed there's no on-disk
   cache, but Drew still sees stale data at login. Needs real root-cause (superpowers:
   systematic-debugging): is there a persisted store after all (offline capture rows?
   UserDefaults snapshot? MockData flash?), or does the in-memory StateObject survive
   relaunch-less sign-in flows the detector misses? Answer his question too: he should
   not have to log out once; if the stale copy predates today's build it may show one
   last time, but if it recurs after that it's a live bug — treat as live bug until
   proven otherwise.
2. **"Grid color sucks — should be a popup, not a fully-open selector; not clean;
   should say PROJECT COLOR."** Rework the project-page color UI: compact trigger
   (small color dot / swatch chip next to the title, mirroring the space page's dot →
   popover pattern) opening a popover with the swatches; label **PROJECT COLOR**.
3. **"Canvas item turned grey. Canvas should be the school/space color unless it's
   associated with a class."** (Screenshot: the CLASS chip and a canvas event
   rendering grey.) Two parts:
   a. Root-cause the grey: where do Canvas-origin items get their color now, and did
      the gridColored/project-color layer or the CLASS badge styling turn them grey?
      Rule 5 (CLAUDE.md): source attribution must be honest; canvas items must wear
      their destination space's color unless a class mapping applies.
   b. **Canvas class ↔ project mapping** — Drew says this was the agreed design
      ("a way to make classes import match w the items coming in") and expects it
      implemented: a project (class) can be linked to a Canvas course (canvas course
      id or similar) in the project's detail page; canvas items from that course then
      belong to that project (and wear its project color). Check what canvas-sync
      stores per item (course id?) and what exists already; implement the mapping
      end to end (schema likely needed, e.g. projects.canvas_course_id + ingest
      routing + a picker in project detail listing the feed's courses).
4. **"Grid-colored dots should be on the side like here"** (sidebar screenshot):
   the sidebar's project rows should show the project's color as its dot (today it's
   a hollow neutral circle; spaces already show their color dot).
5. **"How to edit title — I can't. In the detail page clicking the title should make
   it editable."** Project detail page: click-to-edit title (same in-place pattern as
   the space page rename that shipped today).
6. **"Recoloring doesn't do shit"** — the space color popover persists a token but
   nothing visibly changes. LIKELY root cause to verify first: views may resolve
   space color by NAME through a static theme mapping (AtlasTheme space palette)
   rather than reading spaces.color_token, so writing the token changes nothing
   visible. If so this affects everything (chips, dots, blocks) and the fix is to
   thread the stored token through the color resolution — one consistent path.
7. **"Each project should have an Add Task button that's already tagged with that
   project and space."** Add to project detail page (there's a global add; this one
   pre-fills project + space).
8. **Logo**: "run a sub agent to fix logo… put it in the SVG for website or whatever."
   Get the actual Atlas logo properly into the landing site (currently an inline SVG
   brand mark) and export a 120×120 PNG for the Google consent screen while at it.
9. **DMG wave (gated on Drew approving the fixes above):** make the DMG, add a beta
   download button to the landing site, deploy the site with the privacy policy linked
   (landing/privacy.* was updated today for verification — Limited Use, Docs scope,
   drive.file), and test the download. Free hosting is fine for now — a real owned
   domain is ONLY needed when submitting Google OAuth verification (checklist:
   docs/specs/2026-07-16-google-oauth-verification.md; Drew still owes domain + logo
   PNG for that, logo handled by #8).

## Suggested agent plan (adjust as needed, all Opus unless noted)

- **Agent A — flicker root-cause + fix.** Systematic debugging first; no fix without
  reproducing the persistence path. Deliverable: where the stale data lives, the fix,
  and why it can't recur.
- **Agent B — project/space color system.** Items 2, 4, 5, 6, 7 together (they're all
  ProjectDetailView/SpaceDetailView/sidebar/color-resolution): PROJECT COLOR popover,
  sidebar project dots, click-to-edit project title, per-project Add Task, and the
  space-recolor no-op root cause (thread color_token through resolution). One agent —
  same files, avoids conflicts.
- **Agent C — Canvas color + class mapping.** Item 3 both parts (schema 0032 if
  needed, canvas-sync ingest routing, project-detail course picker, honest colors).
  Backend + Mac; disjoint from B except project detail — SEQUENCE B then C, or give C
  the project-detail course-picker section only and coordinate.
- **Agent D (Sonnet ok) — logo.** Item 8: site SVG + 120×120 PNG export.
- **DMG wave** after Drew approves A–C visually.

A and D can run parallel with B. C after B (shared ProjectDetailView).

## Also open (don't lose)

- Drew testing iOS changes himself — expect feedback.
- File-import-from-laptop design discussion (size caps, Supabase Storage bucket) —
  queued behind fixes; see memory atlas-mobile-todo.
- Space rename fan-out is non-transactional (flagged 2026-07-16); durable fix =
  space_id-based references. Only if Drew asks.
- google_two_way_sync prod column drop — some later migration.
- Jonah needs Config/Secrets.xcconfig sent directly for his OAuth to work.
