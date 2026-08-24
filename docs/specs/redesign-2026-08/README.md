# 2026-08 Redesign — Master Index

Source vision: `docs/product-direction-2026-08.md`. All phases discussed and agreed with Drew on 2026-08-24. **Mac-first; iOS interpretation tracked in `mobile-interpretation.md`.**

| Doc | Scope | Size |
|---|---|---|
| `phase-1-school-framework.md` | Term + Key Dates, Classes as framework, schedule ingestion (ICS/Google-Apple/screenshot/manual), syllabus AI scan + Class info card | Large |
| `phase-2-time-model-calendar-language.md` | Events / deadlines / tasks / work sessions; due markers + day caps; deadline↔work-session link; Late bar; completion mechanics | Large |
| `phase-3-sync-rules-dedup.md` | Outbound defaults (events ON, work "Work:" ON, deadlines OFF), cross-calendar dedup, Apple Cal from iPhone, SIWA revocation + local cleanup on delete | Medium |
| `phase-4-brain-dump.md` | Draft persistence (Mac+iOS), context-aware parsing, commit + chip corrections | Medium |
| `phase-5-simplicity-ia.md` | Sidebar (School promoted), settings 5-heading reorg, language purge, Mac first-run, friction log | Medium |
| `mobile-interpretation.md` | Running iOS notes per phase | Running |

## Suggested implementation order

1. **Pre-App-Store hygiene** (independent, do first): SIWA token revocation in delete-account + local-leftover cleanup (Phase 3 tail).
2. **Phase 4 draft persistence** — small, highest trust-impact.
3. **Phase 3 dedup + sync toggles + "Work:" prefix** — pure-function heavy, testable.
4. **Phase 5 language/settings pass** — wide but shallow.
5. **Phase 2 calendar language** — rendering work on existing objects.
6. **Phase 1 School framework** — biggest; schema + ingestion + scan.
7. **Phase 4 smarter parsing + chips flow**, then **mobile interpretation wave**.

Google verification video is independent of all of the above (no OAuth/scope/UI-in-consent changes) — record and submit in parallel.

## Orchestration rules (for the implementing session)

- The lead model (Fable) **orchestrates and reviews only — it writes no implementation code.** All coding goes through subagents: **Opus** for design-sensitive/architectural work, **Sonnet** acceptable for mechanical/wide-but-shallow work (label renames, plumbing). Never run a subagent on Fable.
- Work phase-by-phase in the order above; one feature branch per phase; build gate before claiming anything done: `xcodebuild -project Atlas.xcodeproj -scheme Atlas -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`. UI changes additionally need Drew's visual check — say "applied, builds, needs your check", never "works".
- Visual target: the approved "Atlas Redesign Preview" design canvas (Drew has the link; artboards: Dashboard, Calendar Day/Week, Class hub, Settings). Match the editorial theme tokens in `AtlasCore/Sources/AtlasCore/Theme.swift` exactly.
- Server changes (seed trigger replacement, SIWA revocation, feeds dedup) ride Supabase migrations + edge functions per existing patterns; never disable legacy CRON keys.
- CLAUDE.md rules apply throughout (surgical changes, data-source attribution correctness, simplicity first).
