# Architecture

Keel has one idea: **files are the only shared truth, and the agent is the
orchestrator.** Everything below follows from it.

## The contract

[`.claude/CLAUDE.md`](../../bundle/.claude/CLAUDE.md) — 81 lines, always in
context, and the only thing that always is. It states two things:

**Ownership.** The agent is the sole executor of the product end to end. There
is no director, PM, analyst, tester, accountant, or ops crew behind it. It
invents, architects, builds, verifies, ships, operates, supports, markets, and
manages spend. The owner is the customer: grants access, sets direction, reads
reports. A user complaint, an error in the logs, an unhardened port — each is
the agent's to notice, queue, and fix without being asked.

**Ten working rules.** Two tiers of work; ground in memory before acting — by
symptom in the index, and by location in the code before changing a file you did
not just write; done means product truth, not a green build; one backlog; park
what is blocked; audits file findings instead of accumulating them; persistent
processes only through the safe launcher; secrets never in files; subagents for
context, not role-play; sweep parked work and duties at session start.

The rest of the kernel is pointers. Procedures live in skills and enter context
only when used.

## The files

```text
memory/       lessons · antipatterns · patterns, indexed by MEMORY.md
BACKLOG.md    the one canonical work queue
PARKED.md     work blocked on the owner, each with a resume plan
OPS.md        standing duties with cadence + operating mode + access registry
stages/       NNN-slug/brief.md + report.md — big work only
```

A conclusion worth surviving the session gets written the moment it exists.
Unwritten insight dies with the context window.

**Memory** is markdown notes plus a strict one-line index. Retrieval is reading
the index and grepping. There is no embedding model, no vector store, no
reranker — see [why-keel](why-keel.md) for what happened when there was.

**`OPS.md`** is the piece that makes ownership routable. Standing duties, each
with a cadence and a skill that executes it, in one of two modes:

- **`build`** — no scheduled token burns. Duties run opportunistically, when
  there is idle capacity.
- **`live`** — the owner's go-live call. The system sets up cron/scheduled runs
  and the full cadence.

## The memory graph — and the one that matters

Two different graphs get called "the memory graph". One of them keeps memory
tidy. The other one is why you keep memory at all.

**Note ↔ note is hygiene.** The edges are the `[[wikilinks]]` inside the
`memory/*.md` notes — they live in the notes, and they always did. `graph.sh`
reads them and reports hubs, dead links, orphans: on a real project memory,
**919 edges** after discounting prose/code false positives, **0 dead links**,
**4 orphans**. No index, no daemon, no build step. That is what it is good for,
and it is not good for anything else — it tells you when memory is fraying, not
what the code does. (`memory/` is markdown with wikilinks, so it also opens in
Obsidian or VS Code Foam. That is a picture, not a tool.)

```sh
# hubs (most-cited notes), dead links, orphans, totals
bash .claude/skills/memory-consolidation/graph.sh

# the raw adjacency list
bash .claude/skills/memory-consolidation/graph.sh --edges
```

What Keel dropped from SkillForge was the **scorer**, not the graph. SkillForge
did not treat its graph as a source of truth either; it *rebuilt* one on every
search, from the same wikilinks in the same files (`buildLinkGraph` in
`retrieval-eval.ts`), ran personalized PageRank over it — "HippoRAG-lite" — as a
boost multiplier, `1 + 0.2 * graph` on top of `0.8 * vector + 0.2 * keyword`,
and cached a copy to `.data/wikilink-graph.json` "for inspection": derived,
regenerable, never the source. The scorer's value was never demonstrated — the
whole retrieval stack saturated at recall@5 = 1.0 on a golden set of 6 queries,
and at the ceiling you cannot attribute credit to the graph term. Who walks the
note graph now is the model: contract rule 2 sends it to the `memory/MEMORY.md`
index and tells it to follow the links that match the task. And that graph was
note-to-note as well. It never knew the code at all.

**Code ↔ knowledge is `recall`, and that is the graph that carries weight.**
Grounding by *symptom* is grep — you have to suspect the failure already to find
the lesson about it. Grounding by *location* is the question you actually have
open: what does this project know about `apps/web/proxy.ts`? Until 1.5.0 that
question had no answer. In a real 222-note project memory, **141 notes name code
files** — 494 mentions across 237 unique files — and none of it was reachable
from the code.

A note now declares the code it is about, in front-matter:

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

`path/to/file.ts#symbol`, or just the file. Two queries:

```sh
# what we know about this code — before you touch it
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts

# anchors that no longer resolve
bash .claude/skills/recall/anchors.sh --check
```

Results come back in two sets. **ANCHORED** — notes that declared this code in
their front-matter: exact, and checkable. **MENTIONED** — notes that merely name
it in prose, ranked by mention density: useful, noisy, and unverifiable — which
is the whole argument for anchoring.

**Rot detection is the point.** Rename a symbol or delete a file and `--check`
reports `DEAD_SYMBOL` / `DEAD_FILE` — the note describes code that no longer
exists, and it says so before you act on it. A prose mention can never be checked
at all. Dead anchors file as P2 findings like anything else.

**Code → code edges are deliberately not built here.** Callers, references,
import trees, call hierarchy — serena (LSP, seeded in `.mcp.json`) computes them
exactly and live: `find_symbol`, `find_referencing_symbols`. A hand-maintained
map of code structure rots on the first refactor, and a rotted map is worse than
no map; an LSP does not rot. So the anchors layer carries only the edge no LSP
can derive: what we *learned* about a place in the code — that this file
fork-bombed a Mac, that this route shipped green and broke in prod.

Contract rule 2 routes to it: *"Before changing a file you did not just write,
ground by location: skill `recall`."* A skill nothing routes to is a skill nobody
uses — which is exactly how the predecessor's catalog died.

## Two tiers of work

| | Small | Big |
|---|---|---|
| **What** | Single surface, short, low risk | Multi-surface, risky, or multi-hour |
| **Protocol** | Do it, verify it, move on | Skill `stage` |
| **Artifacts** | None | `stages/NNN-slug/brief.md` before, `report.md` after |

That is the whole ceremony budget. The predecessor demanded the same ~3.8k
tokens of protocol before the first line of code whether the task was an
architecture rewrite or a padding fix. Ceremony on small work is pure tax.

## Skills

37 markdown procedures under `.claude/skills/`, lazy-loaded — a skill costs
nothing until it is used.

- **Core (7):** `stage`, `qa-browser`, `audit`, `remember`, `recall`,
  `safe-dev-server`, `migrate`
- **Domain (30):** engineering (code/security/architecture/data-model/API/perf/
  test/tech-debt), devops (CI, deploy, observability, dependencies), growth
  (funnel, CRO, SEO, pricing, PMF, positioning, competitors), copy and support.

Skills you write yourself live alongside them and **survive kernel reinstalls**
automatically.

## Subagents

Two, decomposed by **context isolation** — never by job title:

- **`scout`** — read-only exploration. Burns context on a search so the main
  thread does not.
- **`verifier`** — independent judge of done-ness. A self-report is a claim,
  not a verdict; stage-level work is done only when the verifier confirms it.

Role-shaped personas (product, qa, devops, …) are deliberately absent: they
spend more tokens coordinating than working, and they drift — the predecessor
had to police them with a hard 55-line cap and an automated check.

## Hooks

Three, and each has to justify itself by having stopped a real incident:

- **`leak-guard.sh`** (`PreToolUse` on writes) — blocks a write that would put a
  secret value in a file. Secrets are written as `{{secret:KEY}}`; values live
  in `.secrets.env`.
- **`forkbomb-guard.sh`** (`PreToolUse` on Bash) — denies raw launches of
  persistent processes. Next.js + Turbopack fork-bombed a Mac; dev servers now
  go through `safe-dev-server`'s `safe-run` launcher, which has a process-tree
  circuit breaker and whole-group teardown. Thresholds: `keel.json`.
- **`update-check.sh`** (`SessionStart`) — one line when a newer Keel exists,
  silence otherwise.

## What is kernel-owned vs project-owned

```text
.claude/     kernel-owned — reinstalling overwrites it. Never edit in place.
everything   project-owned — the installer creates it once and never touches
else         it again.
```

Kernel changes happen in the keel repo and reach projects by reinstall. Editing
`.claude/` inside a deployed project means your change dies at the next update.
