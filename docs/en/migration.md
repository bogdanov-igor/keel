# Migrating from SkillForge

A project that ran SkillForge carries two different things: the machinery —
the bundle, an MCP server entry pointing into it, persona agents, kernel
skills Keel does not ship — and the state: memory notes, stages, backlog.
The machinery is dead weight, and its MCP entry pointing at a deleted bundle
fails loudly at every session start. The state is the part worth keeping,
and the sweep exists to separate the two without ever confusing them.

## The rules

1. Nothing is deleted. Residue moves to `.keel-migration/<timestamp>/` with
   a `MANIFEST.md` that lists every path and ends in a `## Restore` block
   holding one runnable command per path — run the block to undo the sweep.
   Each command carries its own `mkdir -p`: by the time anyone reads the
   manifest the parent directory is usually gone, and a bare `mv` fails.
2. Project state is never touched: `memory/` notes, `stages/`, `BACKLOG.md`,
   `PARKED.md`, `OPS.md`, `.claude/skills/_user` and your product source.
3. Ambiguity is flagged, not guessed. A script does not get to decide
   whether `prompts/` is yours; it reports and leaves the path alone.

## Steps

**1. Install Keel** over the project as usual:

```sh
cd /path/to/project
shasum -c keel_1.8.0.tgz.sha256 && tar -xzf keel_1.8.0.tgz
bash keel/install.sh
```

The old `.claude` moves to a uniquely named `.claude.bak.<timestamp>`. The
installer carries over every skill you wrote yourself — including ones under
SkillForge's `skills/_user/` — along with your permissions, commands, rules
and output styles, and reports the residue it found without moving any of it.

**2. Preview the sweep.** Read-only, changes nothing:

```sh
bash .claude/skills/migrate/sweep.sh
```

**3. Sweep.** The `migrate` skill carries `disable-model-invocation` because
it moves files: it starts when you ask for it in Claude Code, which is what
the first session after an install does when `install.sh` reported residue.
Or run the script:

```sh
bash .claude/skills/migrate/sweep.sh --apply
```

`--apply` quarantines the machinery, adds `.keel-migration/` to `.gitignore`
and files the re-audit line into `BACKLOG.md` once; a second run finds its
own `src:migrate` line and leaves the backlog alone.

**4. Restart the session** if `.mcp.json` changed: MCP servers are loaded at
startup, so a stale server stays connected until you do.

## What moves, what stays

| Swept to quarantine | Never touched |
|---|---|
| the `skillforge/` bundle and its `.tgz` archives | every note under `memory/` |
| `.claude/_protocol.md`, `.claude/playbooks/` | `stages/` |
| persona agents (orchestrator, product, qa, security, devops, research, copy, skill-creator) | `BACKLOG.md`, `PARKED.md`, `OPS.md` |
| ghost kernel skills (`dreaming`, `memory-eval`, `outcomes`, `sleep-time-consolidation`, `sf-code-review`, `sf-security-review`, `chat-render-enable`, `ops-safe-dev-server`) | `.claude/skills/_user` — your own skills |
| the `memory-residue-check.sh` hook, and `dev-safe.sh` when the file itself names SkillForge | product source |

`.mcp.json` is edited rather than moved: the `skillforge` entry goes, every
other entry stays byte for byte, and the original is copied to
`mcp.json.before` inside the quarantine. With no `python3` to do it, the
manifest asks for that entry by hand; when removing it leaves no servers at
all, the sweep points at `keel/bundle/seed/mcp.json`.

Flagged, reported and never moved: `prompts/`, `.backups/`, `INSTALL.ru.md`,
`INSTALL.en.md`, `LAUNCH-OPS.md`, `memory/signals/`,
`memory/chat-render-active.md`, and old `.claude.bak.*` backups. A backup
with a `VERSION` file inside is Keel's own, left by `install.sh`, and the
report says exactly that — otherwise you open it looking for SkillForge
state that was never there. A report of flagged paths alone raises no banner.

Restoring anything is one line out of the manifest:

```sh
mkdir -p "<parent>" && mv ".keel-migration/<ts>/<path>" "<path>"
```

## Then re-audit

This is what the migration is for, and what SkillForge recorded about itself
is why. Its approval gates and artifact checks were routinely bypassed under
time pressure — its own memory carries that as the `engine-bypass`
antipattern, describing runs that marked units green with no
machine-verifiable artifact. Its memory writes silently failed while the
embedding daemon was degraded, so the record of that period is thinner than
it looks. Work that shipped "green" may never have been verified at all, and
those verdicts should not be inherited. After the sweep:

1. `codebase-map` — re-ground on what is actually in the repo now.
2. `audit` — one scoped audit per surface that matters, findings into
   `BACKLOG.md`. Respect the WIP limit: at 20+ open findings, burn down
   before auditing more.
3. `memory-consolidation` — the memory survived a system change. Repair dead
   `[[wikilinks]]`, fold `signals/` notes into the Keel layout, drop notes
   that only described the predecessor's machinery.

An audit at that scale is a `stage`: brief before, verified report after. I
had the sweep file the line itself, so the step outlives this session:

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
