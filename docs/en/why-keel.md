# Why Keel, and what changed from SkillForge

Keel is the successor to SkillForge — same author, same problem, opposite
conclusion. SkillForge tried to give an AI agent a *system*: an MCP server, a
vector index over project memory, a reranker, agent personas, approval gates,
per-task artifacts, an updater. Keel keeps the four things that carried weight
and deletes the rest.

This document states what was measured, what was observed in production, and —
importantly — **what was not measured**. Every number below is reproducible
from the two trees; the commands are at the bottom.

## The measurements

Compared: SkillForge 1.8.2 as deployed in the ShipPulse project, against
Keel 1.4.0. Token figures are estimates at ~4 characters/token and are marked
as such; everything else is an exact count.

| | SkillForge 1.8.2 | Keel 1.4.0 | Delta |
|---|---|---|---|
| Always-loaded contract | `CLAUDE.md` (80 lines) + `_protocol.md` (247 lines) = **327 lines / 15,245 chars** (~3.8k tokens est.) | `CLAUDE.md` = **79 lines / 4,094 chars** (~1.0k tokens est.) | **3.7× smaller** |
| Kernel code to trust and maintain | **6,316 lines** of TS/JS/shell across 17 files — MCP server, embedding pipeline, retrieval eval, sync, update, verify | **1,305 lines** of shell across 8 files — installer, archive builder, 3 hooks, safe-run launcher, migration sweep, memory graph | **4.8× less** |
| Runtime services required | **2** — an MCP server (bun) + an Ollama daemon serving `bge-m3` embeddings | **0** | — |
| Installed footprint | **63 MB / 3,796 files** (24 MB of `node_modules` for the MCP server; the remainder is the vector index plus `.tgz` archives the updater made *of itself*). Clean shipped tree, excluding those: 4.3 MB / 133 files | **288 KB / 52 files** | **15×** smaller than its cleanest measure; **224×** smaller than what it becomes in a working project |
| Subagents | **8 personas** — orchestrator, product, qa, security, devops, research, copy, skill-creator | **2 by context isolation** — `scout` (read-only exploration), `verifier` (independent judge) | — |
| Retrieval | embeddings (`bge-m3` via Ollama) + reranker + PageRank over the note graph | `MEMORY.md` index + `grep` | — |
| Retrieval golden set it was built to serve | **6 queries**, saturated at recall@5 = 1.0 | n/a | — |
| Ceremony before the first line of code | protocol + `plan.json` + `because[]` citations + approval gate — identical for an architecture rewrite and a padding fix | **0 files** for small work; **2 files** (brief, report) for big work | — |

**The kernel grew, and this table says so.** At 1.3.0 it was 893 lines of shell
across 5 files — a 7.1× advantage. Version 1.4.0 added the migration sweep, the
update check and the memory-graph tool, and the advantage fell to 4.8×. Every
line added is a line someone has to trust; a comparison that only ever improves
is a comparison being managed.

## What production actually said

The numbers explain the cost. These four notes — all from ShipPulse's own
memory, written while SkillForge was the live system — explain the damage.
They are the primary sources, not reconstructions.

**1. The retrieval infrastructure killed the work it was serving.**
`antipatterns/skillforge-mcp-misreports-ollama-when-direct-call-works.md`:
on macOS Apple Silicon, `OLLAMA_NUM_PARALLEL=4` × `bge-m3` Metal heaps under
bursty embedding blew out VM commit → the OS OOM-killed Ollama → the failure
cascaded into the IDE host. It **killed ShipPulse stage 009 mid-fan-out on
2026-05-31 and lost three subagent artifacts.** The memory system destroyed
the work it existed to remember.

**2. The system's own shipping pattern routed around its own retrieval.**
`patterns/stage-012-013-multiwave-ship-pattern.md` — the operating pattern for
SkillForge's most successful shipping run — instructs, verbatim: *"Sub-agents
do NOT call MCP memory (ollama path is flaky); they grep `memory/**`"*, and
memory notes are *"written as direct files (the MCP `memory_write` embed 500s
while ollama is degraded)"*. The vector index, the reranker and the PageRank
graph were bypassed **by the system's own best practice** — in favor of grep
and plain files. Keel is that bypass, promoted to the design.

**3. The gates were bypassed under pressure — by design pressure, not laziness.**
`antipatterns/engine-bypass.md` documents runs skipping the approval gate and
marking units green without artifacts, because *"gates feel bureaucratic under
time pressure"*. A gate that gets bypassed on the important runs is not a
safety mechanism; it is a tax on the unimportant ones.

**4. The personas kept absorbing the work they were supposed to route.**
`antipatterns/fat-agent-prompt.md`: agent files had to be policed by a hard
55-line cap enforced by a `verify` check, because they kept growing domain
logic and diverging from the skill catalog. Roles need policing; context
isolation does not. Keel decomposes by context, not by job title — matching
Anthropic's own finding that role-shaped subagents spend more tokens
coordinating than working.

### What about the graph?

The retrieval row above is about a *scorer*, not about the graph. The graph is
still here.

**The edges are the `[[wikilinks]]`**, inside `memory/*.md`, where they always
were. A real project memory of 222 notes (plus the `MEMORY.md` index) carries
**919 edges**, **0 dead links** and **4 orphans** — run `graph.sh` below and it
prints exactly those figures. Removing the MCP server changed none of that.

**SkillForge's graph was not a source of truth either.** It *rebuilt* the graph
from the same `[[wikilinks]]` in the same files on every search
(`retrieval-eval.ts`, `buildLinkGraph`), then ran personalized PageRank over it
— "HippoRAG-lite" — as a boost multiplier: `1 + 0.2 * graph` on top of
`0.8 * vector + 0.2 * keyword`. It did cache a copy to
`.data/wikilink-graph.json` "for inspection", in its own words — a derived
artifact, regenerable from the notes at any moment, and the notes are what
Keel kept.

**What Keel dropped is that scorer, not the graph.** And the scorer's value was
never demonstrated: the whole retrieval stack saturated at **recall@5 = 1.0 on a
golden set of 6 queries**. At the ceiling you cannot attribute credit to the
graph term — or to any other term. The edges survived, the scorer did not, and
the scorer's contribution was unmeasurable because the eval was saturated.

**Who walks the graph now: the model.** Rule 2 of the contract says to read the
`memory/MEMORY.md` index and *"follow links that match the task"*. Multi-hop
associative retrieval, performed by the reader instead of by a scoring function.

Seeing the graph:

```sh
bash .claude/skills/memory-consolidation/graph.sh           # hubs, dead links, orphans, totals
bash .claude/skills/memory-consolidation/graph.sh --edges   # raw adjacency list
```

No index, no daemon, no build step. And the picture comes free: `memory/` is
markdown with `[[wikilinks]]`, so it opens in Obsidian or VS Code Foam as a
visual graph with zero dependencies added — SkillForge called these same links
"the Foam display graph".

## What Keel keeps

Four things earned their place, and they are all that survived:

- **Files as the only shared truth** — `memory/`, `BACKLOG.md`, `PARKED.md`,
  `OPS.md`, `stages/`. Greppable, diffable, no daemon.
- **Two hooks that stopped real incidents** — the secret-leak guard, and the
  dev-server forkbomb circuit breaker (Next.js + Turbopack fork-bombed a Mac;
  that antipattern is in memory too).
- **`verifier` as an independent judge** — a self-report is a claim, not a
  verdict. The one multi-agent pattern that reliably paid off.
- **Skills, lazy-loaded** — 36 of them, ported from the predecessor and
  stripped of its machinery. They only enter context when used.

And one thing Keel *adds*: `OPS.md`, the duty board — standing
responsibilities with a cadence, each mapped to a skill, in `build` or `live`
mode. It is what makes end-to-end ownership routable instead of aspirational.

## What was NOT measured

Stated plainly, because a comparison that hides its gaps is marketing:

- **No head-to-head task benchmark was run.** We did not execute a fixed task
  suite under both kernels and compare tokens, wall-clock, or success rate.
  Every number in the table above is a *structural* measurement (sizes, counts,
  lines) or a production incident with a date — none is a controlled experiment.
- **The token figures are estimates**, derived from character counts at ~4
  chars/token, not from a tokenizer.
- **"Better" here means: less to load, less to trust, less to break.** It does
  not mean "produces better code" — that claim would need the benchmark above,
  and it has not been run.

What *is* established: Keel loads 3.7× less contract on every task, asks you to
trust 4.8× less code, requires zero runtime services where SkillForge required
two, and removes the exact component that OOM-killed a live stage — a component
the predecessor's own operating pattern had already told its agents to avoid.

## Reproducing the numbers

```sh
# always-loaded contract
wc -lc skillforge-project/.claude/CLAUDE.md skillforge-project/.claude/_protocol.md
wc -lc keel/bundle/.claude/CLAUDE.md

# kernel code
find skillforge -name '*.ts' -o -name '*.js' -o -name '*.sh' \
  | grep -v node_modules | xargs cat | wc -l
find keel -name '*.sh' -not -path '*/dist/*' | xargs cat | wc -l

# footprint
du -sh skillforge && find skillforge -type f | wc -l
du -sh keel/bundle && find keel/bundle -type f | wc -l

# the golden set the retrieval stack was built to serve
python3 -c "import json; print(len(json.load(open('skillforge/retrieval-eval.golden.json'))))"
```

---

**Author:** Igor Bogdanov · <bogdanov.ig.alex@gmail.com>
