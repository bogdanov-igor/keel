---
name: code-audit
description: Review a diff or file set for correctness, safety, performance, and style defects — line-cited findings, each with one concrete fix, ranked into BACKLOG.md.
---

# Code audit

One audit = one target: a file, a git diff ref, or a glob. Anything
wider (a subsystem, several surfaces) is a stage (skill `stage`) that
dispatches several targeted audits.

## Before starting

Read the matching section of `memory/MEMORY.md` and grep `memory/` by
the surface or symptom. Known traps in this code are checked as
regressions, not rediscovered.

## Procedure

1. Collect target files.

   ```bash
   # target is a diff ref
   git diff "$target" --name-only
   # target is a file or glob
   find . -path "$target" -type f
   ```

   Target missing or diff empty → stop and report it; verify the
   target path rather than reviewing a guess.

2. Static pattern sweep — cheap, per file, before reading:

   ```bash
   # stray logging in non-debug files
   grep -n "console\.log\|console\.error" "$file" | grep -v "// debug\|// log"
   # hardcoded secrets
   grep -nE "(password|secret|api_key|token)\s*=\s*['\"][^'\"]{8,}" "$file"
   # await sites worth checking against their enclosing function
   grep -n "await " "$file" | head -5
   # imports, to spot unused ones while reading
   grep -n "^import " "$file"
   ```

3. Read each target file in full and assess four dimensions:
   - Correctness: off-by-one, null dereference, missing error
     propagation, wrong types.
   - Safety: injection vectors, unvalidated input reaching sensitive
     operations, credential exposure.
   - Performance: N+1 queries, unbounded loops, sync I/O in async
     context.
   - Style: dead code, inconsistent or unclear naming, overly complex
     functions.

4. Grade every candidate with severity (critical / major / minor) and
   confidence (high / medium / low). Discovery is exhaustive: a
   requested reporting threshold filters only what lands in the
   backlog, never how hard you look. Keep uncertain findings, marked
   low confidence, and let the reader decide.

5. Attach one concrete fix per finding — an exact change, e.g.
   "replace the literal with `process.env.API_KEY`; the value goes to
   `.secrets.env`, referenced as `{{secret:API_KEY}}`" — never
   "consider refactoring".

## Ranking and output

Map severity to backlog rank:

- critical (exploitable, data loss, crash in a live path) → P0 if it
  affects users now, else P1
- major (broken behavior, real but unexercised risk) → P1
- minor (quality debt) → P2; pure polish → P3

Write each finding as a BACKLOG.md line:

`- [ ] P1 | <file:line> | <defect + fix, one line> | ev:<path:line> | src:code-audit`

Close with honest totals — files reviewed, counts per severity, and
what the target did not cover ("audited" must never silently mean
"sampled"). Zero critical or major findings means the target is clean;
otherwise the P0/P1 lines are the verdict. Critical safety findings
usually deserve a dedicated security pass — queue that as its own
BACKLOG item instead of widening this audit.

If the review surfaced a non-obvious trap class new to this codebase,
record it via skill `remember`.

## Anti-patterns

- Letting a severity threshold narrow the search instead of only the
  output — low-severity and low-confidence findings still get graded.
- Flagging `console.log` in test files or files with `// debug`
  markers as safety issues.
- Suggesting architectural refactors — out of scope here; queue a
  BACKLOG item for a design review instead.
- Vague suggestions ("improve this code"); every fix names the exact
  change.
