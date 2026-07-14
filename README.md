<p align="center">
  <img src="docs/assets/banner.svg" alt="Keel — minimal load-bearing kernel for Claude Code" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.3.0-4a9fd8?style=flat-square" alt="version 1.3.0">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square" alt="Apache-2.0">
  <img src="https://img.shields.io/badge/kernel-264%20KB%20%C2%B7%2048%20files-success?style=flat-square" alt="264 KB, 48 files">
  <img src="https://img.shields.io/badge/runtime%20services-0-success?style=flat-square" alt="zero runtime services">
  <img src="https://img.shields.io/badge/contract-79%20lines-success?style=flat-square" alt="79-line contract">
</p>

<p align="center">
  <b>English</b> · <a href="README.ru.md">Русский</a>
</p>

---

**Keel** is a minimal, load-bearing kernel for [Claude Code](https://claude.com/claude-code)
projects. It makes the agent the sole executor of a product end to end —
invention, architecture, code, QA, deploy, infrastructure, security, market,
support, spend — and adds nothing else.

It is the successor to SkillForge, rebuilt in July 2026 after auditing what
actually helped and what was dead weight. The audit's verdict, in one line:
**the machinery outweighed the work.** SkillForge shipped an MCP server, a
vector index, a reranker and eight agent personas — and its own best shipping
practice told agents to bypass all of it and `grep` the files instead. Keel is
that bypass, promoted to the design.

→ [**What changed, measured**](docs/en/why-keel.md) — the honest comparison:
3.7× smaller always-on contract, 7.1× less kernel code, zero runtime services
where its predecessor needed two, and the component that OOM-killed a live
production stage, deleted.

## Install

```sh
cd /path/to/project                    # tgz + .sha256 copied here
shasum -c keel_1.3.0.tgz.sha256        # integrity first: expect "OK"
tar -xzf keel_1.3.0.tgz
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
  79 lines. Everything else loads only when used.
- **36 lazy-loaded skills** — 6 core (`stage`, `qa-browser`, `audit`,
  `remember`, `safe-dev-server`, `migrate`) plus 30 domain skills across
  engineering, devops, growth, copy and research.
- **`OPS.md`, the duty board** — standing responsibilities with a cadence, each
  mapped to a skill. Two modes: `build` (no scheduled token burns) and `live`
  (the owner's go-live call: cron, full cadence). This is what makes end-to-end
  ownership routable instead of aspirational.
- **2 subagents** — `scout` (read-only exploration) and `verifier` (independent
  judge). Decomposed by context isolation, not by job title.
- **3 hooks** — a secret-leak guard, a dev-server forkbomb circuit breaker
  (both earned their place by stopping real incidents), and a silent
  update check.
- **File memory** — `memory/` notes with a strict one-line index, `BACKLOG.md`
  as the single work queue, `PARKED.md` so owner-blocked work parks instead of
  rotting.

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
