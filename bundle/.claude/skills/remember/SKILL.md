---
name: remember
description: Write a lesson, antipattern, or pattern into project memory with a strict one-line index entry. Use after work that taught something non-obvious; skip for anything the code or git history already records.
---

# Remember

## What qualifies

A trap that will bite again, a constraint invisible in the code, a
decision with a non-obvious why, a verified fix for a recurring class
of bug. Does not qualify: what the diff or git log already says,
session trivia, restated documentation.

## Write the note

`memory/{lessons|antipatterns|patterns}/<slug>.md`

- **lessons** — what happened and why it went that way.
- **antipatterns** — the trap and how to avoid it.
- **patterns** — a reusable approach with 2+ real uses behind it. A
  good idea with zero uses is not a pattern; speculative patterns were
  the previous system's graveyard.

Body ≤ 30 lines: **What happened** (file:line, commit) → **Why** →
**How to apply**. Link related notes with `[[slug]]`.

## Anchor it to the code

If the note is about specific code, name that code in front-matter — this is
what makes it findable later by someone standing in the file, instead of only
by someone who already guessed the symptom (skill `recall`):

```yaml
---
name: cron-runner-host-header-regression
description: v2 multi-tenant Host routing in middleware broke internal cron callers
kind: antipattern
code:
  - apps/web/proxy.ts#handleRequest
  - apps/web/middleware.ts
---
```

Anchor what the lesson is *about*, not every file the session opened. A prose
mention of `proxy.ts` in the body is not an anchor: it cannot be queried and it
cannot be checked for rot. An anchor can — when the code moves, `recall --check`
says so.

## Index it

Add ONE line to the matching domain section of `memory/MEMORY.md`:

`- [Title](antipatterns/<slug>.md) — recall hook`

The hook (≤120 chars) is what a future session greps for — name the
symptom, not the moral. Hard rules: one physical line, no paragraphs,
bodies never in the index. The previous index grew into 104 KB of
paragraphs and became context rot that every session paid to load.

## Maintain

A note proven wrong → update it in place, noting what superseded it;
never write a duplicate alongside. A domain section that no longer
scans in one glance (~40 lines) → split it by sub-domain. The index
works only while it can be read whole.
