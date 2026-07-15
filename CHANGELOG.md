# Changelog

All notable changes to Keel. Versions follow [semver](https://semver.org).

## [1.7.0] — 2026-07-15

Documentation pass and an architecture diagram. No kernel changes.

### Changed

- README (EN/RU), the four guides in docs/ and this changelog reworded;
  section structure aligned between the two languages.
- docs/assets/architecture.svg: kernel/project layout diagram, referenced
  from both architecture guides.

## [1.6.0] — 2026-07-15

Kernel self-test suite; `recall --backfill` anchors existing notes in one
pass.

### Added

- `recall --backfill`: anchors an existing note without editing front-matter
  by hand. 1.5.0 introduced the `code:` block and the tooling to query and
  rot-check it, but every anchor still had to be typed in manually, so notes
  written before 1.5.0 stayed unreachable by location. Backfill reads each
  note, collects the code files it names in prose, and resolves each name
  against the real tree:

  ```bash
  bash .claude/skills/recall/anchors.sh --backfill          # dry run — nothing written
  bash .claude/skills/recall/anchors.sh --backfill --apply  # write the front-matter
  ```

  A mention is anchored only when it resolves to exactly one file. That rule
  also handles monorepo prefixes: a note that says `apps/web/proxy.ts`
  becomes `shippulse/apps/web/proxy.ts` when the app lives in a
  subdirectory, because that is the single file whose path ends in the
  mention. A bare `route.ts` matching many files is reported as ambiguous
  and left for manual anchoring; a name that matches nothing is reported as
  unresolved. Neither is guessed — an anchor on a path that does not resolve
  is exactly the dead anchor `--check` exists to catch. Dry run by default;
  `--apply` writes; idempotent — a note that already carries a `code:` block
  is skipped, so a second run anchors nothing. Needs the project's code on
  disk to resolve against. Validated on a real 222-note memory: the monorepo
  prefix resolved correctly and every anchor it wrote came back live under
  `--check`.
- Kernel self-tests, `test/run.sh`: bash assertions over the shipped scripts
  (`anchors.sh`, `graph.sh`, `sweep.sh`, `update-check.sh`), run offline
  against throwaway fixtures, touching nothing outside a temp dir, non-zero
  exit on any failure. Every case encodes a bug that actually shipped and
  was caught only by reading the script: `--check` reported a symbol alive
  after `handleRequest → handleRequestV2` because `grep -F` matches
  substrings (and suffix renames — `V2`, `Async`, `Internal` — are the most
  common refactor); MENTIONED was ranked by matching lines, although a note
  can name a file five times on one line, so the rank now counts mentions.
  Each of the last three releases shipped a bug of this shape in the
  kernel's own scripts — small, plausible, invisible until read
  adversarially, since shell has no compiler to fail first. The suite pins
  those cases so they cannot regress. It is a maintainer tool and does not
  install into a project.

### Changed

- `build-archive.sh` runs `test/run.sh` before packaging anything and aborts
  the build if a single case fails.

### Note

- Size: shell code is 1,701 lines across 10 files, up from 1,460 across 9;
  the lead over SkillForge's 6,316 lines in 17 files narrows from 4.3x to
  3.7x. Of the +241 lines, 157 are `test/run.sh` itself, so most of the
  growth is the test suite — which also enlarges the very code it exists to
  guard. Split by who runs it: 1,478 lines across 8 files ship into a
  project (`install.sh` and the bundle scripts); 223 lines across 2 files
  are maintainer-only (`build-archive.sh` 66, `test/run.sh` 157) and never
  reach a user. SkillForge's 6,316 counted its own eval/test harness too, so
  the comparison stays like-for-like. Growth by release: 1.3.0 = 893 lines /
  5 files (7.1x), 1.4.0 = 1,305 / 8 (4.8x), 1.5.0 = 1,460 / 9 (4.3x),
  1.6.0 = 1,701 / 10 (3.7x). The trend is still in the wrong direction.
- Unchanged: the always-loaded contract is still 81 lines / 4,227 chars
  (~1.1k tokens est.) against 327 lines / 15,245 chars (~3.8k) — 3.6x
  smaller. Installed footprint 312 KB / 54 files against SkillForge's 63 MB
  / 3,796 files (4.3 MB / 133 for its cleanest shipped tree) — 14x smaller
  than the cleanest measure, 207x than a working project. 37 skills (7 core:
  `stage`, `qa-browser`, `audit`, `remember`, `recall`, `safe-dev-server`,
  `migrate` — plus 30 domain), 2 subagents, 3 hooks, 0 runtime services.

## [1.5.0] — 2026-07-14

The `recall` skill: code anchors in project memory.

### Added

- `recall` skill, code anchors. Until now memory grounding worked only by
  symptom — grep the error text and hope — never by location. In a real
  222-note project memory, 139 notes name code files (494 mentions across
  237 unique files), and none of it was reachable from the code side: there
  was no way to ask what the project knows about `apps/web/proxy.ts` before
  opening it. A note now declares the code it is about in its front-matter:

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

  Results come back in two sets: ANCHORED (declared in front-matter, exact
  and checkable) and MENTIONED (prose mentions ranked by density — useful,
  but noisy and uncheckable).
- Rot detection: rename a symbol or delete a file and `--check` reports
  `DEAD_SYMBOL` / `DEAD_FILE`. A prose mention cannot be checked — nothing
  about it is machine-readable. Verified end-to-end: a rename and a delete
  were both caught.
- Code→code edges are deliberately not built here. serena (LSP, already
  seeded in `.mcp.json`) computes callers, references and call hierarchy
  exactly and live — `find_symbol`, `find_referencing_symbols`.
  Hand-maintained code structure rots; an LSP does not. The anchors layer
  carries only what an LSP cannot know: what we learned about a place in the
  code.

### Changed

- Contract rule 2 routes to the skill: before changing a file you did not
  just write, ground by location (`recall`). This is why the contract grew
  from 79 to 81 lines.
- `remember` gained the anchor convention: a note about code declares that
  code in front-matter instead of relying on prose being findable later.
- `memory-consolidation` calls `anchors.sh --check` in its hygiene pass — a
  dead anchor is a finding, same as a dead link.

### Corrections

- The note-to-note graph is memory hygiene and nothing more. The 1.4.0 docs
  presented `graph.sh` (hubs, dead links, orphans) with the implication that
  it helps write code; it does not — it keeps memory clean, and the docs now
  claim only that. Rendering `memory/` as a graph in Obsidian or Foam is a
  property of the file format, not a feature, and drops out of the headlines
  accordingly. The graph that matters is code ↔ knowledge — that is
  `recall`, new in this release. Still true and worth restating: what Keel
  dropped from SkillForge was the PageRank scorer, not the graph; its value
  was never measurable (the eval saturated at recall@5 = 1.0 on six
  queries); and SkillForge's graph was note-to-note too — it never knew the
  code.
- Size: shell code is 1,460 lines across 9 files, up from 1,305 across 8;
  the advantage over SkillForge's 6,316 lines of TS/JS/shell in 17 files
  narrows from 4.8x to 4.3x. The always-loaded contract is 81 lines / 4,227
  chars (~1.1k tokens est.) against 327 lines / 15,245 chars (~3.8k) — 3.6x
  smaller. Installed footprint 304 KB / 54 files. 37 skills (7 core:
  `stage`, `qa-browser`, `audit`, `remember`, `recall`, `safe-dev-server`,
  `migrate` — plus 30 domain), 2 subagents, 3 hooks, 0 runtime services.
  Both size numbers moved the wrong way; they are recorded here rather than
  quietly dropped.

## [1.4.0] — 2026-07-14

Installation by asking Claude; memory-graph tooling.

### Added

- Ask-Claude installation. The documented path is now: drop the archive into
  the project folder and tell Claude "install keel from the archive in this
  folder: verify the sha256, unpack it, run `keel/install.sh`" — and, for a
  project coming from an older system, "clean up the leftovers from the old
  system and propose the re-audit." The shell commands remain documented one
  scroll down for anyone who prefers to type them.
- `graph.sh` in the `memory-consolidation` skill: the memory graph derived
  from the notes themselves — hubs (most-cited notes), dead links, orphans,
  totals, and `--edges` for the raw adjacency list. No index, no daemon, no
  build step. Fenced code blocks, inline code spans and POSIX classes like
  `[[:space:]]` are discounted, so prose about wikilinks is not miscounted
  as an edge; on a real 222-note memory this removed all four "dead links" a
  naive grep reported.
- Graph documentation in `docs/*/architecture.md` and `docs/*/why-keel.md`:
  the edges are the `[[wikilinks]]` in the notes and always were — the
  predecessor built its graph from these same links at query time. What Keel
  dropped is the PageRank scorer, whose contribution its own eval could
  never establish (saturated at recall@5 = 1.0 on six queries). The model
  walks the links itself, per contract rule 2. `memory/` also opens in
  Obsidian or VS Code Foam as a visual graph with no added dependencies.

### Changed

- `memory-consolidation` calls `graph.sh` instead of re-deriving the same
  greps inline; hubs serve as the cheap centrality signal, and a note cited
  by 2+ others is the promote-to-pattern trigger.
- `install.sh` next-steps wording now reads correctly whether a human or
  Claude ran it.

## [1.3.0] — 2026-07-14

First public release.

### Added

- Apache-2.0 licence, `NOTICE`, and authorship throughout. Redistribution is
  free; attribution and a statement of changes are required.
- Documentation in English and Russian, shipped inside the archive
  (`docs/en/`, `docs/ru/`): install, architecture, migration, and
  [why-keel](docs/en/why-keel.md) — the measured comparison against
  SkillForge.
- `migrate` skill: sweeps SkillForge residue out of a project Keel now runs.
  The predecessor's machinery (bundle, MCP entry, persona agents, ghost
  skills, protocol file) moves to a timestamped `.keel-migration/<ts>/`
  quarantine with a restore manifest. Project state — memory, stages,
  backlog, `_user` skills, source — is never touched, and ambiguous paths
  are flagged for the owner instead of moved. Ends by proposing a re-audit,
  because the kernel changed underneath the codebase.
- Update check: a `SessionStart` hook compares the installed version against
  the latest upstream release (24h cache, 3s network ceiling) and prints one
  line when a newer version exists, nothing otherwise, so the happy path
  costs zero tokens. Opt out via `update_check.enabled` in `keel.json`.
- Installer output for humans: banner, colour, and a summary of what was
  installed, preserved, and seeded. Honours `NO_COLOR` and non-TTY.
- `.claude/VERSION` is stamped at install time (the update check reads it).

### Changed

- `install.sh` now detects previous-system residue and points at the
  `migrate` skill instead of only warning. Moving someone's files is left to
  the skill, run with the owner present.
- `build-archive.sh` ships docs, licence, and changelog inside the tgz, and
  its self-test now covers the version stamp, the migrate skill, and the
  update-check hook's silence on a current install.

## [1.2.0] — 2026-07-13

Pre-public. Kernel as rebuilt after the SkillForge audit: 75-line contract,
35 lazy-loaded skills, `OPS.md` duty board (build/live), `scout` + `verifier`
subagents, leak and forkbomb hooks, file memory, no MCP of its own. Validated
by two multi-agent reviews and a fresh-eyes pass.
