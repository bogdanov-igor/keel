---
name: discovery-signals
description: Gather grounding signals (competitors, user complaints, metrics, errors, trends) from memory, the web, and analytics before big work, so the stage brief rests on evidence instead of assumption.
---

# Discovery signals

Run before decomposing big work (anything getting a stage via skill
`stage`). A hypothesis with zero signals behind it is a guess: collect
a small evidence base first, and if none exists, say so instead of
inventing a plan.

## Signal kinds

| Kind | What it looks like | Typical source |
|---|---|---|
| Competitor | a rival ships or claims something relevant | web, memory |
| UserComplaint | a real user describes a pain | reviews, support threads, memory |
| MetricSignal | a number moved (conversion, churn, latency) | analytics, logs |
| ErrorSignal | recurring failure or exception | logs, error tracker, memory |
| Trend | market or tech shift that changes the calculus | web |

## Procedure

1. Memory first. Read the matching section of `memory/MEMORY.md`, then
   grep `memory/` by topic keywords (`grep -ril "<topic>" memory/`).
   Past lessons and antipatterns are the cheapest signals — a prior
   failed attempt at the same idea is itself a signal.
2. Targeted web search. Three angles usually suffice:
   - `<topic> problem user complaints`
   - `<topic> market trends <current year>`
   - `<topic> error failure reports`
   Cap at ~5 items per signal kind; beyond that is noise, not grounding.
3. Analytics and logs, when access exists. Product analytics, server
   logs, error trackers. One real metric from our own product outweighs
   several web anecdotes about someone else's.
4. Classify each item:
   - kind — one of the five above
   - source — `memory:<path>`, `web:<url>`, or `data:<query or log path>`
   - severity — high / medium / low
   - freshness — current / unknown / stale (discount stale heavily; a
     three-year-old complaint about a since-fixed product is not a signal)

## Output

- A `## Grounding` section in the stage brief
  (`stages/NNN-slug/brief.md`), one line per signal:
  `<kind> | <severity> | <freshness> | <one-line summary> | <source>`.
  3-7 signals is a healthy brief; 20 is a dump, trim to the strongest.
- New durable facts not already in memory → record via skill `remember`.
  Ephemeral observations stay in the brief only.
- Actionable problems surfaced beyond the current topic go to
  `BACKLOG.md`:
  `- [ ] P0..P3 | <surface> | <one line> | ev:<path-or-url> | src:discovery-signals`.

## Gate

At least one genuine signal before committing to the hypothesis. Zero
signals → stop and ask the owner for context; proceed ungrounded only
on the owner's explicit go-ahead, and write the grounding section as
"none found — proceeding on owner's direction" so the brief records it.

## Anti-patterns

- Fabricated signals. Every entry needs a real source (memory path,
  URL, or query/log location). No source, no signal.
- Sliding past the gate. Zero signals means stop and ask, not
  "probably fine".
- Duplicate memory notes. Grep `memory/` for an existing note before
  recording via skill `remember`.
- Scope creep. This is signal collection for one topic, not general
  web research — hand broad research off as its own task.
