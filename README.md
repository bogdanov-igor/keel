<p align="center">
  <img src="docs/assets/banner.svg?v=1.8" alt="Keel — minimal load-bearing kernel for Claude Code" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.8.0-4a9fd8?style=flat-square" alt="version 1.8.0">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square" alt="Apache-2.0">
  <img src="https://img.shields.io/badge/kernel-380%20KB%20%C2%B7%2062%20files-success?style=flat-square" alt="380 KB, 62 files">
  <img src="https://img.shields.io/badge/skills-40-success?style=flat-square" alt="40 skills">
  <img src="https://img.shields.io/badge/runtime%20services-0-success?style=flat-square" alt="zero runtime services">
  <img src="https://img.shields.io/badge/contract-101%20lines-success?style=flat-square" alt="101-line contract">
</p>

<p align="center">
  <b>English</b> · <a href="README.ru.md">Русский</a>
</p>

---

Keel is a minimal kernel for [Claude Code](https://claude.com/claude-code)
projects. It sets the agent up as the sole executor of a product end to end:
invention, architecture, code, QA, deploy, infrastructure, security, market,
support, spend. Everything beyond that is deliberately left out.

[Loft](https://github.com/bogdanov-igor/loft) is my other kernel — the same
plumbing pointed at an analyst's document work: specs, a wiki mirrored from
Confluence, corpus audits. The two trade parts: 1.8.0 took loft's rewritten
leak-guard parser, and the limit on open audit findings and the rule about
claiming work before starting it are proposed back to loft.

Keel is the successor to SkillForge, which I rebuilt in July 2026 after
auditing what in it actually helped and what was dead weight. SkillForge
shipped its own MCP server, a vector index, a reranker and eight agent
personas, while its own documented best practice told agents to bypass all of
that and grep the files directly. Keel keeps the bypass and drops the
machinery. The comparison with numbers is in [why-keel](docs/en/why-keel.md):
the always-on contract is 2.7× smaller by characters, kernel code 1.5×
smaller (2.7× counting only what ships into a project), zero runtime services
where the predecessor ran two, and the component that once OOM-killed a live
production stage is gone.

## Quickstart

**1.** Download `keel_1.8.0.tgz` and `keel_1.8.0.tgz.sha256` from
[Releases](https://github.com/bogdanov-igor/keel/releases/latest) into your
project folder.

**2.** Open the project in Claude Code and say:

> Install keel from the archive in this folder: verify the sha256, unpack it,
> run `keel/install.sh`, then tell me what it set up.

**3.** If the project ran SkillForge — or any system before this one — add:

> Clean up the leftovers from the old system and propose the re-audit.

### Or do it yourself

```sh
cd /path/to/project                    # tgz + .sha256 copied here
shasum -c keel_1.8.0.tgz.sha256        # integrity first: expect "OK"
tar -xzf keel_1.8.0.tgz
bash keel/install.sh                   # no argument = install right here
```

From the source repo instead: `bash install.sh /path/to/project`.

Updating is the same command: get the newer keel, re-run `install.sh`. Kernel
files are replaced, project state is never touched, and your own skills,
permissions, slash commands and rules are carried over; the installer
self-checks what it wrote and rolls back if that check fails. When a newer
keel exists, a hook prints one line at session start, once a day.

Dependencies, all optional: `node` and Playwright for browser QA
(`npx playwright install chromium`), `uvx` for the seeded serena MCP server,
`npx` for context7 — the installer seeds only servers whose launcher is
already on the machine. `python3` too: the hooks read their JSON payload with
`jq` when it is there and `python3` otherwise; with neither, `leak-guard`
scans the raw payload and the deny hooks let the call through — without one
of the two they do not guard.

## Rules that stopped being prose

The headline change in 1.8.0. A rule in the contract is a sentence the model
can skip, and the ones that got skipped were skipped under pressure. Four of
them now have a hook behind them, and each hook cost one loss to learn.

`recompact` covers the compaction, the documented moment a long session goes
blind: afterwards it reads the disk and hands back the active stage's goal,
the claimed items in `BACKLOG.md` and the gates still owed. `verdict-guard`
refuses an `N pass / M fail` line in a stage report that carries no agent id;
a verdict typed in by hand before the verifier ran happened once in
production and read as real. `loop-guard` puts the two-attempts rule into
context on the third failure of one command with the same first error line,
while the model is tunnel-visioned; it never blocks, and it counts its own
firings. `index-guard` speaks when `memory/MEMORY.md` passes 250 lines or one
line passes 300 characters — the predecessor's index bloated until nobody
read it.

Three assumptions the kernel had carried were measured on Claude Code 2.1.87
and closed. The contract survives compaction: with a `PreCompact` hook
rewriting `.claude/CLAUDE.md` on disk mid-compaction, the next turn answered
from the rewritten text, so the file stays where it is. Hooks work inside a
worktree: `CLAUDE_PROJECT_DIR` is the worktree, its own `settings.json` is
read, `.worktreeinclude` carried `.secrets.env`, `forkbomb-guard` denied from
inside. And the browser sweep, which now ships as a file instead of a code
block to copy, has an honest hit-test: over eight public sites in three
viewports plus a local build it reported twelve stolen clicks, every one a
wrapped link, a skip link for screen readers or a link clipped by its cell —
the rerun reports none, and a fixture page pins a real theft.

Three skills arrived as well: `integrations`, `adopt-feedback`,
`design-port`. Full list in the [changelog](CHANGELOG.md); what binds future
releases, including what was rejected, in the [roadmap](ROADMAP.md).

## What's inside

- The contract, [`.claude/CLAUDE.md`](bundle/.claude/CLAUDE.md): 101 lines,
  the only thing always in context — ownership, the files that hold the
  truth, eleven working rules. Everything else loads when used.
- 40 lazily loaded skills, in context only while they run.

  Core, the ones the contract routes to by name:
  - `stage` — big work in two files: a brief with done criteria and a premortem, a verified report.
  - `qa-browser` — the browser pass: programmatic checks, real flows, screenshots against the baseline.
  - `audit` — one surface at a time, findings ranked P0-P3 into `BACKLOG.md`, and what was not covered.
  - `remember` — file a lesson, antipattern or pattern with one index line, anchored to its code.
  - `recall` — what the project already learned about this file or symbol, and which anchors went dead.
  - `safe-dev-server` — the sanctioned way to start a dev server, watcher or preview.
  - `migrate` — quarantine a predecessor's machinery, with a restore command per path.
  - `integrations` — detect what this project can reach, ask about each, record it in `OPS.md`.
  - `adopt-feedback` — sweep your corrections out of Claude Code's auto memory into the project's files.

  Engineering and quality:
  - `code-audit` — a diff or file set read for correctness, safety, performance, style; one fix per finding.
  - `architecture-review` — layer separation, coupling and scalability risk against the stated goals.
  - `api-contract-audit` — routes against their declared contract: validation, shapes, error codes, auth.
  - `data-model-review` — schema and migrations: missing keys, index gaps, tenant isolation.
  - `security-audit` — secrets, injection, auth gaps, XSS and CORS over a file set or a diff.
  - `test-authoring` — tests for a file or a function: happy path, edges, error states, coverage delta.
  - `e2e-playwright-cli` — scripted browser checks through the Playwright CLI, results to disk under `.qa/`.
  - `site-sweep` — every route, viewport and theme crawled, then each page graded against launch.
  - `design-port` — a Claude Design canvas ported into the product and checked by rendering it.
  - `tech-debt-audit` — TODO density, stubs, dead exports and oversized files, as a paydown list.

  DevOps and infrastructure:
  - `ci-pipeline-setup` — lint, test, build, scan and deploy stages with caching and branch rules.
  - `deploy-audit` — deploy configs: missing env vars, absent health checks, no rollback, drift.
  - `observability-setup` — structured logs, error tracking, metrics and alerts for a live service.
  - `performance-profiling` — CPU hotspots, leaks, slow queries and N+1, each finding with evidence.
  - `dependency-vuln-audit` — known CVEs and stale packages as a prioritized remediation list.
  - `rls-tenant-isolation` — a Supabase path moved off the service-role client onto enforced RLS.
  - `incident-postmortem` — a blameless timeline: root cause, contributing factors, graded actions.

  Growth, market and copy:
  - `growth-funnel-audit` — onboarding, activation and retention traced in the code and in the events.
  - `conversion-cro-audit` — landing, signup and first run read for what kills a conversion.
  - `seo-audit` — metadata, robots, sitemap, headings and Core Web Vitals on public routes.
  - `messaging-copy-audit` — claim drift across landing, pricing and docs, and what cannot be backed.
  - `pricing-packaging-audit` — every price and limit in code, copy and config against one source.
  - `competitor-analysis` — competitor profiles with sources: pricing, ICP, features, moat claims.
  - `market-positioning-analysis` — ICP fit, differentiation and gaps from sourced competitor data.
  - `support-playbook` — issue categories, a triage tree, escalation paths and macros from the docs.
  - `customer-reply-draft` — a reply grounded in the docs and the playbook, inventing no capability.

  Research and product:
  - `discovery-signals` — evidence before big work: competitors, complaints, metrics, errors, trends.
  - `product-pmf-eval` — each module classed core, supporting, nice-to-have or balloon-ware.
  - `codebase-map` — entry points, modules, framework and config of an unfamiliar repo, from grep alone.
  - `memory-consolidation` — proposes, never applies: merges, promotions, link repairs, index trims.
  - `visual-memory` — a screenshot or a PDF page turned into a note that grep can find later.
- Two subagents, split by context isolation: `scout` on sonnet, read-only,
  returning the files it opened whole apart from those it only excerpted;
  `verifier` on opus with `qa-browser` preloaded, judging finished work. Each
  runs on the model its front-matter names, not the session's.
- Seven hooks, one incident behind each. `leak-guard` blocks a write that
  would put a value from `.secrets.env` into a file; `forkbomb-guard` denies
  a raw dev-server launch, after Next.js with Turbopack fork-bombed a Mac;
  `verdict-guard` refuses a hand-written verifier verdict; `recompact` hands
  a compacted session its state back; `loop-guard` says the two-attempts rule
  on the third identical failure; `index-guard` says when the memory index
  has outgrown its job; `update-check` prints one line when a newer keel exists,
  and nothing the rest of the time.
- File memory anchored to the code: notes under `memory/` with a strict
  one-line-per-note index, plus code anchors that make a lesson reachable
  from the file it is about (the `recall` skill). `BACKLOG.md` is the single
  work queue; `PARKED.md` holds what is blocked on you, with a resume plan.
- `OPS.md`, a duty board: standing responsibilities, each with a cadence and
  the skill that runs it — triage feedback daily, sweep security weekly,
  check that pricing still agrees with itself monthly. Two modes. `build`
  is the default: the product is not in front of users yet, nothing is
  scheduled, duties run when a session is open and idle. `live` starts on
  your go-live call and the cadence becomes real — you pick how it runs,
  from `/loop` in an open session to cron with `claude -p` or a GitHub
  Action. The kernel schedules nothing by itself.
- A bridge to Claude Code's own auto memory, machine-local and outside the
  repository: `adopt-feedback` sweeps your corrections out of it into
  `memory/` and `BACKLOG.md` monthly, so a correction you had to give twice
  becomes a kernel change instead of a note on one laptop.
- Worktree isolation for parallel work: units run as `claude --worktree`,
  where the harness blocks edits to the main checkout, and the seeded
  `.worktreeinclude` carries `.secrets.env` into the fresh checkout.
- `qa-baseline/`: the screenshots a browser pass compares against are tracked
  files, changed only on a verifier pass or your own decision.

## What it leaves out

- No MCP server of its own, no vector index, no embeddings, no reranker. The
  installer seeds external servers it finds a launcher for (serena,
  context7); the kernel runs none. A few hundred markdown notes are found by
  reading an index and grepping. The predecessor's own eval saturated at
  recall@5 = 1.0 on a golden set of six queries, and its embedding daemon
  once OOM-killed a live stage, losing three subagents' work.
- No agent personas: role-shaped subagents spend more tokens coordinating
  than working.
- No per-task ceremony: no runs log, no hypothesis citations, no file locks,
  no sha256 sidecars. Small work leaves no files behind; big work leaves two,
  a brief and a verified report.
- No updater or patch system: distribution is copying the folder.

## Memory anchored to the code

Notes in `memory/` used to be reachable only by symptom: grep the error text
and hope a note matches. In a real project memory of 222 notes, 141 name code
files — 494 mentions across 237 unique files — and none of it was reachable
from `apps/web/proxy.ts` before you opened the file.

The `recall` skill adds that direction. A note declares the code it is about
in its front-matter, and two queries follow — no index, daemon or build step:

```yaml
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
```

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
bash .claude/skills/recall/anchors.sh --check             # dead anchors
```

Results come in two sets. ANCHORED lists the notes that declared this code:
exact and checkable. MENTIONED lists notes that only name it in prose, ranked
by density: useful, noisy, impossible to verify. `--backfill` anchors notes
you already have, resolving each prose mention against the real tree and
anchoring only the ones that land on exactly one file. Anchors exist for rot
detection: rename a symbol or delete a file and `--check` reports
`DEAD_SYMBOL` / `DEAD_FILE`, both verified end to end. A prose mention can
never be checked this way. More detail in
[architecture](docs/en/architecture.md).

## Tests

`test/run.sh` runs the kernel's self-tests from `test/cases/`, one file per
zone: over 400 of them across the seven hooks, the installer, bundle
integrity — front-matter, hook paths, skill references, agent models — the
shipped scripts `anchors.sh`, `graph.sh`, `sweep.sh`, and the build. Plain
bash, offline, throwaway fixtures. Two cases do more than test a script.
`test/metrics.sh` measures every number this documentation quotes and a case
compares them with the tree, because five releases in a row shipped a stale
one; a claim reworded out of its regex fails loudly rather than passing
unnoticed. And a fixture page with a real stolen click is the positive
control for the browser sweep, run wherever Playwright is installed.
`build-archive.sh` runs the suite before packaging and refuses to cut a
release if anything fails. A maintainer tool: it does not install into a
project.

## Layout in a deployed project

```text
.claude/          kernel (kernel-owned: reinstalling overwrites it)
memory/           project memory: MEMORY.md index + lessons/antipatterns/patterns
stages/           big-work artifacts: NNN-slug/brief.md + report.md
BACKLOG.md        the one canonical work queue
PARKED.md         work blocked on you, each item with a resume plan
OPS.md            standing duties + operating mode (build/live) + access registry
keel.json         circuit-breaker thresholds, update-check settings
.mcp.json         external MCP servers (serena + context7, when their launchers exist)
.worktreeinclude  what follows a session into claude --worktree
```

`qa-baseline/` appears with the first browser pass that records a reference.
[CHANGELOG.md](CHANGELOG.md) and [ROADMAP.md](ROADMAP.md) stay in the keel
repo and never install into a project.

## Coming from SkillForge?

Install Keel, then ask for the `migrate` skill — it never runs on its own. It
moves the predecessor's machinery (bundle, MCP entry, persona agents, ghost
skills) into a timestamped `.keel-migration/` folder with a restore command
per path. Nothing is deleted; memory, stages, backlog and your own skills are
never touched, and anything ambiguous is flagged for you to decide. It ends
by proposing a re-audit. Details in the
[migration guide](docs/en/migration.md).

## Documentation

| | English | Русский |
|---|---|---|
| Install & update | [install](docs/en/install.md) | [установка](docs/ru/install.md) |
| Architecture | [architecture](docs/en/architecture.md) | [архитектура](docs/ru/architecture.md) |
| Migrating from SkillForge | [migration](docs/en/migration.md) | [миграция](docs/ru/migration.md) |
| What changed, measured | [why-keel](docs/en/why-keel.md) | [почему keel](docs/ru/why-keel.md) |
| Decisions that bind releases | [roadmap](ROADMAP.md) | [roadmap](ROADMAP.md) |

## Licence

[Apache-2.0](LICENSE) © 2026 **Igor Bogdanov** · <bogdanov.ig.alex@gmail.com>

Free to use, fork and build on, commercially included. Keep the attribution
and note what you changed.
