---
name: recall
description: Ground in what the project already learned about a specific place in the code — before changing it. Answers "what do we know about this file/symbol", and detects notes whose code anchors no longer resolve (the code moved; the note now lies). Use before touching an unfamiliar or previously-burned file, and when memory feels detached from the codebase.
---

# Recall

`remember` writes what we learned. **Recall finds it again — by location.**

Grounding by *symptom* is grep: you already have to suspect the failure to
find the lesson about it. Grounding by *location* is this: you are about to
open `apps/web/proxy.ts`, and the four things this project learned the hard way
about that file arrive before you type.

That gap is real, not theoretical. In a mature project memory, most notes name
code — and none of it is reachable from the code.

## Use it

```sh
bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # before you touch it
bash .claude/skills/recall/anchors.sh handleRequest       # by symbol
bash .claude/skills/recall/anchors.sh --check             # dead anchors
bash .claude/skills/recall/anchors.sh --list              # every anchor
```

Two result sets:

- **ANCHORED** — notes that declared this code in their front-matter. Exact,
  and checkable.
- **MENTIONED** — notes that merely name it in prose, ranked by how often.
  Useful, noisy, and unverifiable — which is the whole argument for anchoring.

## The anchor

A note about specific code carries it in front-matter:

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

`path/to/file.ts#symbol`, or just `path/to/file.ts`. Anchor what the lesson is
*about* — not every file the session happened to open.

## Why anchors and not a code graph

Callers, references, import trees, call hierarchy — **serena (LSP) already
computes these exactly and live.** `find_symbol`, `find_referencing_symbols`.
Never hand-maintain code structure: it rots the moment someone refactors, and
a rotted map is worse than no map.

What an LSP cannot know is what *happened* here: that this file was the one
that fork-bombed a Mac, that this route shipped green and broke in prod, that
this function is the wedge that keeps reopening. That is the only edge this
layer carries — and it is the one no tool can derive.

## Rot is the point

An anchor that no longer resolves is a note describing code that no longer
exists. `--check` finds them; a plain prose mention can never be checked at
all. Dead anchors are P2, filed like any finding:

```text
- [ ] P2 | memory | repair anchor apps/web/proxy.ts#handleRequest (symbol gone — renamed?) | src:recall
```

Run `--check` as part of `memory-consolidation`, and whenever a refactor moves
files.

## When NOT to use it

Small, familiar, low-risk edits in code you just wrote. Recall is for the file
you have not touched in a month, the one someone else built, or the one that
burned this project before.
