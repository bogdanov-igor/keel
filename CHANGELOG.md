# Changelog

All notable changes to Keel. Versions follow [semver](https://semver.org).

## [1.5.0] — 2026-07-14

Memory grounded by location, not by symptom.

### Added

- **`recall` skill — code anchors.** Grounding used to work by *symptom*: grep the
  error and hope. Never by *location*. In a real 222-note project memory, 139 notes
  name code files — 494 mentions across 237 unique files — and none of it was
  reachable from the code. You could not ask *"what does this project know about
  `apps/web/proxy.ts`?"* before opening it. Now a note declares the code it is about
  in its front-matter:

  ```yaml
  code:
    - apps/web/proxy.ts#handleRequest
    - apps/web/middleware.ts
  ```

  Two queries:

  ```bash
  bash .claude/skills/recall/anchors.sh apps/web/proxy.ts   # what we know about this code
  bash .claude/skills/recall/anchors.sh --check             # dead anchors
  ```

  Results come back in two sets: ANCHORED (exact, checkable) and MENTIONED (prose
  mentions, ranked by density — useful, noisy, and uncheckable, which is the whole
  argument for anchoring).
- **Rot detection**, which is the point of anchoring at all. Rename a symbol or
  delete a file and `--check` reports `DEAD_SYMBOL` / `DEAD_FILE`. A prose mention
  can never be checked — nothing about it is machine-readable. Verified end-to-end:
  a rename and a delete were both caught.
- **No code→code edges here, deliberately.** serena (LSP, already seeded in
  `.mcp.json`) computes callers, references and call hierarchy exactly and live —
  `find_symbol`, `find_referencing_symbols`. Hand-maintained code structure rots; an
  LSP does not. The anchors layer carries only what an LSP cannot know: what we
  *learned* about a place in the code.

### Changed

- **Contract rule 2 routes to it**: *"Before changing a file you did not just write,
  ground by location: skill recall."* This is the whole reason the contract grew from
  79 to 81 lines. A skill nobody is routed to is a skill nobody uses — which is
  exactly how the predecessor's skill catalogue died.
- `remember` gained the anchor convention: a note about code names that code in
  front-matter, rather than trusting prose to be findable later.
- `memory-consolidation` calls `anchors.sh --check` in its hygiene pass — a dead
  anchor is a finding, the same as a dead link.

### Honesty

- **The note-to-note graph is memory hygiene. That is all it is.** The 1.4.0 docs
  sold `graph.sh` — hubs, dead links, orphans — as a feature, with an implication
  that it helps you write code. It does not. It keeps memory clean, it is genuinely
  good at that, and there the claim ends. Rendering Keel's own markdown as a graph in
  Obsidian is decoration, not a tool; it drops out of the headlines and survives at
  most as a parenthetical that `memory/` happens to open in Obsidian or Foam. The
  graph that carries weight is code ↔ knowledge — that is `recall`, and it is new
  here. Unchanged and still worth stating: what Keel dropped from SkillForge was the
  PageRank *scorer*, not the graph; its value was never measurable (the eval saturated
  at recall@5 = 1.0 on six queries); and SkillForge's graph was note-to-note too — it
  never knew the code at all.
- **The kernel grew again.** Shell code is 1,460 lines across 9 files, up from 1,305
  across 8; the advantage over SkillForge's 6,316 lines of TS/JS/shell in 17 files
  narrows from 4.8x to 4.3x. The always-loaded contract is 81 lines / 4,227 chars
  (~1.1k tokens est.) against 327 lines / 15,245 chars (~3.8k) — 3.6x smaller.
  Installed footprint 304 KB / 54 files. 37 skills (7 core: `stage`, `qa-browser`,
  `audit`, `remember`, `recall`, `safe-dev-server`, `migrate` — plus 30 domain), 2
  subagents, 3 hooks, 0 runtime services. Both numbers move the wrong way, and both
  are printed here rather than quietly dropped: a kernel that only ever grows becomes
  the thing it replaced.

## [1.4.0] — 2026-07-14

Installation you can do by asking, and the memory graph made visible.

### Added

- **Ask-Claude installation.** The documented path is now: drop the archive in
  the project folder and tell Claude *"install keel from the archive in this
  folder: verify the sha256, unpack it, run `keel/install.sh`"* — then, for a
  project coming from an older system, *"clean up the leftovers from the old
  system and propose the re-audit."* The shell commands remain, one scroll
  down, for anyone who would rather type them.
- **`graph.sh`** in the `memory-consolidation` skill — the memory graph from the
  notes themselves: hubs (most-cited notes), dead links, orphans, totals, and
  `--edges` for the raw adjacency list. No index, no daemon, no build step. It
  discounts fenced code blocks, inline code spans and POSIX classes like
  `[[:space:]]`, so prose *about* wikilinks is not miscounted as an edge — on a
  real 222-note memory that removed every one of the four "dead links" a naive
  grep reported.
- **The graph, documented** (`docs/*/architecture.md`, `docs/*/why-keel.md`):
  the edges are the `[[wikilinks]]` in the notes and always were — the
  predecessor built its graph from these same links at query time. What Keel
  dropped is the PageRank *scorer*, whose contribution its own eval could never
  establish (saturated at recall@5 = 1.0 on six queries). The model walks the
  links itself, per contract rule 2. And `memory/` opens in Obsidian or VS Code
  Foam as a visual graph with zero dependencies added.

### Changed

- `memory-consolidation` calls `graph.sh` instead of re-deriving the same greps
  inline; hubs are the cheap centrality signal, and a note cited by 2+ others is
  the promote-to-pattern trigger.
- `install.sh` next-steps wording now reads correctly whether a human or Claude
  ran it.

## [1.3.0] — 2026-07-14

First public release.

### Added

- **Apache-2.0 licence**, `NOTICE`, and authorship throughout. Redistribution
  is free; attribution and a statement of changes are not.
- **Documentation in English and Russian**, shipped *inside* the archive
  (`docs/en/`, `docs/ru/`): install, architecture, migration, and
  [why-keel](docs/en/why-keel.md) — the measured comparison against SkillForge.
- **`migrate` skill** — sweeps SkillForge residue out of a project Keel now
  runs. The predecessor's machinery (bundle, MCP entry, persona agents, ghost
  skills, protocol file) moves to a timestamped `.keel-migration/<ts>/`
  quarantine with a restore manifest. Project state — memory, stages, backlog,
  `_user` skills, source — is never touched, and ambiguous paths are flagged
  for the owner instead of moved. Ends by proposing a re-audit, because the
  kernel changed underneath the codebase.
- **Update check** — a `SessionStart` hook compares the installed version
  against the latest upstream release (24h cache, 3s network ceiling) and
  prints exactly one line when a newer version exists. Silent otherwise, so
  the happy path costs zero tokens. Opt out via `update_check.enabled` in
  `keel.json`.
- **Installer output for humans** — banner, colour, and a summary of what was
  installed, preserved, and seeded. Honours `NO_COLOR` and non-TTY.
- `.claude/VERSION` is stamped at install time (the update check reads it).

### Changed

- `install.sh` now *detects* previous-system residue and points at the
  `migrate` skill instead of only warning. An installer does not move
  someone's files; the skill does, with the owner present.
- `build-archive.sh` ships docs, licence, and changelog inside the tgz, and
  its self-test now covers the version stamp, the migrate skill, and the
  update-check hook's silence on a current install.

## [1.2.0] — 2026-07-13

Pre-public. Kernel as rebuilt after the SkillForge audit: 75-line contract,
35 lazy-loaded skills, `OPS.md` duty board (build/live), `scout` + `verifier`
subagents, leak and forkbomb hooks, file memory, no MCP of its own. Validated
by two multi-agent reviews and a fresh-eyes pass.
