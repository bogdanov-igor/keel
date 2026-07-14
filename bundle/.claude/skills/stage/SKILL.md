---
name: stage
description: Protocol for big work — multi-surface, risky, or multi-hour. Two files in stages/NNN-slug/ (brief before, verified report after). Small tasks skip this entirely; ceremony on small work is pure tax.
---

# Stage — big work protocol

Use when the work spans surfaces, carries risk (data, prod, money), or
will outlive one sitting. Otherwise don't — that's the two-tier rule.

## Files

`stages/NNN-slug/` (next free NNN, three digits):

**`brief.md`** — written before starting:

- Goal: one sentence, testable.
- Grounding: relevant memory notes as `[[slug]]` links, or the words
  "no prior art" — an honest empty beats a decorated citation.
- Approach, plus 1-2 alternatives considered (one line each, with the
  reason they lost).
- Units: numbered list. Per unit: expected outcome (phrased as a check
  that can fail, not a wish) and rollback (a command or "revert commit").

**`report.md`** — written at close:

- Per unit: what shipped (commits, paths), evidence for the expected
  outcome, and the verifier verdict.
- Aggregate: shipped / partial / abandoned — with the honest reason.

Two files total. No plan.json, no sha256 sidecars, no locks, no run ids.

## Rules

- Show the owner `brief.md` before executing when scope is debatable.
  The contract's parking rule applies: silence doesn't rot a stage,
  it parks it.
- Parallel units run in worktrees, one surface per unit, merge order
  stated in the brief. Parallel edits to the same files lose work —
  this stack once had parallel migrations silently clobber each
  other's SQL function bodies.
- The report's verdict comes from the `verifier` agent with fresh
  context; paste its summary line and link its evidence. A report
  without a verifier pass is `partial`, whatever the units claim.
- Units unfinished at close become `BACKLOG.md` items — never silent loss.
- The stage taught something → skill `remember` before closing.
