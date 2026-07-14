# Changelog

All notable changes to Keel. Versions follow [semver](https://semver.org).

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
  real 223-note memory that removed every one of the four "dead links" a naive
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
