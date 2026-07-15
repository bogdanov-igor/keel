# Migrating from SkillForge

A project that ran SkillForge carries two different things: the machinery
(dead weight, and actively harmful once the bundle is gone) and the state
(memory, stages, backlog — the part worth keeping). Migration sweeps the
first, preserves the second, and is careful never to confuse them.

## The rules

1. Nothing is deleted. Residue is moved to `.keel-migration/<timestamp>/`
   with a `MANIFEST.md` that lists every path and the `mv` that restores it.
2. Project state is never touched: memory notes, stages, backlog, parked
   items, `_user` skills, product source — all yours, all left alone.
3. Ambiguity is flagged, not guessed. A script does not get to decide
   whether `prompts/` is yours; it reports and leaves the path alone.

## Steps

**1. Install Keel** over the project as usual:

```sh
cd /path/to/project
tar -xzf keel_1.7.0.tgz && bash keel/install.sh
```

The installer moves the old `.claude` to `.claude.bak.<timestamp>`, carries
over every skill you wrote yourself (including ones under SkillForge's
`skills/_user/`), and reports the residue it found, without moving anything.

**2. Preview the sweep.** Read-only, changes nothing:

```sh
bash .claude/skills/migrate/sweep.sh
```

**3. Sweep.** In Claude Code, invoke the `migrate` skill, or run it
directly:

```sh
bash .claude/skills/migrate/sweep.sh --apply
```

**4. Restart the session** if `.mcp.json` changed: MCP servers are loaded at
startup, so a stale server stays connected until you do.

## What moves, what stays

| Swept to quarantine | Never touched |
|---|---|
| `skillforge/` bundle and its `.tgz` archives | every note under `memory/` |
| the `skillforge` server entry in `.mcp.json` | `stages/` |
| `.claude/_protocol.md`, `.claude/playbooks/` | `BACKLOG.md`, `PARKED.md`, `OPS.md` |
| persona agents (orchestrator, product, qa, …) | `.claude/skills/_user` — your own skills |
| ghost kernel skills (`dreaming`, `memory-eval`, `outcomes`, `sleep-time-consolidation`, `sf-code-review`, `sf-security-review`, `chat-render-enable`, `ops-safe-dev-server`) | product source |
| the `memory-residue-check.sh` hook | |

Flagged for you to decide — reported, never moved: `prompts/`, `.backups/`,
`INSTALL.*.md`, `LAUNCH-OPS.md`, `memory/signals/`,
`memory/chat-render-active.md`, and old `.claude.bak.*` backups.

Restoring anything is one command:

```sh
mv .keel-migration/<ts>/<path> <path>
```

## Then re-audit

This is what the migration is for. The kernel changed underneath a codebase
that was built under different rules, and that matters more than it sounds,
because of what SkillForge recorded about itself:

- Its approval gates and artifact checks were routinely bypassed under time
  pressure. Its own memory carries this as the `engine-bypass` antipattern,
  describing runs that marked units green with no machine-verifiable
  artifact.
- Its memory writes silently failed while the embedding daemon was degraded,
  so the record of that period is thinner than it looks.

Work that shipped "green" under the old system may never have been verified
at all. Those verdicts should not be inherited. After the sweep, run:

1. `codebase-map` — re-ground on what is actually in the repo now.
2. `audit` — one scoped audit per surface that matters. Findings go to
   `BACKLOG.md`. Respect the WIP limit: at 20+ open findings, burn down
   before auditing more.
3. `memory-consolidation` — the memory survived a system change. Repair dead
   `[[wikilinks]]`, fold `signals/` notes into the Keel layout, and drop
   notes that only described the predecessor's machinery.

The `migrate` skill files the re-audit into `BACKLOG.md` automatically, so
it survives the session:

```text
- [ ] P1 | kernel | Re-audit after Keel migration: codebase-map + scoped audits + memory consolidation | ev:.keel-migration/<ts>/MANIFEST.md | src:migrate
```

## Cleaning up

Once the project has run clean for a while, delete the quarantine and the
old kernel backups:

```sh
rm -rf .keel-migration/ .claude.bak.*
```

Nothing in Keel depends on them.
