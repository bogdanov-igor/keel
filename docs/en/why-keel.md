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
Keel 1.6.0. Token figures are estimates at ~4 characters/token and are marked
as such; everything else is an exact count.

| | SkillForge 1.8.2 | Keel 1.6.0 | Delta |
|---|---|---|---|
| Always-loaded contract | `CLAUDE.md` (80 lines) + `_protocol.md` (247 lines) = **327 lines / 15,245 chars** (~3.8k tokens est.) | `CLAUDE.md` = **81 lines / 4,227 chars** (~1.1k tokens est.) | **3.6× smaller** |
| Kernel code to trust and maintain | **6,316 lines** of TS/JS/shell across 17 files — MCP server, embedding pipeline, retrieval eval, sync, update, verify | **1,701 lines** of shell across 10 files — installer, 3 hooks, safe-run launcher, migration sweep, memory graph, code anchors, archive builder, kernel self-tests. **1,478 lines across 8 files ship into a project**; the archive builder (66) and the self-tests (157) — **223 across 2** — are maintainer-only and never reach a user | **3.7× less** |
| Runtime services required | **2** — an MCP server (bun) + an Ollama daemon serving `bge-m3` embeddings | **0** | — |
| Installed footprint | **63 MB / 3,796 files** (24 MB of `node_modules` for the MCP server; the remainder is the vector index plus `.tgz` archives the updater made *of itself*). Clean shipped tree, excluding those: 4.3 MB / 133 files | **312 KB / 54 files** | **14×** smaller than its cleanest measure; **207×** smaller than what it becomes in a working project |
| Subagents | **8 personas** — orchestrator, product, qa, security, devops, research, copy, skill-creator | **2 by context isolation** — `scout` (read-only exploration), `verifier` (independent judge) | — |
| Retrieval | embeddings (`bge-m3` via Ollama) + reranker + PageRank over the note-to-note graph | `MEMORY.md` index + `grep` + code anchors (`recall`) | — |
| Retrieval golden set it was built to serve | **6 queries**, saturated at recall@5 = 1.0 | n/a | — |
| Ceremony before the first line of code | protocol + `plan.json` + `because[]` citations + approval gate — identical for an architecture rewrite and a padding fix | **0 files** for small work; **2 files** (brief, report) for big work | — |

**The kernel grew, and this table says so.** At 1.3.0 it was 893 lines of shell
across 5 files — a 7.1× advantage. Version 1.4.0 added the migration sweep, the
update check and the memory-graph tool: 1,305 lines across 8 files, and the
advantage fell to 4.8×. Version 1.5.0 added the code-anchor resolver: 1,460
lines across 9 files, and the advantage fell again, to 4.3×. Version 1.6.0 added
kernel self-tests: **1,701 lines across 10 files**, and it fell to **3.7×**. Of
that last +241 lines, **157 are the test suite itself** — code that *raises* the
'code to trust' count while making every other line safer to trust. That is the
honest tension, not something to bury; and SkillForge's 6,316 counted its own
eval harness too, so measuring keel's tests against it is apples-to-apples.
Every line added is a line someone has to trust; a comparison that only ever
improves is a comparison being managed.

**The kernel now tests itself.** `test/run.sh` is bash assertions over the
shipped scripts (`anchors.sh`, `graph.sh`, `sweep.sh`, `update-check.sh`):
throwaway fixtures, offline, non-zero exit on any failure. `build-archive.sh`
runs them first and refuses to build the archive if one fails — a script that
fails its own test never ships. The reason it exists: each of the last three
releases carried a real bug in a kernel script that only careful review caught —
`--check` missed the rename `handleRequest` → `handleRequestV2` because
`grep -F` matches a substring; the `MENTIONED` list ranked by matching lines
rather than mentions. The suite encodes exactly those cases so they cannot come
back. It is a maintainer tool — 157 of the 1,701 lines, and it never lands in a
project.

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

Two different graphs keep getting confused, and at 1.4.0 this document confused
them — it oversold the one that matters less. Separate them: there is a
**note-to-note** graph, and there is a **code-to-knowledge** graph. Only the
second one helps you write code.

**The note-to-note graph is memory hygiene. That is all it is.** The edges are
the `[[wikilinks]]` inside `memory/*.md`, where they always were. A real project
memory of 222 notes (plus the `MEMORY.md` index) carries **919 edges**,
**0 dead links** and **4 orphans** — `graph.sh` prints exactly those figures:

```sh
bash .claude/skills/memory-consolidation/graph.sh           # hubs, dead links, orphans, totals
bash .claude/skills/memory-consolidation/graph.sh --edges   # raw adjacency list
```

Hubs, dead links, orphans — that is a maintenance report on the notes. It is
genuinely useful for that, and for nothing else. It does not tell you anything
about the code you are about to change. (`memory/` is plain markdown with
`[[wikilinks]]`, so it also happens to open in Obsidian or VS Code Foam. That is
a property of the file format, not a feature of the kernel.)

**SkillForge's PageRank ran over that same note-to-note graph. It never knew the
code.** It *rebuilt* the graph from the same `[[wikilinks]]` in the same files on
every search (`retrieval-eval.ts`, `buildLinkGraph`), then ran personalized
PageRank over it — "HippoRAG-lite" — as a boost multiplier: `1 + 0.2 * graph` on
top of `0.8 * vector + 0.2 * keyword`. It cached a copy to
`.data/wikilink-graph.json` "for inspection", in its own words — a derived
artifact, regenerable from the notes at any moment. Notes pointing at notes. Not
one edge in it ever touched a source file.

**What Keel dropped is that scorer, not the graph.** And the scorer's value was
never demonstrated: the whole retrieval stack saturated at **recall@5 = 1.0 on a
golden set of 6 queries**. At the ceiling you cannot attribute credit to the
graph term — or to any other term. The edges survived, the scorer did not, and
the scorer's contribution was unmeasurable because the eval was saturated.

**The edge neither system had: knowledge anchored to code locations.** That is
`recall`, new in 1.5.0. Memory grounding worked by *symptom* — grep the error
text and hope — never by *location*. In that same project memory, **141 notes
name code files: 494 mentions across 237 unique files**, and none of it was
reachable from the code. You could not ask *"what does this project know about
`apps/web/proxy.ts`?"* before opening it. (The reproduce command is at the bottom.)

A note now declares the code it is about, in front-matter:

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

Two queries, no scorer, no embeddings, no daemon — an anchor either resolves or
it does not:

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
bash .claude/skills/recall/anchors.sh --check             # dead anchors
```

Results come back in two sets. **ANCHORED** — exact, checkable. **MENTIONED** —
prose mentions, ranked by density: useful, but noisy and uncheckable, which is
precisely the argument for anchoring.

**Rot detection is the point.** Rename a symbol or delete a file and `--check`
reports `DEAD_SYMBOL` / `DEAD_FILE` — both verified end-to-end, a rename and a
delete, each caught. A prose mention can never be checked; that is the whole
difference between a mention and an anchor.

**Code→code edges are not built here, deliberately.** serena (LSP, already seeded
in `.mcp.json`) computes callers, references and call hierarchy exactly and live
— `find_symbol`, `find_referencing_symbols`. Hand-maintained code structure rots;
an LSP does not. The anchors layer carries only what an LSP cannot know: what we
*learned* about a place in the code.

**Who walks the graph: the model.** Rule 2 of the contract sends it to the
`memory/MEMORY.md` index, tells it to *"follow links that match the task"*, and
now also: *"Before changing a file you did not just write, ground by location:
`skill recall`."* That routing line is why the contract grew from 79 to 81 lines
— a skill nobody is routed to is a skill nobody uses, which is exactly how the
predecessor's skill catalog died.

## What Keel keeps

Four things earned their place, and they are all that survived:

- **Files as the only shared truth** — `memory/`, `BACKLOG.md`, `PARKED.md`,
  `OPS.md`, `stages/`. Greppable, diffable, no daemon.
- **Two hooks that stopped real incidents** — the secret-leak guard, and the
  dev-server forkbomb circuit breaker (Next.js + Turbopack fork-bombed a Mac;
  that antipattern is in memory too).
- **`verifier` as an independent judge** — a self-report is a claim, not a
  verdict. The one multi-agent pattern that reliably paid off.
- **Skills, lazy-loaded** — 37 of them, most ported from the predecessor and
  stripped of its machinery. They only enter context when used.

And two things Keel *adds*. `OPS.md`, the duty board — standing
responsibilities with a cadence, each mapped to a skill, in `build` or `live`
mode: what makes end-to-end ownership routable instead of aspirational. And
code anchors (skill `recall`, new in 1.5.0) — the edge neither system had:
knowledge reachable *from* the code it is about. SkillForge's PageRank ran over
a note-to-note graph; it never knew the code at all.

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

What *is* established: Keel loads 3.6× less contract on every task, asks you to
trust 3.7× less code, requires zero runtime services where SkillForge required
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

# the note-to-note graph: 222 notes, 919 edges, 0 dead links, 4 orphans
bash .claude/skills/memory-consolidation/graph.sh

# memory names code, but code could not reach memory: 141 of 222 notes,
# 494 mentions, 237 unique files — one command, one extension set
EXT='\.(ts|tsx|js|jsx|sql|py|go)'
grep -rlE "$EXT" memory --include='*.md' | grep -v MEMORY.md | wc -l   # notes
grep -rhoE "[A-Za-z0-9_/.-]+$EXT" memory --include='*.md' | wc -l      # mentions
grep -rhoE "[A-Za-z0-9_/.-]+$EXT" memory --include='*.md' | sort -u | wc -l
```

---

**Author:** Igor Bogdanov · <bogdanov.ig.alex@gmail.com>
