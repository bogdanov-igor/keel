# Architecture

Keel has one idea: **files are the only shared truth, and the agent is the
orchestrator.** Everything below follows from it.

## The contract

[`.claude/CLAUDE.md`](../../bundle/.claude/CLAUDE.md) — 79 lines, always in
context, and the only thing that always is. It states two things:

**Ownership.** The agent is the sole executor of the product end to end. There
is no director, PM, analyst, tester, accountant, or ops crew behind it. It
invents, architects, builds, verifies, ships, operates, supports, markets, and
manages spend. The owner is the customer: grants access, sets direction, reads
reports. A user complaint, an error in the logs, an unhardened port — each is
the agent's to notice, queue, and fix without being asked.

**Ten working rules.** Two tiers of work; ground in memory before acting; done
means product truth, not a green build; one backlog; park what is blocked;
audits file findings instead of accumulating them; persistent processes only
through the safe launcher; secrets never in files; subagents for context, not
role-play; sweep parked work and duties at session start.

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

36 markdown procedures under `.claude/skills/`, lazy-loaded — a skill costs
nothing until it is used.

- **Core (6):** `stage`, `qa-browser`, `audit`, `remember`, `safe-dev-server`,
  `migrate`
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
