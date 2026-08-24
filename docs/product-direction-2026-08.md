# Atlas — Product Direction & Development Report (2026-08-24)

> Source: external feedback conversation Drew had, based on his mental model of Atlas. Some points may already be handled in the codebase — this doc is the reference as we review each one.
>
> **Drew's flags:** §11 (interaction quality) is a main feeling and must be handled. Additional hard requirement not in the original report: **cross-calendar deduplication** — if two imported events (e.g. one from Google, one from Apple/Canvas) have the same/similar title and overlapping or identical time, Atlas should recognize them as one event rather than creating duplicates.

## 1. Executive Summary

Atlas has already grown beyond a simple school planner. It currently includes:

- Mac app, iOS app, cross-device syncing
- Google Calendar integration, Apple Calendar integration
- Canvas assignment importing through ICS
- Google Drive/notes integration
- Tasks, Projects, Calendars
- Brain Dump as the main input, with a global Mac shortcut to open it while Atlas runs in the background
- AI-powered interpretation/routing of Brain Dump input
- Calendar-based planning and work-session scheduling
- Collaboration and social functionality

The main problem is not a lack of functionality. The bigger problem is that Atlas has accumulated enough technical complexity that the product can start to feel like the developers' conception of the system rather than a simple product for the student using it.

The next phase should focus on:

1. Making School genuinely school-native.
2. Introducing Classes as a real concept rather than treating classes as specially named Projects.
3. Clarifying the difference between Tasks, Deadlines, Events, and Work Sessions.
4. Making the calendar understandable despite those different object types.
5. Keeping Brain Dump extremely easy while making its AI results fast to correct.
6. Prioritizing interaction quality and reliability.
7. Simplifying the visible experience without necessarily simplifying the underlying technology.
8. Using Atlas heavily ourselves before expanding the product.

The goal is not to add more features. The goal is to make the existing system feel obvious.

## 2. The Core Problem: Atlas Has Become Too Technical

Atlas was developed by two technically minded founders, with Claude assisting heavily. That creates a specific risk: **the architecture becomes visible in the product.** Distinctions, states, settings, objects, workflows, and edge cases that make sense to the builders may mean nothing to a normal student.

A user should not need to understand how Atlas internally categorizes something, why one object technically differs from another, what sync architecture is used, why a thing belongs in a section, internal states, how the AI decided something, or how the calendar system works internally.

The product should simply communicate: *Here are your classes. Here is what you need to do. Here is when things are due. Here is your schedule. Here is when you can actually get the work done.*

**Key principle: complexity can exist underneath the product. It does not need to exist in the user's mental model.**

## 3. School Should Become Its Own Product Mode

Current structure: `Space → Projects → Tasks`, where a class is effectively a Project named "Calculus." Technically possible, but it makes School feel like a generic productivity system with school-related names.

Proposed: `School → Classes → school-specific objects` — each class (Calculus, Biology, …) contains Assignments, Tasks, Deadlines, Notes, Resources, Exams, and Calendar information. Classes become first-class objects.

This does not necessarily mean rebuilding the database. The important change is the user-facing mental model: a student should think *"this belongs to Calculus,"* not *"I need to put this inside the Calculus project."*

## 4. The Four Time Concepts

The calendar currently mixes several types of information. They should be clearly distinguished:

- **Events** — something that happens at a particular time (Biology lecture Tue 10 AM, doctor Wed 4 PM). Inherently calendar-oriented.
- **Deadlines** — something that must be completed *by* a time (essay due Friday 11:59 PM). Not a block of time; a constraint.
- **Tasks** — things that need to get done, even without a deadline (email professor, buy notebook). Useful without a date.
- **Work Sessions** — actual time intentionally allocated to a task (work on essay Wed 3:00–4:30 PM). The bridge between a task and the calendar.

## 5. Tasks Should Not Require Deadlines

Not every task needs a deadline. Atlas should distinguish three states: task **exists** → task **has a deadline** → task **has been scheduled for work**. A task can exist for weeks with no deadline, later receive one, then receive one or more work sessions.

## 6. The Calendar Should Become the Planning Layer

Atlas should not merely display calendars. It should help answer: *"Given everything I have going on, when should I actually do my work?"* — e.g. take the English essay (due Friday) and place a work session in Wednesday's 3–4 PM opening. The calendar becomes: things happening + things that need completing + time allocated to complete them. The visual design must make those distinctions immediately understandable.

## 7. Calendar Synchronization

Philosophy: **pull external calendar events in** (to understand availability); **push only appropriate Atlas information out.**

Suggested defaults:
- Atlas Events → synced outward by default.
- Tasks and deadlines → Atlas-native by default (no Google Calendar event for "finish biology lab" or its Friday due date).
- Work sessions → potentially sensible to sync (real reserved time) — user's choice.
- User ultimately controls what Atlas sends to their external calendar.

Atlas should not clutter someone's primary calendar, and Atlas itself stays the authoritative place for tasks and deadlines.

**Addendum (Drew): cross-calendar deduplication.** When the same real-world event arrives from multiple sources (same/similar title + identical or overlapping time), Atlas must recognize it as one event, not render duplicates.

## 8. Brain Dump Is the Universal Input

Brain Dump is already positioned correctly: it is the main input box, with a global Mac shortcut and Mac↔iOS sync. It should stay extremely simple: the user says *"I need to finish the science project, my English test is Friday at 8 AM, and I should study for calculus tomorrow"* and Atlas interprets it into the right objects. The user should never have to manually determine which item is an event/task/deadline or which class it belongs to.

## 9. AI Does Not Need to Be Perfect

Target: AI gets most of it right → user corrects mistakes instantly. Tap a result → small contextual popover (Class ▾ / Type ▾ / Due ▾) → change, close. No editing screen, no tutorial, no settings digging. Better than chasing 100% classification accuracy.

## 10. Brain Dump Must Be Reliable

The bug where closing the mobile app loses an in-progress Brain Dump is a priority. Brain Dump is an input mechanism — losing typed text damages credibility more than any cosmetic bug. Expectation: **if I typed it, Atlas saved it** — on Mac and iOS.

## 11. Interaction Quality Is a Core Product Feature  ⭐ (Drew's main feeling)

Atlas sometimes doesn't feel satisfying to use. This is not minor polish — for a productivity app, interaction quality determines habit. If another app does something in two taps and Atlas needs six, the user uses the other app, regardless of capabilities.

Priorities: fewer unnecessary clicks, clear feedback after actions, fast transitions, obvious buttons, simple editing, good keyboard interactions, natural drag-and-drop, clear calendar states, fast Brain Dump access, reliable saving, minimal modal complexity, strong mobile interactions.

Constant test: *"Could a student figure this out without being taught?"*

## 12. Atlas Should Not Require a One-Hour Tutorial

If a new user needs the architecture explained, the interface is exposing implementation. The fix is not a better tutorial — it's removing the need for one. The product teaches itself through context: add classes → see classes → tap Calculus → see assignments/notes → see the Friday deadline → *"want to plan when you'll work on it?"* → user learns work sessions naturally.

## 13. Design Around the Student's Questions

- "What do I have?" → Classes / assignments / tasks
- "What's happening?" → Calendar / events
- "What's due?" → Deadlines
- "What should I do?" → Tasks + planning
- "When should I do it?" → Work sessions
- "What did I just remember?" → Brain Dump
- "Where's my stuff for this class?" → Class hub / notes / resources

## 14. Leverage Existing Integrations

Prefer plugging into existing standards and infrastructure over rebuilding (Canvas-through-ICS is the model). Applies to calendar sync, auth/OAuth, educational systems, file/document systems, automation infrastructure. Spend development time on what makes Atlas Atlas.

## 15. Google Verification

Still outstanding (video re-record). Address it, but don't let waiting on verification become an excuse to continuously expand the product.

## 16. Dogfooding Drives the Next Phase

Both founders use Atlas through school. Every time you reach for another app, ask why:
- Opened Apple Calendar → Atlas didn't make the schedule obvious (UX problem)
- Used Reminders → task had no deadline (task-model problem)
- Used Notes → class notes were easier to find there (notes/resource problem)
- Forgot Atlas existed → habit/discoverability problem

These observations beat hypothetical feature brainstorming.

## 17. Recommended Development Priorities

1. **School architecture** — Classes as real school objects; define how assignments/tasks/deadlines/notes/resources/events relate to a class.
2. **Simplify the mental model** — understandable without being taught the architecture.
3. **Calendar model** — clearly distinguish events / deadlines / tasks / work sessions and define each one's calendar behavior.
4. **External calendar sync** — events out by default; user chooses deadlines/work sessions; Atlas is primary source for tasks and deadlines. (+ cross-calendar dedup, per addendum in §7.)
5. **Brain Dump** — classification accuracy, context awareness, instant editing, persistence, reliability.
6. **Interaction quality** — systematically find anything slower/clunkier/less satisfying than the alternative.
7. **Google verification** — finish it.

## 18. The Product Vision

Not "an all-in-one productivity app for students." Better: **Atlas understands your school life and helps you turn it into a plan.** Classes, assignments, deadlines, calendar, notes, available time, and random thoughts all connect. The user tells Atlas what's going on; Atlas organizes it, then helps decide when to actually do the work.

## 19. Final Principle

The next version of Atlas should not have more functionality — it should have **less visible complexity**. Sophisticated AI/sync/collab/integrations can live underneath, but the student's experience should be: *My Classes. My Tasks. What's Due. What's Happening. When I'm Going to Work. Brain Dump.*

The objective is not the biggest possible Atlas — it's making the Atlas already built something Drew and Jonah genuinely want to open every day.
