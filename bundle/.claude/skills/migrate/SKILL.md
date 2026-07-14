---
name: migrate
description: Sweep SkillForge (or derivative) residue out of a project that Keel now runs — quarantine the predecessor's machinery, never its state, then re-audit because the kernel changed underneath the codebase. Use on first session after installing Keel over an older system, or whenever install.sh reports residue.
---

# Migrate

A project that ran SkillForge carries its machinery: the `skillforge/`
bundle, an MCP server entry pointing at it, persona agents, kernel skills
Keel does not ship, a protocol file. None of it is load-bearing now, and a
stale MCP entry pointing at a deleted bundle fails loudly at session start.

The predecessor's *state*, though, is the valuable part — memory notes,
stages, backlog — and it stays exactly where it is.

## The line

| Swept to quarantine | Never touched |
|---|---|
| `skillforge/` bundle, its `.tgz` archives | `memory/` notes (all of them) |
| `skillforge` entry in `.mcp.json` | `stages/` |
| `_protocol.md`, `playbooks/` | `BACKLOG.md`, `PARKED.md`, `OPS.md` |
| persona agents, ghost kernel skills | `.claude/skills/_user` (project-owned skills) |
| `memory-residue-check.sh` hook | product source |

Ambiguous paths (`prompts/`, `.backups/`, `memory/signals/`, old install
docs) are **flagged and left in place**. The owner decides; a script does
not get to guess about someone's files.

Nothing is deleted. Everything swept lands in `.keel-migration/<ts>/` with a
`MANIFEST.md` that lists each path and the `mv` that restores it.

## Procedure

1. Detect first, always. Read the report before changing anything:

   ```sh
   bash .claude/skills/migrate/sweep.sh
   ```

2. Show the owner what will move and what is flagged. If anything in the
   MACHINERY list looks project-owned to you, stop and ask — a false
   positive there is the one way this skill can hurt.

3. Sweep:

   ```sh
   bash .claude/skills/migrate/sweep.sh --apply
   ```

4. Restart the session if `.mcp.json` changed — MCP servers are loaded at
   startup, so the stale server stays connected until then.

## Then re-audit — this is the point

The kernel changed underneath a codebase that was built under different
rules. The predecessor's gates (approval, `because[]` citations, artifact
checks) were routinely bypassed under time pressure — that is recorded in
its own memory as the `engine-bypass` antipattern — so work that shipped
"green" may never have been verified at all.

Do not assume the previous system's verdicts still hold. Propose to the
owner, and on agreement run:

1. `codebase-map` — re-ground on what is actually here now.
2. `audit` — one scoped audit per surface that matters, findings into
   `BACKLOG.md`. Respect the WIP limit: 20+ open findings means burn down
   first.
3. `memory-consolidation` — the memory survived a system change: repair dead
   `[[wikilinks]]`, fold `signals/` notes into the Keel layout, drop notes
   that only described the predecessor's machinery.

`sweep.sh --apply` files the re-audit into `BACKLOG.md` itself, so it survives
the session without depending on anyone remembering:

```text
- [ ] P1 | kernel | Re-audit after Keel migration: codebase-map + scoped audits + memory consolidation | ev:.keel-migration/<ts>/MANIFEST.md | src:migrate
```

Do not file a second one. Confirm it is there, and start it when the owner
agrees.

## Report

State three things: what was swept (with the manifest path), what was
flagged for the owner, and what the re-audit will cover — plus what it will
not.
