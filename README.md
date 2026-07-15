<p align="center">
  <img src="docs/assets/banner.svg" alt="Keel — minimal load-bearing kernel for Claude Code" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.7.0-4a9fd8?style=flat-square" alt="version 1.7.0">
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

Keel is a minimal kernel for [Claude Code](https://claude.com/claude-code)
projects. It sets the agent up as the sole executor of a product end to end:
invention, architecture, code, QA, deploy, infrastructure, security, market,
support, spend. Everything beyond that is deliberately left out.

[Loft](https://github.com/bogdanov-igor/loft) is my other kernel: the same
approach applied to an analyst's document work — specs, a wiki mirrored from
Confluence, corpus audits.

Keel is the successor to SkillForge, which I rebuilt in July 2026 after
auditing what in it actually helped and what was dead weight. SkillForge
shipped its own MCP server, a vector index, a reranker and eight agent
personas, while its own documented best practice told agents to bypass all of
that and grep the files directly. Keel keeps the bypass and drops the
machinery. The comparison with numbers is in
[why-keel](docs/en/why-keel.md): the always-on contract is 3.6× smaller,
kernel code 3.7× smaller, zero runtime services where the predecessor ran
two, and the component that once OOM-killed a live production stage is gone.

## Quickstart

**1.** Download `keel_1.7.0.tgz` and `keel_1.7.0.tgz.sha256` from
[Releases](https://github.com/bogdanov-igor/keel/releases/latest) into your
project folder.

**2.** Open the project in Claude Code and say:

> Install keel from the archive in this folder: verify the sha256, unpack it,
> run `keel/install.sh`, then tell me what it set up.

**3.** If the project ran SkillForge — or any system before this one — add:

> Clean up the leftovers from the old system and propose the re-audit.

Claude verifies the checksum, unpacks, installs and reports. The cleanup step
quarantines the predecessor's machinery without deleting anything and files a
re-audit into `BACKLOG.md`.

### Or do it yourself

```sh
cd /path/to/project                    # tgz + .sha256 copied here
shasum -c keel_1.7.0.tgz.sha256        # integrity first: expect "OK"
tar -xzf keel_1.7.0.tgz
bash keel/install.sh                   # no argument = install right here
```

From the source repo instead: `bash install.sh /path/to/project`.

Updating is the same command: get the newer keel, re-run `install.sh`. Kernel
files are replaced, project state is never touched, and skills you wrote
yourself are carried over. When a newer keel exists, a hook prints one line
at session start, once a day; when you are current it prints nothing.

The only optional dependency is Playwright, used for browser QA
(`npx playwright install chromium`).

## What's inside

- The contract, [`.claude/CLAUDE.md`](bundle/.claude/CLAUDE.md): 81 lines,
  the only thing that is always in context. Everything else loads when used.
- 37 lazily loaded skills: 7 core (`stage`, `qa-browser`, `audit`,
  `remember`, `recall`, `safe-dev-server`, `migrate`) plus 30 domain skills
  across engineering, devops, growth, copy and research.
- `OPS.md`, the duty board: standing responsibilities with a cadence, each
  mapped to a skill. Two modes — `build` (no scheduled token burns) and
  `live` (the owner's go-live call: cron, full cadence). The board is what
  ties end-to-end ownership to concrete scheduled work.
- Two subagents: `scout` for read-only exploration, `verifier` as an
  independent judge of finished work. The split is about context isolation,
  not job titles.
- Three hooks: a secret-leak guard, a circuit breaker against dev-server
  forkbombs — both are in the kernel because they stopped real incidents —
  and a silent update check.
- File memory anchored to the code: notes under `memory/` with a strict
  one-line-per-note index, plus code anchors that make a lesson reachable
  from the file it is about (the `recall` skill). `BACKLOG.md` is the single
  work queue; `PARKED.md` holds owner-blocked items, each with a resume plan.

## What it leaves out

- No MCP server of its own, no vector index, no embeddings, no reranker. A
  few hundred markdown notes are found by reading an index and grepping. The
  predecessor's own eval saturated at recall@5 = 1.0 on a golden set of six
  queries, and its embedding daemon once OOM-killed a live stage mid-fan-out,
  losing the work of three subagents.
- No agent personas: role-shaped subagents spend more tokens coordinating
  than working.
- No per-task ceremony: no runs log, no hypothesis citations, no file locks,
  no sha256 sidecars. Small work leaves no files behind; big work leaves two,
  a brief and a verified report.
- No updater or patch system: distribution is copying the folder.

## Memory anchored to the code

Notes in `memory/` used to be reachable only by symptom: grep for the error
text and hope a note matches. There was no way to go the other direction,
from a file to what the project had already learned about it. In a real
project memory of 222 notes, 141 notes name code files — 494 mentions, 237
unique files — and none of that was reachable from the code side. You could
not ask what the project knows about `apps/web/proxy.ts` before opening it.

The `recall` skill adds that direction. A note declares the code it is about
in its front-matter:

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

Two queries, with no index, daemon or build step behind them:

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
bash .claude/skills/recall/anchors.sh --check             # dead anchors
```

Results come in two sets. ANCHORED lists the notes that declared this code:
exact and checkable. MENTIONED lists the notes that only name it in prose,
ranked by mention density: useful, but noisy and impossible to verify.

`--backfill` anchors notes you already have. It resolves each prose mention
in a note against the real tree and anchors only the ones that land on
exactly one file — a note naming `apps/web/proxy.ts` becomes
`shippulse/apps/web/proxy.ts` when the monorepo keeps the app a level down.
Ambiguous and unresolvable names are reported, never guessed: a guessed path
is just a dead anchor. It runs dry by default; `--apply` writes the
front-matter and skips any note that already declares its code.

Anchors exist for rot detection. Rename a symbol or delete a file and
`--check` reports `DEAD_SYMBOL` / `DEAD_FILE` — the note no longer matches
the code. Both cases are verified end to end. A prose mention can never be
checked this way.

Code-to-code edges are not built here. Callers, references and the call
hierarchy are computed exactly and live by serena (LSP, already seeded in
`.mcp.json`): `find_symbol`, `find_referencing_symbols`. Hand-maintained
code structure rots; an LSP does not. The anchor layer carries only what an
LSP cannot know: what we learned about a place in the code. Contract rule 2
routes to it — before changing a file you did not just write, ground by
location — and that routing is why the contract grew from 79 lines to 81.

Note-to-note links are memory hygiene:
`bash .claude/skills/memory-consolidation/graph.sh` reports hubs, dead links
and orphans (919 edges, 0 dead, 4 orphans on that same memory), and nothing
beyond that. `memory/` is plain markdown with `[[wikilinks]]`, so the folder
also opens in Obsidian or VS Code Foam as a graph — a property of the file
format, not a feature of the kernel.

What Keel dropped from SkillForge was not the graph but the PageRank scorer
over it ("HippoRAG-lite", `1 + 0.2 * graph` on top of
`0.8 * vector + 0.2 * keyword`). Its value was never demonstrated: the
retrieval stack saturated at recall@5 = 1.0 on a golden set of six queries,
and at that ceiling no single term can be credited. SkillForge also rebuilt
the graph from the notes on every search rather than treating it as a source
of truth, and its graph was note-to-note as well — it never knew the code.

More detail in [architecture](docs/en/architecture.md).

## Tests

`test/run.sh` runs the kernel's self-tests: plain bash assertions over
`anchors.sh`, `graph.sh`, `sweep.sh` and `update-check.sh`, offline, against
throwaway fixtures. `build-archive.sh` runs the suite before packaging and
refuses to cut a release if anything fails. The suite exists because each of
the last three releases carried a real bug in these scripts that only
adversarial review caught: `--check` missed a
`handleRequest`→`handleRequestV2` rename because `grep -F` matches
substrings, and `MENTIONED` was ranked by matching lines instead of
mentions. Those exact cases are now pinned in the suite. It is a maintainer
tool and does not install into your project.

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

Install Keel, then run the `migrate` skill. It moves the predecessor's
machinery — bundle, MCP entry, persona agents, ghost skills — into a
timestamped `.keel-migration/` folder with a restore manifest. Nothing is
deleted; memory, stages, backlog and skills you wrote yourself are never
touched, and anything ambiguous is flagged for you to decide. The skill ends
by proposing a re-audit, because the kernel changed underneath the codebase.

Details in the [migration guide](docs/en/migration.md).

## Documentation

| | English | Русский |
|---|---|---|
| Install & update | [install](docs/en/install.md) | [установка](docs/ru/install.md) |
| Architecture | [architecture](docs/en/architecture.md) | [архитектура](docs/ru/architecture.md) |
| Migrating from SkillForge | [migration](docs/en/migration.md) | [миграция](docs/ru/migration.md) |
| What changed, measured | [why-keel](docs/en/why-keel.md) | [почему keel](docs/ru/why-keel.md) |

## Licence

[Apache-2.0](LICENSE) © 2026 **Igor Bogdanov** · <bogdanov.ig.alex@gmail.com>

Free to use, fork and build on, commercially included. Keep the attribution
and note what you changed.
