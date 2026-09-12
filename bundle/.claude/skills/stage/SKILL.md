---
name: stage
description: Protocol for big work — multi-surface, risky, or multi-hour. Two files in stages/NNN-slug/ (brief with done criteria and a premortem before, verified report after). Small tasks skip this entirely; ceremony on small work is pure tax.
---

# Stage — big work protocol

Use when the work spans surfaces, carries risk (data, prod, money), or
will outlive one sitting. Otherwise don't — that's the two-tier rule.

The protocol has one point: what counts as done is agreed before the
work, not derived from the report after it — a report always confirms
the "done" that was read out of it.

## Files

`stages/NNN-slug/` (next free NNN, three digits):

**`brief.md`** — written before starting, one page, readable by an
agent that never saw this session (files, interfaces, what is out of
scope):

- Goal: one sentence, testable.
- For whom: who reads the result and what they will do with it.
- Done criteria: 3–7 checkable statements, each one that could fail.
  The `verifier` judges by these, not by the units' own reports.
- Grounding: relevant memory notes as `[[slug]]` links, or the words
  "no prior art" — an honest empty beats a decorated citation.
- Approach, plus 1-2 alternatives considered (one line each, with the
  reason they lost).
- Units: numbered list. Per unit: expected outcome (phrased as a check
  that can fail, not a wish) and rollback (a command or "revert commit").
- Premortem, three rounds. Round one: "it is the day this stage was
  due, and it has failed — name the causes that follow from this
  brief, each tied to a file or section of it, each with the signal
  that would show it in the first week". Round two: defend each cause
  against the obvious objection. Round three: the smallest edits to
  the brief that close the top three. A cause hangs on the brief's
  text, not on a generic list of project risks; a cause without an
  observable signal does not count.

**`report.md`** — written at close:

- Per unit: what shipped (commits, paths), evidence for the expected
  outcome, and the verifier verdict.
- Which premortem causes materialized, and by which signal.
- Aggregate: shipped / partial / abandoned — with the honest reason,
  and the caveats as a list. No narrative: the report is read to
  decide what is next, not to remember how it went.

Two files total. No plan.json, no sha256 sidecars, no locks, no run ids.

## Rules

- Show the owner `brief.md` before executing when scope is debatable.
  The contract's parking rule applies: silence doesn't rot a stage,
  it parks it.
- Parallel units run as subagents in their own worktrees (ask for
  "use worktrees for your agents"; the harness blocks edits to the
  main checkout). Commit the stage's work before fanning out — a
  worktree branches from the default branch and would not see it. One
  surface per unit, merge order stated in the brief; units that touch
  the same files are not parallel. This stack once had parallel
  migrations silently clobber each other's SQL function bodies.
- The report's verdict comes from the `verifier` agent with fresh
  context, judging the done criteria. The Verifier section is created
  as a placeholder ("run pending") and filled only by pasting the
  agent's summary line together with its agent id; a verdict written by
  hand is a fabrication, and the hook `verdict-guard` refuses it. A
  report without a verifier pass is `partial`, whatever the units claim.
  Two rounds at most: the second checks the first round's fails and
  regressions, then the stage closes with caveats.
- A stage longer than a sitting: `/loop 45m` with a one-line premortem
  prompt ("assume this work has failed; name three causes visible in
  the transcript and the brief; refute each cheaply; file what
  survives") keeps the session honest. It lives as long as the session.
- Stage closed → `/clear`; the next stage starts from its brief, not
  from the tail of this conversation. `/clear` also drops an active
  `/loop` (and `/goal`, where the CLI has it) — start them again if the
  next stage needs them.
- Units unfinished at close become `BACKLOG.md` items — never silent loss.
- The stage taught something → skill `remember` before closing.
