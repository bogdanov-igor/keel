---
name: tech-debt-audit
description: Quantify and classify technical debt in a codebase — TODO/FIXME density, stubs, dead exports, oversized files — and file a prioritized paydown list into BACKLOG.md; use when a codebase feels sludgy or before planning a refactor.
---

# tech-debt-audit

Grep-based debt census: deterministic for a given tree — same code, same numbers.
Before starting, read the matching section of memory/MEMORY.md and grep memory/ for
prior debt audits of this project. If BACKLOG.md already has 20+ open findings,
burn those down instead of auditing.

## Defaults

- Scan extensions: `.ts .tsx .js .jsx .py .go` (narrow this if generated/binary files inflate counts)
- Exclude: `node_modules dist build .git` plus vendor/generated dirs
- TODO density threshold: **0.05 TODOs per file** — modules above it get flagged
- Evidence dir: `.qa/tech-debt/` — raw grep dumps live here; BACKLOG lines point at them

## Procedure

1. **TODO/FIXME/HACK density.**
   ```bash
   mkdir -p .qa/tech-debt
   grep -rn "TODO\|FIXME\|HACK\|XXX\|WORKAROUND" \
     --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" --include="*.go" \
     --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=.git \
     . > .qa/tech-debt/todos.txt
   total_todos=$(wc -l < .qa/tech-debt/todos.txt)
   total_files=$(find . -path ./node_modules -prune -o -type f \
     \( -name "*.ts" -o -name "*.tsx" \) -print | wc -l)
   ```
   Compute `todo_density = total_todos / total_files`. Also count per top-level
   directory and flag any module whose own density exceeds the threshold.

2. **Stub / placeholder detection.**
   ```bash
   grep -rn "throw new Error.*not implemented\|stub\|placeholder\|Coming soon\|TBD\|return null.*// TODO" \
     src 2>/dev/null > .qa/tech-debt/stubs.txt
   ```

3. **Dead-code proxies** — exported symbols never referenced elsewhere
   (count ≤ 1 means only the export line itself matches).
   ```bash
   grep -rhoE "export (function|const|class) \w+" src | awk '{print $NF}' | sort -u | \
     while read -r name; do
       count=$(grep -rn "\b$name\b" src | wc -l)
       [ "$count" -le 1 ] && echo "DEAD: $name"
     done > .qa/tech-debt/dead.txt
   ```

4. **Complexity proxy** — file length and deep nesting, explicitly labeled
   "proxy", not real cyclomatic complexity.
   ```bash
   find src -name "*.ts" -o -name "*.tsx" | xargs wc -l 2>/dev/null | \
     sort -rn | head -20 > .qa/tech-debt/large.txt
   ```
   Files over ~400 lines are flags; for each, count lines indented 4+ levels
   (`grep -cE "^( {16}|\t{4})" <file>`) as a nesting-depth proxy.

5. **Classify each item.** Categories: `todo-debt`, `stub-debt`, `dead-code`,
   `complexity-debt`. Estimate effort: trivial / small / medium / large.

6. **File the paydown list into BACKLOG.md** — one line per item, ordered by
   priority then effort (cheap high-priority wins first).

## Output

Each debt item becomes one BACKLOG.md line:

```
- [ ] P1 | src/api/incidents/resolve.ts:34 | stub-debt: throw new Error('not implemented') in resolve handler, effort medium | ev:.qa/tech-debt/stubs.txt | src:tech-debt-audit
```

Priority mapping:

- **P0** — stub or dead path on a live critical flow (an unimplemented handler
  reachable in production).
- **P1** — blocks a feature or sits on the critical path (high).
- **P2** — real debt off the critical path (medium).
- **P3** — cosmetic or test-file TODOs (low).

End with a one-line summary in chat, e.g.
`47 TODOs (density 0.08), 12 stubs, 3 dead exports, 5 large files — worst module src/lib/`,
and state what was not covered (extensions or dirs skipped).

## Reading the result

- Healthy: density below threshold, zero P0/P1 stubs, zero dead exports.
- Above threshold, or any P0/P1 stub, or ≥1 dead export → debt is actionable;
  the BACKLOG lines are the work queue.
- Counts inflated by binary or generated files → rerun with narrower extensions
  rather than reporting noise.
- Paydown spanning multiple surfaces or hours → open it via skill stage, not
  inline fixes. A module that keeps regrowing debt across audits is a lesson —
  record it via skill remember.

## Anti-patterns

- Do not flag TODOs in test files as high priority; test todos are P3.
- Do not report every large file as debt; check whether it is generated or
  vendor code first.
- Do not skip the paydown list; raw counts without priority order are not
  actionable.
- Do not conflate the line-count proxy with actual cyclomatic complexity;
  always label it "proxy".
