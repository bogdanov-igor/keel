---
name: performance-profiling
description: Profile a Node/Bun/Python/Go service for CPU hotspots, memory leaks, slow DB queries, and N+1 patterns — findings land in BACKLOG.md as a prioritized fix list with evidence.
---

# performance-profiling

Before starting, read the matching section of memory/MEMORY.md and grep memory/
by topic for prior performance notes on this service. Establish (infer from the
repo, or ask one targeted question):

- runtime: node | bun | python | go — determines tooling
- db type and ORM (prisma | drizzle | sequelize | sqlalchemy | none) — for query and N+1 analysis
- hot paths (known slow endpoints) — to focus the scan
- pre-captured profile data (profile.json / flamegraph), if any — without it, static analysis only

## Procedure

1. Static N+1 detection. Grep ORM calls inside loops:
   ```bash
   cd "$project_path"
   # Prisma/Drizzle: find await db.* inside for/while/map
   grep -n 'await.*\.\(findMany\|findUnique\|findFirst\|select\|query\)' \
     $(grep -rl 'for\s*(\|while\s*(\|\.map(' src/ app/ lib/ 2>/dev/null) 2>/dev/null | head -20
   ```

2. Missing index detection. If a database is in play, grep schema files for
   foreign key columns without a corresponding index:
   ```bash
   grep -n 'references\|REFERENCES\|@relation' \
     $(find "$project_path" -name "schema.prisma" -o -name "schema.sql" 2>/dev/null) | head -30
   ```
   Cross-reference with explicit index declarations. Flag FK columns with no index.

3. Uncached aggregate queries. Grep API handlers for COUNT/SUM/AVG without cache annotation:
   ```bash
   grep -rn 'COUNT\|SUM\|AVG\|aggregate' --include="*.ts" --include="*.py" \
     src/ app/ lib/ 2>/dev/null | grep -v 'cache\|memo\|redis\|stale'
   ```

4. Memory leak patterns. Grep for the common ones:
   - Event listeners without `removeEventListener`.
   - `setInterval` without `clearInterval`.
   - Unbounded Maps/Sets used as caches (no TTL/eviction logic).

5. Profile data analysis. If profile data was provided:
   - Parse top 10 frames by CPU time.
   - Identify frames exceeding 10% of total wall time.
   - Correlate with source files in the repo.

6. Rank findings:
   - P0: N+1 on a hot path; missing index on an FK with high cardinality.
   - P1: uncached aggregate on a hot page; memory leak with unbounded growth.
   - P2: suboptimal query (no LIMIT, missing select projection).
   - P3: micro-optimization opportunity.

## Output

Append each finding to BACKLOG.md, one line per finding:

```
- [ ] P0 | src/api/projects.ts:47 | N+1: prisma.findUnique inside .map() — batch with findMany({ id: { in: ids } }) + Map lookup | ev:src/api/projects.ts | src:performance-profiling
- [ ] P0 | schema.prisma:88 | project_id FK has no @@index — full table scan on every join; add @@index([project_id]) | ev:schema.prisma | src:performance-profiling
```

Include the fix hint in the one-liner where it fits. Close with a short chat
summary: finding counts by severity, which fixes to take first (measure query
time before/after), and what was not covered. If fixing spans multiple surfaces
or hours, run it via skill stage. If dynamic profiling is required (no profile
data and hot paths not statically analyzable), say so and add a P2 BACKLOG line
to capture a profile rather than guessing.

Dynamic profiler runs (clinic, 0x, py-spy) and any app process they attach to
are persistent processes — launch them via skill safe-dev-server so the child
process tree stays under the circuit breaker. Any credentials needed to hit an
endpoint come from `{{secret:KEY}}` references backed by .secrets.env — never
inline values.

After the pass, record non-obvious causes or repo-specific gotchas via skill
remember; skip findings the BACKLOG lines already capture.

## Anti-patterns

- Recommending premature optimization — no caching before confirming the query is actually slow.
- Flagging ORM calls as N+1 when they sit inside a batch/transaction with an explicit `in` clause.
- Recommending database engine changes — fix queries and indexes first.
- Analyzing test fixtures or seed scripts as production hot paths.
