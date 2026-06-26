# 08 — Email Capture (AI)

Turn relevant emails into tasks automatically.

## Idea

Connect an email account. Atlas periodically scans **relevant** new emails, and when one implies an action (e.g. *"please revise your essay by Friday"*), the AI drafts a **task** with a due date, **tagged "from email"** for the user to confirm.

## Flow

```
Scheduled Edge Function
  → pull NEW emails (filtered by label/subject)        ← not the whole inbox
  → batch several into one GPT-4o-mini call
  → model returns candidate tasks (title, due, source) 
  → surface to user as suggestions, tagged "from email"
  → user confirms → task created
```

## Why no n8n needed

A **scheduled Supabase function** does the same job as an n8n workflow (pull → filter → batch → AI → store), and keeps everything in one backend. n8n would only be a convenience wrapper. Not required.

## Filtering & batching (cost control)

- **Filter** by Gmail label/subject so we only process likely-actionable mail, not everything.
- **Batch** multiple emails per AI call to cut cost (GPT-4o-mini is cheap, batching makes it negligible).

## Auth

- Gmail OAuth, tokens held server-side (per [01](./01-architecture.md)).

## Status

**Later phase.** OAuth + parsing is moderate work; valuable but not foundational. Human-in-the-loop confirm is mandatory (never auto-create from email silently).

## Open questions

- Which emails count as "relevant" (user-defined labels vs. AI relevance scoring).
- Frequency of scans vs. cost.
- Privacy posture for reading email content through AI.
