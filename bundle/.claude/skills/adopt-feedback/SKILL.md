---
name: adopt-feedback
description: Sweep the owner's corrections out of Claude Code's own auto memory into the kernel's files — a rule about how the agent works becomes a backlog item raising it into Keel, a fact becomes project memory, concrete work becomes a backlog line. Run when the owner asks, or periodically, so a correction given once stops having to be given again.
disable-model-invocation: true
argument-hint: "[--dry-run]"
---

# Adopt feedback

Claude Code keeps an auto memory of its own, outside the project: what
the owner corrected, what he prefers, what he had to repeat. The
kernel cannot see any of it — the contract, the skills, and `memory/`
carry none of those corrections. This skill moves them across, once,
into files that are read by design.

Read-only on the auto memory: never write, move, or delete there.

## 1. Locate the directory

`autoMemoryDirectory` in settings, if set. Otherwise
`~/.claude/projects/<project>/memory/`, where `<project>` is the
project's absolute path with every `/` and `.` replaced by `-`
(`/Users/me/app.v2` becomes `-Users-me-app-v2`):

```sh
grep -h autoMemoryDirectory ~/.claude/settings.json .claude/settings.json 2>/dev/null
ls -- "$HOME/.claude/projects/$(pwd -P | tr '/.' '--')/memory/" \
  || ls -d "$HOME/.claude/projects/"*"$(basename "$(pwd -P)")"*/memory/
```

Verify with `ls` before claiming anything. If the directory is not
there, the report says **"auto memory not checked"** — never "no
corrections found". An unread source is not an empty one.

## 2. Read

`MEMORY.md` (the index), then every note whose front-matter carries
`type: feedback` — usually nested, `metadata:` then `type:` — plus
`type: user` for standing preferences. Skip the
rest: project notes belong to the session that wrote them.

## 3. Classify — one destination each

| The correction is | Destination |
|---|---|
| a rule about how the agent works | `BACKLOG.md`: `- [ ] P2 \| kernel \| raise into keel: … \| ev:<auto-memory path> \| src:kernel` |
| a fact about this code or product | skill `remember` — with a `code:` anchor when it names code |
| concrete work he wants done | a normal `BACKLOG.md` line |
| already in the contract or `memory/` | skip, and say it was already covered |

A rule the owner had to give more than once is not a preference — it
is a kernel gap. Say so on its backlog line.

## 4. Report

A table, one row per correction: what he said (short), where it went,
and why. Then the count skipped as already-covered. `--dry-run` prints
that table and writes nothing — the default for a first pass on a
memory nobody has swept before.
