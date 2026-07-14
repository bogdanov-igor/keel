---
name: audit
description: Scoped audit of one surface/dimension — evidence-backed findings ranked P0-P3 straight into BACKLOG.md. Respects the WIP limit (20+ open findings → burn down, don't audit) and states what was not covered.
---

# Audit

## Before starting

Count open `src:audit*` items in `BACKLOG.md`. At 20 or more, stop:
burn down instead (contract rule 6). This stack's history: two audits
produced 194 findings, ~58 never closed — finding-generation that
outpaces fixing is motion, not progress.

## Scope

One audit = one dimension on one surface, stated in one line at the
top ("public hub, mobile layout"; "API auth paths"). A whole-product
audit is a stage (skill `stage`) that dispatches several scoped audits.

## Procedure

1. Ground: read the matching `memory/MEMORY.md` section first. Known
   traps on this surface are checked-for-regression, not re-discovered.
2. Evidence per finding: `path:line`, a qa-browser output file, or a
   reproducible command. No evidence → no finding.
3. Rank: P0 broken for users or data loss · P1 broken flow or broken
   promise · P2 quality debt · P3 polish.
4. Write findings into `BACKLOG.md`:
   `- [ ] P1 | <surface> | <defect, one line> | ev:<path> | src:audit-NNN`
   (NNN = next audit number; grep BACKLOG for the last one).
5. Fixing, same or later session: every P0/P1 fix is verified before
   its checkbox closes — qa-browser for UI, `verifier` agent for
   stage-level claims.

## Report

Totals honestly: found N (P0 a / P1 b / P2 c / P3 d), plus what the
scope did NOT cover — "audited" must never silently mean "sampled".
