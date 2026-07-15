<p align="center">
  <img src="docs/assets/banner.svg" alt="Keel — minimal load-bearing kernel for Claude Code" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.6.0-4a9fd8?style=flat-square" alt="version 1.6.0">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square" alt="Apache-2.0">
  <img src="https://img.shields.io/badge/kernel-312%20KB%20%C2%B7%2054%20files-success?style=flat-square" alt="312 KB, 54 files">
  <img src="https://img.shields.io/badge/skills-37-success?style=flat-square" alt="37 skills">
  <img src="https://img.shields.io/badge/runtime%20services-0-success?style=flat-square" alt="zero runtime services">
  <img src="https://img.shields.io/badge/contract-81%20lines-success?style=flat-square" alt="81-line contract">
</p>

<p align="center">
  <b>English</b> · <a href="README.ru.md">Русский</a>
</p>

---

**Keel** is a minimal, load-bearing kernel for [Claude Code](https://claude.com/claude-code)
projects. It makes the agent the sole executor of a product end to end —
invention, architecture, code, QA, deploy, infrastructure, security, market,
support, spend — and adds nothing else.

Sibling kernel: [**Loft**](https://github.com/bogdanov-igor/loft) — the same
philosophy applied to the analyst's document work (specs, Confluence-mirrored
wikis, corpus audits). The loft stands on the keel.

It is the successor to SkillForge, rebuilt in July 2026 after auditing what
actually helped and what was dead weight. The audit's verdict, in one line:
**the machinery outweighed the work.** SkillForge shipped an MCP server, a
vector index, a reranker and eight agent personas — and its own best shipping
practice told agents to bypass all of it and `grep` the files instead. Keel is
that bypass, promoted to the design.

→ [**What changed, measured**](docs/en/why-keel.md) — the honest comparison:
3.6× smaller always-on contract, 3.7× less kernel code, zero runtime services
where its predecessor needed two, and the component that OOM-killed a live
production stage, deleted.

## Quickstart

**1.** Download `keel_1.6.0.tgz` and `keel_1.6.0.tgz.sha256` from
[Releases](https://github.com/bogdanov-igor/keel/releases/latest) into your project folder.

**2.** Open the project in Claude Code and say:

> Install keel from the archive in this folder: verify the sha256, unpack it,
> run `keel/install.sh`, then tell me what it set up.

**3.** If the project ran SkillForge — or any system before this one — say:

> Clean up the leftovers from the old system and propose the re-audit.

That is the whole installation. Claude verifies the checksum, unpacks, installs,
and reports; the cleanup step quarantines the predecessor's machinery (deleting
nothing) and files a re-audit into `BACKLOG.md`.

### Or do it yourself

```sh
cd /path/to/project                    # tgz + .sha256 copied here
shasum -c keel_1.6.0.tgz.sha256        # integrity first: expect "OK"
tar -xzf keel_1.6.0.tgz
bash keel/install.sh                   # no argument = install right here
```

From the source repo instead: `bash install.sh /path/to/project`.

**Updating is the same command.** Pull the newer keel, re-run `install.sh`:
kernel files are replaced, project state is never touched, and skills you wrote
yourself are carried over automatically. Keel tells you when an update exists —
one line at session start, once a day, silent when you are current.

Only optional dependency: Playwright for browser QA
(`npx playwright install chromium`).

## What it is

- **One always-on contract** — [`.claude/CLAUDE.md`](bundle/.claude/CLAUDE.md),
  81 lines. Everything else loads only when used.
- **37 lazy-loaded skills** — 7 core (`stage`, `qa-browser`, `audit`,
  `remember`, `recall`, `safe-dev-server`, `migrate`) plus 30 domain skills
  across engineering, devops, growth, copy and research.
- **`OPS.md`, the duty board** — standing responsibilities with a cadence, each
  mapped to a skill. Two modes: `build` (no scheduled token burns) and `live`
  (the owner's go-live call: cron, full cadence). This is what makes end-to-end
  ownership routable instead of aspirational.
- **2 subagents** — `scout` (read-only exploration) and `verifier` (independent
  judge). Decomposed by context isolation, not by job title.
- **3 hooks** — a secret-leak guard, a dev-server forkbomb circuit breaker
  (both earned their place by stopping real incidents), and a silent
  update check.
- **File memory, anchored to the code** — `memory/` notes with a strict one-line
  index, plus code anchors that make a lesson reachable *from* the file it is
  about (skill `recall`). `BACKLOG.md` as the single work queue, `PARKED.md` so
  owner-blocked work parks instead of rotting.

## What it deliberately does not have

- **No MCP server of its own, no vector index, no embeddings, no reranker.**
  A few hundred markdown notes are found by reading an index and grepping. The
  predecessor's own eval saturated at recall@5 = 1.0 on a golden set of **six
  queries** — and its embedding daemon OOM-killed a live stage mid-fan-out,
  losing three subagents' work. Zero own infrastructure means zero of that.
- **No agent personas.** Role-shaped subagents spend more tokens coordinating
  than working.
- **No per-task ceremony.** No runs, hypothesis citations, file locks, or
  sha256 sidecars. Small work gets no files; big work gets two — a brief and a
  verified report.
- **No updater or patch system.** Copy the folder. That is the distribution.

## Memory that knows the code

Grounding used to work by **symptom** — grep and hope. You had to already suspect
the failure to find the lesson about it. It never worked by **location**. In a real
222-note project memory, 141 notes name code files — 494 mentions, 237 unique files
— and none of it was reachable *from* the code. You could not ask what the project
already knows about `apps/web/proxy.ts` before opening it.

**`recall` is that missing direction.** A note declares the code it is about, in
front-matter:

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

Two queries — no index, no daemon, no build step:

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
bash .claude/skills/recall/anchors.sh --check             # dead anchors
```

Results come in two sets. **ANCHORED** — notes that declared this code: exact, and
checkable. **MENTIONED** — notes that merely name it in prose, ranked by density:
useful, noisy, and impossible to verify, which is precisely the argument for
anchoring.

**`--backfill` does that anchoring for a note you already have.**
`bash .claude/skills/recall/anchors.sh --backfill` resolves each prose mention in an
existing note against the real tree and anchors only the ones that land on exactly one
file — a note naming `apps/web/proxy.ts` becomes `shippulse/apps/web/proxy.ts` when the
monorepo buries the app a level down. Ambiguous names and unresolvable ones are reported,
never guessed, since a guessed path is just a dead anchor manufactured on the spot. It runs
dry by default; `--apply` writes the front-matter and skips any note that already declares
its code.

**Rot detection is the point.** Rename a symbol or delete a file and `--check`
reports `DEAD_SYMBOL` / `DEAD_FILE` — the code moved, so the note now lies. Both
cases are verified end to end. A prose mention can never be checked at all.

**Code→code edges are not built here.** Callers, references and the call hierarchy
are computed exactly and live by serena (LSP, already seeded in `.mcp.json`):
`find_symbol`, `find_referencing_symbols`. Hand-maintained code structure rots; an
LSP does not. The anchor layer carries only what an LSP cannot know — what we
*learned* about a place in the code. Contract rule 2 routes to it: before changing a
file you did not just write, ground by location. That routing is why the contract grew
from 79 lines to 81 — a skill nobody is routed to is a skill nobody uses, which is
exactly how the predecessor's skill catalogue died.

Note-to-note links remain what they always were — memory hygiene:
`bash .claude/skills/memory-consolidation/graph.sh` reports hubs, dead links and
orphans (919 edges, 0 dead, 4 orphans on that same memory), and nothing beyond
that. (`memory/` is plain markdown with `[[wikilinks]]`, so it also opens in
Obsidian or VS Code Foam as a graph — a property of the file format, not a
feature of the kernel.)

What Keel dropped from SkillForge was never the graph but the **PageRank scorer**
over it ("HippoRAG-lite", `1 + 0.2 * graph` on top of `0.8 * vector + 0.2 * keyword`) —
whose value was never demonstrated: the retrieval stack saturated at recall@5 = 1.0
on a golden set of six queries, and at the ceiling you cannot credit the graph term,
or any other. SkillForge rebuilt that graph from the notes on every search and never
treated it as a source of truth; and it was note-to-note as well — it never knew the
code at all.

→ [Architecture](docs/en/architecture.md) for the detail.

## Tested

The kernel's shell scripts carry a self-test suite — `test/run.sh`, plain bash assertions
over `anchors.sh`, `graph.sh`, `sweep.sh` and `update-check.sh`, run offline against
throwaway fixtures. `build-archive.sh` runs it first and refuses to cut a release if
anything fails, so a script that flunks its own test never ships. It exists because the
last three releases each carried a real bug in these scripts that only adversarial review
caught — `--check` missing a `handleRequest`→`handleRequestV2` rename because `grep -F`
matches substrings, `MENTIONED` ranked by matching lines instead of mentions — and the
suite pins exactly those cases so they cannot come back. It is a maintainer tool, not
something that installs into your project.

## Layout in a deployed project

```text
.claude/    kernel (kernel-owned: reinstalling overwrites it)
memory/     project memory: MEMORY.md index + lessons/antipatterns/patterns
stages/     big-work artifacts: NNN-slug/brief.md + report.md
BACKLOG.md  the one canonical work queue
PARKED.md   owner-blocked items, each with a resume plan
OPS.md      standing duties + operating mode (build/live) + access registry
keel.json   circuit-breaker thresholds, update-check settings
.mcp.json   external MCP servers (serena + context7 seeded)
```

## Coming from SkillForge?

Install Keel, then run the **`migrate`** skill. It quarantines the
predecessor's machinery — bundle, MCP entry, persona agents, ghost skills — into
a timestamped `.keel-migration/` folder with a restore manifest, **never
deletes anything**, never touches your memory, stages, backlog or your own
skills, and flags anything ambiguous for you to decide. Then it proposes a
re-audit — because the kernel changed underneath a codebase whose old gates
were, by its own records, routinely bypassed.

→ [Migration guide](docs/en/migration.md)

## Documentation

| | English | Русский |
|---|---|---|
| Install & update | [install](docs/en/install.md) | [установка](docs/ru/install.md) |
| Architecture | [architecture](docs/en/architecture.md) | [архитектура](docs/ru/architecture.md) |
| Migrating from SkillForge | [migration](docs/en/migration.md) | [миграция](docs/ru/migration.md) |
| What changed, measured | [why-keel](docs/en/why-keel.md) | [почему keel](docs/ru/why-keel.md) |

## Licence

[Apache-2.0](LICENSE) © 2026 **Igor Bogdanov** · <bogdanov.ig.alex@gmail.com>

Free to use, fork and build on — commercially included. Keep the attribution
and state what you changed.
