# Changelog

All notable changes to Keel. Versions follow [semver](https://semver.org).

## [1.6.0] — 2026-07-15

The kernel tests itself before it ships, and existing notes anchor to their code
in one pass.

### Added

- **`recall --backfill` — anchor an existing note without editing front-matter by
  hand.** 1.5.0 gave notes a `code:` block and the tooling to query and rot-check
  it, but every anchor still had to be typed in by hand — so a memory written
  before 1.5.0 stayed unreachable by location. Backfill reads each note, pulls
  every code file it names in prose, and resolves that name against the real tree:

  ```bash
  bash .claude/skills/recall/anchors.sh --backfill          # dry run — nothing written
  bash .claude/skills/recall/anchors.sh --backfill --apply  # write the front-matter
  ```

  It anchors only a mention that resolves to **exactly one** file — which is what
  makes the monorepo prefix fall into place. A note that says `apps/web/proxy.ts`
  becomes `shippulse/apps/web/proxy.ts` when the app lives in a subdirectory,
  because that is the single file whose path ends in the mention. A bare
  `route.ts` matching many files is reported as *ambiguous* and left for you to
  anchor by hand; a name that matches nothing is reported as *unresolved*. Neither
  is guessed — anchoring a path that does not resolve only manufactures the dead
  anchor `--check` exists to catch. Dry-run by default; `--apply` writes;
  idempotent — a note that already carries a `code:` block is skipped, so a second
  run anchors nothing. It needs the project's code on disk to resolve against.
  Validated on a real 222-note memory: it resolved the monorepo prefix and every
  anchor it wrote came back live under `--check`.
- **Kernel self-tests — `test/run.sh`.** bash assertions over the shipped scripts
  — `anchors.sh`, `graph.sh`, `sweep.sh`, `update-check.sh` — run against
  throwaway fixtures, offline, touching nothing outside a temp dir, non-zero exit
  on any failure. Every case encodes a bug that actually shipped and was caught
  only by reading the script: `--check` reporting a symbol alive after
  `handleRequest → handleRequestV2` because `grep -F` is a substring match (and
  the suffix rename — `V2`, `Async`, `Internal` — is the commonest refactor there
  is); MENTIONED ranked by matching *lines* when a note can name a file five times
  on one line, so the rank has to count *mentions*. The last three releases each
  shipped a bug of exactly this shape in the kernel's own scripts — small,
  plausible, and invisible until someone read it adversarially, because shell has
  no compiler to fail first. The suite pins those cases so they cannot regress. It
  is not a feature and it does not install into a project: it is a maintainer
  tool, and it is what keeps the kernel trustworthy.

### Changed

- **`build-archive.sh` gates on the suite.** It runs `test/run.sh` before it
  packages anything and aborts the build if a single case fails — a script that
  fails its own test never ships. The build passing was never the release gate;
  the suite passing is.

### Note

- **The kernel grew again — and this time most of the growth is the tests.** Shell
  code is 1,701 lines across 10 files, up from 1,460 across 9; the lead over
  SkillForge's 6,316 lines in 17 files narrows from 4.3x to 3.7x. Of the +241
  lines, **157 are `test/run.sh` itself** — the addition made to keep the kernel
  trustworthy is also the largest single addition, and it enlarges the very "code
  you have to trust" that it exists to guard. That irony is the honest point, not
  something to bury. Split by who runs it: 1,478 lines across 8 files ship into a
  project (`install.sh` and the bundle scripts); 223 lines across 2 files are
  maintainer-only (`build-archive.sh` 66, `test/run.sh` 157) and never reach a
  user. SkillForge's 6,316 counted its own eval/test harness too, so measuring
  keel's tests on the same line is apples-to-apples, not a thumb on the scale. The
  growth ladder, stated plainly: 1.3.0 = 893 lines / 5 files (7.1x), 1.4.0 =
  1,305 / 8 (4.8x), 1.5.0 = 1,460 / 9 (4.3x), 1.6.0 = 1,701 / 10 (3.7x). Still the
  wrong direction; the difference now is that the new lines are assertions about
  the old ones.
- **What did not move.** The always-loaded contract is still 81 lines / 4,227
  chars (~1.1k tokens est.) against 327 lines / 15,245 chars (~3.8k) — 3.6x
  smaller. Installed footprint 312 KB / 54 files against SkillForge's 63 MB /
  3,796 files (4.3 MB / 133 for its cleanest shipped tree) — 14x smaller than the
  cleanest measure, 207x than a working project. 37 skills (7 core: `stage`,
  `qa-browser`, `audit`, `remember`, `recall`, `safe-dev-server`, `migrate` —
  plus 30 domain), 2 subagents, 3 hooks, 0 runtime services.

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
