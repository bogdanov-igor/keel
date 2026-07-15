# Why Keel, and what changed from SkillForge

Keel is the successor to SkillForge: same author, same problem, opposite
conclusion. SkillForge tried to give an AI agent a whole system — an MCP
server, a vector index over project memory, a reranker, agent personas,
approval gates, per-task artifacts, an updater. Keel keeps the four things
that carried weight and deletes the rest.

I retired SkillForge, and this document is the reasoning: what was measured,
what production showed, and — just as important — what was not measured.
Every number below is reproducible from the two trees; the commands are at
the bottom.

## The measurements

Compared: SkillForge 1.8.2 as deployed in the ShipPulse project, against
Keel 1.6.0. Token figures are estimates at ~4 characters per token and are
marked as such; everything else is an exact count.

| | SkillForge 1.8.2 | Keel 1.6.0 | Delta |
|---|---|---|---|
| Always-loaded contract | `CLAUDE.md` (80 lines) + `_protocol.md` (247 lines) = 327 lines / 15,245 chars (~3.8k tokens est.) | `CLAUDE.md` = 81 lines / 4,227 chars (~1.1k tokens est.) | 3.6× smaller |
| Kernel code to trust and maintain | 6,316 lines of TS/JS/shell across 17 files — MCP server, embedding pipeline, retrieval eval, sync, update, verify | 1,701 lines of shell across 10 files — installer, 3 hooks, safe-run launcher, migration sweep, memory graph, code anchors, archive builder, kernel self-tests. 1,478 lines across 8 files ship into a project; the archive builder (66) and the self-tests (157) — 223 lines across 2 files — are maintainer-only and never reach a user | 3.7× less |
| Runtime services required | 2 — an MCP server (bun) + an Ollama daemon serving `bge-m3` embeddings | 0 | — |
| Installed footprint | 63 MB / 3,796 files (24 MB of `node_modules` for the MCP server; the remainder is the vector index plus `.tgz` archives the updater made of itself). Clean shipped tree, excluding those: 4.3 MB / 133 files | 312 KB / 54 files | 14× smaller than its cleanest measure; 207× smaller than what it becomes in a working project |
| Subagents | 8 personas — orchestrator, product, qa, security, devops, research, copy, skill-creator | 2, split by context isolation — `scout` (read-only exploration), `verifier` (independent judge) | — |
| Retrieval | embeddings (`bge-m3` via Ollama) + reranker + PageRank over the note-to-note graph | `MEMORY.md` index + `grep` + code anchors (`recall`) | — |
| Retrieval golden set it was built to serve | 6 queries, saturated at recall@5 = 1.0 | n/a | — |
| Ceremony before the first line of code | protocol + `plan.json` + `because[]` citations + approval gate — identical for an architecture rewrite and a padding fix | 0 files for small work; 2 files (brief, report) for big work | — |

The kernel grows from release to release, and the table says so. At 1.3.0 it
was 893 lines of shell across 5 files — a 7.1× advantage. 1.4.0 added the
migration sweep, the update check and the memory-graph tool: 1,305 lines
across 8 files, and the advantage fell to 4.8×. 1.5.0 added the code-anchor
resolver: 1,460 lines across 9 files, 4.3×. 1.6.0 added the kernel
self-tests: 1,701 lines across 10 files, 3.7×. Of that last +241 lines, 157
are the test suite itself — code that raises the "code to trust" count while
making every other line safer to trust. That tension is stated here rather
than buried, and SkillForge's 6,316 lines counted its own eval harness too,
so measuring Keel's tests against it is apples to apples. Every line added
is a line someone has to trust; a comparison that only ever improves is a
comparison being managed.

The kernel now tests itself. `test/run.sh` is a set of bash assertions over
the shipped scripts (`anchors.sh`, `graph.sh`, `sweep.sh`,
`update-check.sh`): throwaway fixtures, offline, non-zero exit on any
failure. `build-archive.sh` runs them first and refuses to build the archive
if one fails, so a script that fails its own test never ships. The suite
exists because each of the last three releases carried a real bug in a
kernel script that only careful review caught: `--check` missed the rename
`handleRequest` → `handleRequestV2` because `grep -F` matches a substring,
and the MENTIONED list ranked by matching lines rather than mentions. The
suite encodes exactly those cases so they cannot come back. It is a
maintainer tool — 157 of the 1,701 lines — and it never lands in a project.

## What production showed

The numbers explain the cost. The damage is documented in four notes from
ShipPulse's own memory, written while SkillForge was the live system. They
are primary sources, not reconstructions.

### 1. The retrieval infrastructure killed the work it was serving

`antipatterns/skillforge-mcp-misreports-ollama-when-direct-call-works.md`:
on macOS Apple Silicon, `OLLAMA_NUM_PARALLEL=4` × `bge-m3` Metal heaps
under bursty embedding load blew out VM commit, the OS OOM-killed Ollama,
and the failure cascaded into the IDE host. On 2026-05-31 it killed
ShipPulse stage 009 mid-fan-out and lost three subagent artifacts. The
memory system destroyed the work it existed to remember.

### 2. The system's own shipping pattern routed around its retrieval

`patterns/stage-012-013-multiwave-ship-pattern.md` — the operating pattern
for SkillForge's most successful shipping run — instructs, verbatim:
"Sub-agents do NOT call MCP memory (ollama path is flaky); they grep
`memory/**`", and memory notes are "written as direct files (the MCP
`memory_write` embed 500s while ollama is degraded)". The vector index, the
reranker and the PageRank graph were bypassed by the system's own best
practice, in favor of grep and plain files. Keel is that bypass, promoted
to the design.

### 3. The gates were bypassed under pressure

`antipatterns/engine-bypass.md` documents runs skipping the approval gate
and marking units green without artifacts, because "gates feel bureaucratic
under time pressure". The pressure came from the design, not from lazy
operators. A gate that gets bypassed on the important runs is not a safety
mechanism; it is a tax on the unimportant ones.

### 4. The personas kept absorbing the work they were supposed to route

`antipatterns/fat-agent-prompt.md`: agent files had to be policed with a
hard 55-line cap enforced by a `verify` check, because they kept growing
domain logic and diverging from the skill catalog. Roles need policing;
context isolation does not. Keel splits subagents by context rather than by
job title, which matches Anthropic's own finding that role-shaped subagents
spend more tokens coordinating than working.

## Knowledge anchored to code

New in 1.5.0: the `recall` skill, code anchors.

Before it, memory grounding worked by symptom — grep `memory/` for words
from the error and hope — and never by location. In a real project memory
of 222 notes, 141 name code files: 494 mentions across 237 unique files,
and none of it was reachable from the code. You could not ask what the
project knows about `apps/web/proxy.ts` before opening the file. (The
reproduce command is at the bottom.)

An anchor is a front-matter declaration: the note states which code it is
about.

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

Two queries follow — no scorer, no embeddings, no daemon; an anchor either
resolves or it does not:

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
bash .claude/skills/recall/anchors.sh --check             # dead anchors
```

Results come back in two sets. ANCHORED — notes that declared the code in
front-matter: exact and checkable. MENTIONED — prose mentions, ranked by
density: useful, but noisy, and there is no way to check them.

Rot detection is what the anchors are for. Rename a symbol or delete a file
and `--check` reports `DEAD_SYMBOL` / `DEAD_FILE` — both paths verified end
to end, a rename and a delete, each caught. A prose mention can never be
checked; that is the difference between a mention and an anchor.

Code-to-code edges are not built here, deliberately. serena (an LSP, already
seeded in `.mcp.json`) computes callers, references and call hierarchy
exactly and live — `find_symbol`, `find_referencing_symbols`.
Hand-maintained code structure rots; an LSP does not. The anchors layer
carries only what an LSP cannot know: what the project learned about a
place in the code.

Contract rule 2 routes to the skill. It sends the model to the
`memory/MEMORY.md` index, tells it to "follow links that match the task",
and now also: "Before changing a file you did not just write, ground by
location: `skill recall`." That routing line is why the contract grew from
79 to 81 lines. A skill nobody is routed to is a skill nobody uses, which
is how the predecessor's skill catalog died.

### The note graph

Two different graphs keep getting confused, and at 1.4.0 this document
confused them too, overselling the one that matters less. The note-to-note
graph is memory hygiene; the code-to-knowledge graph above is the one that
helps with code.

The retrieval row in the table is about the scorer, not the graph. The
edges are still where they always were: `[[wikilinks]]` inside
`memory/*.md`. The real 222-note memory (plus the `MEMORY.md` index)
carries 919 edges, 0 dead links and 4 orphans — `graph.sh` prints exactly
those figures, and removing the MCP server changed none of them:

```sh
bash .claude/skills/memory-consolidation/graph.sh           # hubs, dead links, orphans, totals
bash .claude/skills/memory-consolidation/graph.sh --edges   # raw adjacency list
```

Hubs, dead links, orphans: a maintenance report on the notes, genuinely
useful for that and for nothing else. It does not help write code and does
not claim to. (`memory/` is plain markdown with `[[wikilinks]]`, so it also
opens in Obsidian or VS Code Foam. That is a property of the file format,
not a feature of the kernel.)

SkillForge's graph was the same note-to-note graph; it never knew the code.
It was not a source of truth either: SkillForge rebuilt it on every search
from the same `[[wikilinks]]` in the same files (`retrieval-eval.ts`,
`buildLinkGraph`), then ran personalized PageRank over it — "HippoRAG-lite"
— as a boost multiplier: `1 + 0.2 * graph` on top of
`0.8 * vector + 0.2 * keyword`. It cached a copy to
`.data/wikilink-graph.json`, in its own words "for inspection": a derived
artifact, regenerable from the notes at any moment. And the notes are
exactly what Keel kept.

What Keel dropped is that scorer, not the graph. The scorer's value was
never demonstrated: the whole retrieval stack saturated at recall@5 = 1.0
on a golden set of 6 queries, and at the ceiling credit cannot be
attributed to the graph term or to any other. The edges survived, the
scorer did not, and the scorer's contribution stayed unmeasurable because
the eval was saturated.

The links are now walked by the model: contract rule 2 tells it to read the
`memory/MEMORY.md` index and follow the links that match the task. No index
build, no daemon. Whether that is as good as the dropped scorer is not
claimed here — there was nothing to compare against while the eval sat at
its ceiling.

## What Keel keeps

Four things earned their place, and they are all that survived:

- Files as the only shared truth: `memory/`, `BACKLOG.md`, `PARKED.md`,
  `OPS.md`, `stages/`. Greppable, diffable, no daemon.
- Two hooks that stopped real incidents: the secret-leak guard and the
  dev-server forkbomb circuit breaker (Next.js + Turbopack fork-bombed a
  Mac; that antipattern is in memory too).
- `verifier` as an independent judge. A self-report is a claim, not a
  verdict — the one multi-agent pattern that reliably paid off.
- Skills, lazy-loaded: 37 of them, most ported from the predecessor and
  stripped of its machinery. They enter context only when used.

And two things Keel adds. `OPS.md`, the duty board: standing
responsibilities with a cadence, each mapped to a skill, in `build` or
`live` mode. It is what makes end-to-end ownership routable instead of
aspirational. The second addition is code anchors — the `recall` skill,
described above.

## What was NOT measured

Stated plainly, because a comparison that hides its gaps is marketing:

- No head-to-head task benchmark was run. Nobody executed a fixed task
  suite under both kernels and compared tokens, wall-clock or success rate.
  Every number in the table above is a structural measurement (sizes,
  counts, lines) or a production incident with a date; none is a controlled
  experiment.
- The token figures are estimates, derived from character counts at ~4
  chars/token, not from a tokenizer.
- "Better" here means less to load, less to trust, less to break. It does
  not mean "produces better code" — that claim would need the benchmark
  above, and it has not been run.

What is established: Keel loads 3.6× less contract on every task, asks you
to trust 3.7× less code, requires zero runtime services where SkillForge
required two, and removes the exact component that OOM-killed a live stage
— a component the predecessor's own operating pattern had already told its
agents to avoid.

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
