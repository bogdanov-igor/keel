# Changelog

All notable changes to Keel. Versions follow [semver](https://semver.org).

## [1.8.0] — 2026-09-12

Three things at once: the shared plumbing that Loft 1.3.0 hardened comes
back into Keel; the first rules a hook can enforce stop being prose; and
three questions the kernel had been carrying as assumptions were
measured on a live Claude Code and closed. Decisions that bind future
releases now live in [ROADMAP.md](ROADMAP.md).

### Added

- Four hooks, one pain behind each. `recompact.sh` runs on
  `SessionStart` with the `compact` matcher: after a context compaction
  it prints back what the compaction dropped — the active stage's goal,
  the open `claim:` lines from `BACKLOG.md`, the gates (qa-browser,
  verifier, recall, remember) and a reminder that the skill listing is
  loaded on use; compaction is the documented moment a long session
  "gets dumb", because the skill listing is not re-injected and hook
  context is summarized away. `verdict-guard.sh` runs on `Write|Edit`
  to `stages/*/report.md` and refuses a `N pass / M fail` count that
  carries no agent id — a verdict written by hand before the verifier
  ran happened once in production and read as real. `loop-guard.sh`
  runs on `PostToolUseFailure` for Bash: on the third failure of the
  same command with the same first error line it puts one sentence into
  context — the contract's two-attempts rule, at the moment the model
  is tunnel-visioned; it never blocks and keeps a tally of its own
  firings. `index-guard.sh` runs on `PostToolUse` for writes to
  `memory/MEMORY.md` and says when the index passes 250 lines or one
  line passes 300 characters; the predecessor's index bloated until it
  was useless.
- The kernel's settings deny reading `.secrets.env`
  (`permissions.deny: Read(./.secrets.env)`). Measured: the Read tool
  and `cat` are refused, a `grep -r` from the directory is not; newer
  Claude Code versions also refuse writing the file, so you fill
  it by hand. The settings also pin `skillListingBudgetFraction: 0.02`:
  the listed descriptions are about 2k tokens, the documented default
  budget is 1% of the context window, and overflow drops descriptions
  silently, least-invoked first.
- Three skills, all invoked by you. `integrations`: after
  install, or on request, detects what the project can reach (gh, uvx,
  npx, node, python3, codex, gemini, Playwright browsers, MCP servers),
  asks one question per item, and records the answers in the `OPS.md`
  access registry; it installs nothing and signs into nothing.
  `adopt-feedback`: sweeps your corrections out of Claude Code's
  own auto memory into `memory/` and `BACKLOG.md`, so a correction given
  twice becomes a kernel change instead of a machine-local note; it now
  has a monthly `OPS.md` duty. `design-port`: ports a design made in
  Claude Design into the product one to one and verifies it by
  rendering pixels next to the reference — the practice one product ran
  for three months, written down.
- `qa-browser` ships its sweep as a file, `sweep.mjs`, instead of a
  code block to copy. The sweep hit-tests every interactive element
  (`click-stolen`: the element under a control's centre is not the
  control), and the check was measured on eight public sites in three
  viewports plus a local Astro build: its three false-positive classes —
  a link wrapped over two lines, a screen-reader-only skip link, a link
  cut off by an overflow-hidden cell — are handled, the rerun reports
  none, and a fixture page with a real theft pins that it still catches
  one. New `low-contrast`: text whose colour against the nearest opaque
  background falls under 4.5:1 (3:1 for large text), twelve per page,
  text over images skipped. `element-overflow` now ignores overflow
  inside a scroller and reports one line per selector. The reference
  for a screenshot comparison is a tracked file under `qa-baseline/`,
  changed only with a verifier pass or by you. QA without a
  server: when the circuit breaker refuses a process, Playwright serves
  the built output itself.
- `stage`: done criteria written before the work (the verifier judges
  by these), a line saying who reads the result and what they will do
  with it, a premortem in three rounds ("it is the day this stage was
  due, and it has failed — name the causes that follow from this brief,
  each tied to a file or section of it, each with a first-week
  signal"), a brief readable by an agent that never saw the session,
  `/clear` between stages, parallel units in worktrees, the Verifier
  section born as a placeholder that only a real run fills, and a
  report with no narrative — it is read to decide what is next.
- `verifier` runs on opus and preloads `qa-browser` — the contract had
  been routing it to a skill it could not invoke. Before a pass it names
  the check that would have refuted it; every fail carries a severity
  (blocker, important, optional) and the author chooses what to fix
  first; two rounds at most. `scout` runs on sonnet at medium effort,
  cannot write, starts from the project's map when there is one, and
  returns the list of files it read whole apart from those it only
  excerpted. `codebase-map` now writes that map as a memory note
  anchored to the entry points, so `recall --check` reports the day it
  stops matching the tree.
- Contract: "read" means opened whole, and Read cuts at 2000 lines
  without saying so; auto-memory notes worth keeping move into
  `memory/`; a screenshot plus "looks correct" is not a result; two
  failed attempts at one fix stop the attempt; a test is never
  weakened, skipped or deleted to get a green run; parallel work runs
  in `claude --worktree`; the leak hook only knows the values in
  `.secrets.env`, and hosts and credentials typed in the clear are the
  agent's to catch; a read that would flood the main window goes to
  `scout`; the verdict comes first and unchecked claims are marked.
  81 lines became 101 (5,576 characters).
- The five skills that run a kernel script (`recall`, `qa-browser`,
  `safe-dev-server`, `migrate`, `memory-consolidation`) name it in
  `allowed-tools`, so the sanctioned path costs no permission prompt.
- `OPS.md`: the live mode names the five ways to run a duty without
  asking (`/loop` in an open session, cron with `claude -p`, Desktop
  tasks, cloud routines, GitHub Actions) and what each can reach; four
  duties — the auto-memory sweep, kernel cost with `/skill-doctor`, the
  Claude Code changelog read for what a mechanism could replace, and a
  quarterly review of which model inability each hook and rule still
  compensates.
- `remember`: a lesson about how the agent works is also filed as a
  `src:kernel` line in `BACKLOG.md`, so it reaches the kernel.
- `install.sh` carries `settings.local.json`, `commands/`, `rules/`,
  `output-styles/` and project agents across a reinstall (it kept only
  skills), gives every backup a unique name, appends to `.gitignore`
  without gluing onto a last line that has no newline, seeds
  `.worktreeinclude` so a worktree session gets `.secrets.env`, seeds
  serena only when `uvx` exists, seeds `.vscode/extensions.json` with
  Foam when the project has none (the memory's `[[wikilinks]]` become a
  graph in VS Code), says what an existing `.mcp.json` costs in schema
  tokens, reports which integrations the machine has, derives the
  expected skill count from the bundle instead of a number that had
  already drifted, and self-checks the installed kernel — on failure it
  rolls the previous `.claude` back.
- `migrate`: the manifest carries a runnable restore command per moved
  path; Keel's own `.claude.bak.*` is labelled as such.
- `build-archive.sh` is hermetic (own cache, no network), packs with
  python's `tarfile` so the same tag gives the same sha256 on any
  machine, ships `ROADMAP.md`, refuses to run when a declared input is
  missing, and its self-test checks the Russian diagram is inside.
- Self-tests split into `test/cases/*.sh`, one file per zone, and grew
  from 37 to over 400 assertions: every hook (the two new ones with a
  real captured payload as the fixture), a worktree case that runs
  every hook with `cwd` and `CLAUDE_PROJECT_DIR` disagreeing, the
  installer, bundle integrity (front-matter, hook paths, skill
  references, `allowed-tools` paths, agent models), the build from a
  fixture derived from the repository instead of a list that drifted,
  a positive-control page for the browser sweep (runs where Playwright
  is present), and `test/metrics.sh` with a case that pins every number
  the docs quote to the measured value — the docs had shipped a stale
  one five releases in a row.

### Measured and closed

- `.claude/CLAUDE.md` survives compaction. On Claude Code 2.1.87, with
  a `PreCompact` hook rewriting the contract on disk during the
  compaction, the next user turn followed the rewritten text in both
  placements (`.claude/CLAUDE.md` and a root `CLAUDE.md`), and
  `InstructionsLoaded` fired with `load_reason: compact`. The placement
  stays.
- Hooks in a worktree. In a session launched with `claude --worktree`,
  `CLAUDE_PROJECT_DIR` is the worktree and the worktree's own
  `settings.json` is read; `.worktreeinclude` carried `.secrets.env`;
  `forkbomb-guard` denied from inside. `recompact` takes the project
  from the payload's `cwd` for the case where a session enters a
  worktree later.
- The hit-test's false positives (above). Loft received the WIP limit
  on audit findings and the claim discipline in its contract.

### Fixed

- `leak-guard` blocked the edit that removes a leaked secret (the value
  sat in `old_string`), missed values containing a quote or backslash,
  `export KEY=`, CRLF and inline comments, treated `PORT=8080` as a
  secret, and returned invalid JSON for a key with a quote. It now scans
  only the new text, parses `.secrets.env` tolerantly, ignores values
  under six characters and escapes what it prints. Ported from Loft
  1.3.0 with a jq/python3 parser and a raw-payload fallback.
- `update-check` died with `HOME: unbound variable` when neither `HOME`
  nor `XDG_CACHE_HOME` was set, retried the network on every start when
  offline, and read `"enabled": false` from any section of `keel.json`.
  Now: negative cache for an hour, scoped parsing, `KEEL_NO_UPDATE_CHECK`,
  and a newer `keel/VERSION` next to the project is announced too.
- `site-sweep` described a crawler at `.qa/site-sweep.mjs` that the
  kernel never shipped; it now says the crawler is written per project
  on top of `qa-browser`'s `sweep.mjs` and gives the output contract.
- `migrate` and `site-sweep` carry `disable-model-invocation`: one moves
  files, the other starts a half-hour crawl — neither runs on a guess.
- Four references to contract rules by number replaced by name; a
  private product path in the `recall` example replaced.
- README claimed Playwright was the only optional dependency while the
  installer seeded serena (`uvx`) and context7 (`npx`).
- The 1.7.0 archive was built before the Russian architecture diagram
  existed, so its Russian guide pointed at the English one.
- `.serena/` is no longer tracked.

### Corrections

- 1.5.0 said 139 notes of a 222-note memory named code; every later
  document says 141 with the same 494 mentions and 237 files. 141 is the
  later recount; 139 stands here as written.

### Note

- Size: shipped shell is 2,335 lines across 12 files (the installer,
  7 hooks, 4 skill scripts) plus 158 lines of JavaScript in `sweep.mjs`;
  maintainer-only shell is 1,858 lines across 19 files (the builder, the
  test runner, `metrics.sh`, 16 case files). All shell: 4,193 lines / 31
  files against SkillForge's 6,316 / 17 — 1.5×, down from 3.7× at 1.4.0;
  the shipped part alone is 2.7×. Of the +2,492 lines since 1.7.0, 1,538
  are tests and 435 the four new hooks. The contract is 101 lines / 5,576
  chars (~1.4k tokens est.) against 327 / 15,245 (~3.8k) — 2.7× smaller,
  was 3.6×. Installed footprint 380 KB / 62 files (was 312 KB / 54). 40
  skills (9 core: `stage`, `qa-browser`, `audit`, `remember`, `recall`,
  `safe-dev-server`, `migrate`, `integrations`, `adopt-feedback` — plus
  31 domain), 2 subagents, 7 hooks, 0 runtime services, over 400
  self-tests. The lead over SkillForge keeps shrinking and is recorded
  rather than hidden; whether each new mechanism earns its lines is what
  the quarterly assumptions review in `OPS.md` now exists to answer.

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
