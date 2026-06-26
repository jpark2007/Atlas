# 04 — The Brain (AI)

**Engine:** OpenRouter API, model **GPT-4o-mini**. Always called via a Supabase Edge Function (key hidden). Model is swappable later without app changes.

## Capabilities

### 1. Natural-language capture
- User types/dumps plain English: *"essay due Thursday, gym 3x this week, dinner with mom Sunday."*
- AI returns **structured items**: events vs. tasks, titles, due dates, durations.
- User reviews/confirms before they're committed (no silent writes).

### 2. Auto-bucketing
- For each captured item, AI assigns the right **Space** (School/Personal/Business) and, when obvious, the **Project/Class**.
- Learns from corrections over time (start simple: prompt includes the user's spaces/projects so the model can match).

### 3. Smart scheduling
- For unscheduled tasks, AI suggests **when** to do them, fitting around existing calendar free/busy.
- Surfaces suggestions the user drags/accepts onto the timeline; never force-books without confirmation.

### 4. Long-term goal suggestions
- User sets a goal ("get fit", "learn Spanish").
- Atlas periodically suggests sessions to slot in (e.g. "3 Spanish blocks this week"), respecting the calendar.

## How a request flows

```
App → Edge Function (adds OpenRouter key + context) → GPT-4o-mini → structured JSON → App (review UI) → confirm → DB
```

- **Context sent to the model:** the user's spaces/projects (names), relevant free/busy windows, and the raw text. Keep payloads lean for cost.
- **Structured output:** model returns JSON (items with type, fields, suggested space/project) the app validates before showing.

## Cost & batching

- GPT-4o-mini is cheap; batch where possible (e.g. email scan processes several messages per call — see [08](./08-email-capture.md)).
- Keep prompts tight; only send the context needed for the task.

## Principles

- **Human-in-the-loop:** AI proposes, user confirms. Especially for anything that writes to a real calendar.
- **Transparent tagging:** AI-created items are tagged with their source so the user knows what came from the Brain.

## Open questions

- How to represent "learning" from corrections (simple prompt context vs. stored preferences).
- Guardrails for ambiguous dates ("Thursday" — which one?).
