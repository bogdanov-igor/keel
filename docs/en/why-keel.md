# Why Keel, and what changed from SkillForge

Keel is the successor to SkillForge: same problem, opposite conclusion.
SkillForge tried to give a coding agent a whole system — an MCP server of
its own, a vector index over project memory, a reranker, agent personas,
approval gates, per-task artifacts, an updater. Keel keeps the four things
that carried weight and deletes the rest.

I retired SkillForge, and this document is the post-mortem: what
production showed, what Keel does about each cause and, just as important,
what was never measured. Every number below is reproducible from the two
trees; the commands are at the bottom.

## The symptom

Not "it writes bad code". What went wrong is narrower and worse: the parts
of the system built to help were the parts everyone worked around.
Subagents were instructed in writing to avoid the memory server. The
approval gate got skipped on exactly the runs that mattered. Agent files
grew until a line cap had to be enforced by a check. And once the memory
system took a live stage down with it. The natural suspects — the model,
the contract file — were innocent: the always-on instructions were never
the problem, everything loaded and executed around them was.

## The diagnosis

Four causes, and the damage under each is documented in a note from
ShipPulse's own memory, written while SkillForge was the live system.
These are primary sources, not reconstructions.

### 1. The retrieval infrastructure killed the work it was serving

`antipatterns/skillforge-mcp-misreports-ollama-when-direct-call-works.md`:
on macOS Apple Silicon, `OLLAMA_NUM_PARALLEL=4` × `bge-m3` Metal heaps
under bursty embedding load blew out VM commit, the OS OOM-killed Ollama,
and the failure cascaded into the IDE host. On 2026-05-31 it killed
ShipPulse stage 009 mid-fan-out and lost three subagent artifacts. The
memory system destroyed the work it existed to remember.

Keel's memory is files: markdown notes plus a strict one-line index in
`memory/MEMORY.md`, retrieval is reading the index and grepping, and
`recall` adds a way in from the code side. No embedding model, no vector
store, no daemon whose silent failure can masquerade as memory loss.

### 2. The system's own shipping pattern routed around its retrieval

`patterns/stage-012-013-multiwave-ship-pattern.md` — the operating pattern
for SkillForge's most successful shipping run — instructs, verbatim:
"Sub-agents do NOT call MCP memory (ollama path is flaky); they grep
`memory/**`", and memory notes are "written as direct files (the MCP
`memory_write` embed 500s while ollama is degraded)". The vector index,
the reranker and the PageRank graph were bypassed by the system's own best
practice, in favour of grep and plain files. What the operators fell back
to is what Keel is made of.

### 3. The gates were bypassed under pressure

`antipatterns/engine-bypass.md` documents runs skipping the approval gate
and marking units green without artifacts, because "gates feel
bureaucratic under time pressure". The pressure came from the design, not
from lazy operators. A gate that gets bypassed on the important runs is
not a safety mechanism; it is a tax on the unimportant ones.

Keel has two tiers instead. Small work — do it, verify it, move on, no
process files. Big work — the `stage` skill and two files, a brief before
and a verifier-confirmed report after. And where a rule has to hold under
deadline pressure, 1.8.0 gave it a hook instead of a sentence: a secret
value refused on the write, a `N pass / M fail` count with no agent id
behind it refused in a stage report, the two-attempts rule put back into
context on the third identical failure of one command. A hook costs
nothing on the happy path and cannot be skipped because it feels
bureaucratic.

### 4. The personas kept absorbing the work they were supposed to route

`antipatterns/fat-agent-prompt.md`: agent files had to be policed with a
hard 55-line cap enforced by a `verify` check, because they kept growing
domain logic and diverging from the skill catalog. Roles need policing;
context isolation does not. Keel splits subagents by context rather than
by job title — `scout` reads on sonnet, `verifier` judges on opus, each on
the model its front-matter names — which matches Anthropic's own finding
that role-shaped subagents spend more tokens coordinating than working.

### What 1.8.0 stopped assuming

Three things the kernel carried as assumptions were measured on a live
Claude Code 2.1.87 and written into the [roadmap](../../ROADMAP.md). A
measurement on one CLI version is a measurement on one CLI version: a
harness release can undo any of them, and each takes minutes to re-run.

The contract survives compaction. A `PreCompact` hook rewrote
`.claude/CLAUDE.md` on disk while the compaction ran; on the next user
turn the model answered from the rewritten text, in both placements — the
`.claude/` file and a root `CLAUDE.md` — and `InstructionsLoaded` fired
with `load_reason: compact`. Inside the turn that was compacting, the old
text still held. No root pointer and no rules file, then; the placement
stays. What does not survive is the skill listing, which is why the
`recompact` hook hands back the active stage's goal, the open claims and
the gates.

Hooks work in a worktree. Parallel work runs as `claude --worktree` and
every guard reads files by path, so the question was which path.
`CLAUDE_PROJECT_DIR` turned out to be the worktree and the worktree's own
`settings.json` the one read; `.worktreeinclude` carried `.secrets.env`
across; `forkbomb-guard` denied from inside. A session that enters a
worktree later is documented rather than run, so `recompact` takes the
project from the payload's `cwd` and a test case runs every hook with the
two disagreeing.

The browser sweep's false positives are known and gone. The `click-stolen`
check — the element under a control's centre is not the control — ran over
eight public sites in three viewports, 24 pages, plus 18 pages of a local
Astro build. The first run reported 12 stolen clicks, every one in one of
three classes: a link wrapped over two lines, a screen-reader-only skip
link, a link cut off by a cell with overflow hidden. `sweep.mjs` now
probes the first line box, skips clipped controls and clips the box to the
visible part; the rerun reports none, and a fixture page with a real theft
pins that it still catches one. That measured the false positives, not the
misses: a stolen click stays a candidate to confirm by eye.

## The measurements

Compared: SkillForge 1.8.2 as deployed in the ShipPulse project, against
Keel 1.8.0. Token figures are estimates at ~4 characters per token and are
marked as such; everything else is an exact count, printed by
`test/metrics.sh` and pinned by the test suite.

| | SkillForge 1.8.2 | Keel 1.8.0 | Delta |
|---|---|---|---|
| Always-loaded contract | `CLAUDE.md` (80 lines) + `_protocol.md` (247 lines) = 327 lines / 15,245 chars (~3.8k tokens est.) | `CLAUDE.md` = 101 lines / 5,576 chars (~1.4k tokens est.) | 2.7× smaller by characters |
| Kernel code to trust and maintain | 6,316 lines of TS/JS/shell across 17 files — MCP server, embedding pipeline, retrieval eval, sync, update, verify | 4,193 lines of shell across 31 files. Shipped: 2,335 lines across 12 files — the installer, 7 hooks, 4 skill scripts (safe-run launcher, migration sweep, memory graph, code anchors) — plus 158 lines of JavaScript, the `qa-browser` sweep `sweep.mjs`. Maintainer-only: 1,858 lines across 19 files — the archive builder, the test runner, the metrics script and 16 test cases — which never reach a user | 1.5× less; 2.7× counting the shipped part alone |
| Runtime services required | 2 — an MCP server (bun) + an Ollama daemon serving `bge-m3` embeddings | 0 | — |
| Installed footprint | 63 MB / 3,796 files (24 MB of `node_modules` for the MCP server; the remainder is the vector index plus `.tgz` archives the updater made of itself). Clean shipped tree, excluding those: 4.3 MB / 133 files | 380 KB / 62 files | 11.6× smaller than its cleanest measure; 169.8× smaller than what it becomes in a working project |
| Subagents | 8 personas — orchestrator, product, qa, security, devops, research, copy, skill-creator | 2, split by context isolation — `scout` on sonnet (read-only exploration), `verifier` on opus (independent judge) | — |
| Retrieval | embeddings (`bge-m3` via Ollama) + reranker + PageRank over the note-to-note graph | `MEMORY.md` index + `grep` + code anchors (`recall`) | — |
| Retrieval golden set it was built to serve | 6 queries, saturated at recall@5 = 1.0 | n/a | — |
| Ceremony before the first line of code | protocol + `plan.json` + `because[]` citations + approval gate — identical for an architecture rewrite and a padding fix | 0 files for small work; 2 files (brief, report) for big work | — |

The lead shrank again. At 1.3.0 the kernel was 894 lines of shell across 5
files — a 7.1× advantage. 1.4.0 added the migration sweep, the update
check and the memory-graph tool: 1,305 lines across 8 files, 4.8×. 1.5.0
added the code-anchor resolver: 1,460 / 9, 4.3×. 1.6.0 added the kernel
self-tests: 1,701 / 10, 3.7×. 1.7.0 changed no code at all. 1.8.0 added
four hooks, three skills and a test suite split into per-zone cases: 4,193
lines across 31 files, 1.5× — and 2,335 lines across 12 files if only the
part that ships into a project is counted, which is 2.7×. Of the +2,492
lines since 1.7.0, 1,538 are tests and 435 are the four new hooks.

Two things are true at once and both belong here. The lead over the
predecessor keeps shrinking, release after release, and nothing in the
trend suggests it stops on its own. And the kernel now enforces with hooks
what it used to ask for in prose — a secret kept out of a file, a
fabricated verdict refused, the state a compaction dropped handed back —
which is a different kind of line from a line of prose, since the prose
was routinely ignored under pressure. Enforcement is not free: it is code,
and so are the tests that guard it, and code is what this table counts.
The mechanism meant to push the number back down is the quarterly
assumptions review in `OPS.md`: every hook and rule encodes an assumption
about what the model cannot do on its own, and a stale assumption is a
candidate for deletion. SkillForge's 6,316 lines counted its own eval
harness too, so measuring Keel's tests against it is apples to apples. A
comparison that only ever improves is a comparison being managed.

The kernel tests itself. `test/run.sh` runs `test/cases/*.sh`, one file
per zone, over 400 self-tests: every hook (the two newest with a real
captured payload as the fixture), a worktree case that runs all seven with
`cwd` and `CLAUDE_PROJECT_DIR` disagreeing, the installer, bundle
integrity, the shipped scripts, the build, and every number this page
quotes compared against `test/metrics.sh`. Throwaway fixtures, offline,
non-zero exit on any failure. `build-archive.sh` runs them first and
refuses to build the archive if one fails, so a script that fails its own
test never ships. The suite exists because releases kept carrying a real
bug that only careful review caught: `--check` missed the rename
`handleRequest` to `handleRequestV2` because `grep -F` matches a
substring. Five releases in a row also shipped a stale number in the docs,
which is what the metrics case now catches. It is a maintainer tool —
1,858 of the 4,193 lines — and it never lands in a project.

## Knowledge anchored to code

New in 1.5.0: the `recall` skill, code anchors.

Before it, memory grounding worked by symptom — grep `memory/` for words
from the error and hope — and never by location. In a real project memory
of 222 notes, 141 name code files: 494 mentions across 237 unique files,
and none of it was reachable from the code. You could not ask what the
project knows about `apps/web/proxy.ts` before opening the file. An anchor
is a front-matter declaration: the note states which code it is about.

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
front-matter: exact and checkable. MENTIONED — prose mentions ranked by
density: useful, but noisy, and there is no way to check them. Rot
detection is what the anchors are for: rename a symbol or delete a file
and `--check` reports `DEAD_SYMBOL` / `DEAD_FILE`, both verified end to
end. A prose mention can never be checked; that is the difference between
a mention and an anchor.

Code-to-code edges are not built here, deliberately. serena (an LSP,
seeded in `.mcp.json` when the machine has `uvx`) computes callers,
references and call hierarchy exactly and live. Hand-maintained code
structure rots; an LSP does not. The anchors layer carries only what an
LSP cannot know: what the project learned about a place in the code.

The contract's memory rule routes to the skill: read the
`memory/MEMORY.md` index, follow the links that match the task, and
"before changing a file you did not just write, ground by location: skill
`recall`". That routing line is what grew the contract from 79 lines to 81
back in 1.5.0; it stands at 101 today. A skill nobody is routed to is a
skill nobody uses, which is how the predecessor's skill catalog died.

### The note graph

Two different graphs keep getting confused, and at 1.4.0 this document
confused them too, overselling the one that matters less. The note-to-note
graph is memory hygiene; the code-to-knowledge graph above is the one that
helps with code.

The retrieval row in the table is about the scorer, not the graph. The
edges are still where they always were: `[[wikilinks]]` inside
`memory/*.md`. The real 222-note memory carries 919 edges, 0 dead links
and 4 orphans — `graph.sh` prints exactly those figures, and removing the
MCP server changed none of them:

```sh
bash .claude/skills/memory-consolidation/graph.sh           # hubs, dead links, orphans, totals
bash .claude/skills/memory-consolidation/graph.sh --edges   # raw adjacency list
```

Hubs, dead links, orphans: a maintenance report on the notes, useful for
that and for nothing else. It does not help write code and does not claim
to. (`memory/` is plain markdown with `[[wikilinks]]`, so it also opens in
Obsidian or VS Code Foam — that comes with the file format; the kernel adds
nothing to it.)

SkillForge's graph was the same note-to-note graph; it never knew the
code, and it was not a source of truth either. It was rebuilt on every
search from the same `[[wikilinks]]` in the same files
(`retrieval-eval.ts`, `buildLinkGraph`), then fed to personalized PageRank
— "HippoRAG-lite" — as a boost multiplier: `1 + 0.2 * graph` on top of
`0.8 * vector + 0.2 * keyword`, and cached to `.data/wikilink-graph.json`
in its own words "for inspection". A derived artifact, regenerable from
the notes at any moment — and the notes are exactly what Keel kept.

What Keel dropped is that scorer. Its value was never demonstrated: the
whole retrieval stack saturated at recall@5 = 1.0 on a golden set of 6
queries, and at the ceiling credit cannot be attributed to the graph term
or to any other. The links are now walked by the model, per the memory
rule. Whether that is as good as the dropped scorer is not claimed here —
there was nothing to compare against while the eval sat at its ceiling.

## What Keel keeps

Four things earned their place, and they are all that survived:

- Files as the only shared truth: `memory/`, `BACKLOG.md`, `PARKED.md`,
  `OPS.md`, `stages/`. Greppable, diffable, no daemon.
- Hooks that each encode a real incident or a pain that repeated: the
  secret-leak guard and the dev-server forkbomb circuit breaker (Next.js
  with Turbopack fork-bombed a Mac), joined since by the silent update
  check, the post-compaction recovery, the verdict receipt, the loop guard
  and the memory-index guard — seven in all.
- `verifier` as an independent judge. A self-report is a claim, not a
  verdict — the one multi-agent pattern that reliably paid off.
- Skills, lazy-loaded: 40 of them, 9 core and 31 domain, most ported from
  the predecessor and stripped of its machinery. They enter context only
  when used.

And two things Keel adds. `OPS.md`, the duty board: standing
responsibilities with a cadence, each mapped to a skill, in `build` or
`live` mode — which is what makes end-to-end ownership routable instead of
aspirational. The kernel calls you the owner there: the person who grants
access, sets direction and picks the mode. The second addition is code
anchors, the `recall` skill described above.

## What was NOT measured

Stated plainly, because a comparison that hides its gaps is marketing:

- No head-to-head task benchmark was run. Nobody executed a fixed task
  suite under both kernels and compared tokens, wall-clock or success
  rate. Every number in the table above is a structural measurement
  (sizes, counts, lines) or a production incident with a date; none is a
  controlled experiment.
- The token figures are estimates, derived from character counts at ~4
  chars/token, not from a tokenizer.
- The three findings closed by measurement were measured once, on one
  machine, on Claude Code 2.1.87. They say what the harness did that day,
  not what it will do after the next release.
- "Better" here means less to load, less to trust, less to break. It does
  not mean "produces better code" — that claim would need the benchmark
  above, and it has not been run.

What is established: Keel loads 2.7× less contract on every task by
character count, asks you to trust 1.5× less code (2.7× counting only what
ships into a project), requires zero runtime services where SkillForge
required two, and removes the exact component that OOM-killed a live stage
— a component the predecessor's own operating pattern had already told its
agents to avoid.

## Reproducing the numbers

```sh
# every number this page quotes, measured from the tree in one command
bash test/metrics.sh

# always-loaded contract — 327 / 15,245 against 101 / 5,576
wc -lc skillforge-project/.claude/CLAUDE.md skillforge-project/.claude/_protocol.md
wc -lc keel/bundle/.claude/CLAUDE.md

# kernel code — 6,316 / 17 files against 4,193 / 31
find skillforge -name '*.ts' -o -name '*.js' -o -name '*.sh' \
  | grep -v node_modules | xargs cat | wc -l
find keel -name '*.sh' -not -path '*/dist/*' -not -path '*/.claude/worktrees/*' \
  | xargs cat | wc -l

# the shipped part of it alone — 2,335 lines across 12 files
find keel/install.sh keel/bundle/.claude -name '*.sh' | xargs cat | wc -l

# footprint — 63 MB / 3,796 files against 380 KB / 62
du -sh skillforge && find skillforge -type f | wc -l
du -sk keel/bundle && find keel/bundle -type f | wc -l

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
