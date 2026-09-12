# Install & update

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `bash`, `tar` — present on macOS and Linux out of the box; `curl` for the
  update check alone, and without it the check exits in silence
- Optional `python3`: the installer filters the MCP seed with it, and the
  hooks read their JSON payload with `jq` when it is there and `python3`
  otherwise; with neither, `leak-guard` scans the raw payload and the deny
  hooks let the call through, so one of the two is needed for them to guard
- Optional `uvx` for the seeded serena server, `npx` for context7, `node`
  and Playwright (`npx playwright install chromium`) for browser QA

Keel runs nothing of its own: no MCP server it owns, no daemon, no index to
build. The kernel is shell and markdown.

## Quickstart

**1.** Download `keel_1.8.0.tgz` and `keel_1.8.0.tgz.sha256` from
[Releases](https://github.com/bogdanov-igor/keel/releases/latest) into your
project folder.

**2.** Open the project in Claude Code and say:

> Install keel from the archive in this folder: verify the sha256, unpack it,
> run `keel/install.sh`, then tell me what it set up.

**3.** Ran SkillForge before — add "clean up the leftovers from the old
system and propose the re-audit": the machinery goes to quarantine, nothing
is deleted, see [migration](migration.md).

## By hand

Both paths run the same installer.

### From the archive

```sh
cd /path/to/project                 # copy both files here
shasum -c keel_1.8.0.tgz.sha256     # verify integrity first: expect "OK"
tar -xzf keel_1.8.0.tgz
bash keel/install.sh                # no argument = install into this directory
```

The `keel/` folder can stay in the project (re-running `install.sh` updates
the kernel, and the update check reads its `VERSION`) or be deleted. If it
stays, add it and the `.tgz` to `.gitignore`.

### From the source repo

```sh
git clone https://github.com/bogdanov-igor/keel.git
bash keel/install.sh /path/to/project
```

## What the installer does

| Action | Detail |
|---|---|
| Installs the kernel | Copies `bundle/.claude` in as a real directory, never a symlink — symlinks break hook path resolution and per-project memory. An existing `.claude` moves to `.claude.bak.<timestamp>` first, and that name is made unique rather than merely timestamped: two installs in the same second made `mv` drop the second backup inside the first, burying the real previous `.claude` two levels below the path the message named. Every `*.sh` in the new `.claude` gets the execute bit back, because unpacking and copying drop it and the hooks need it at the next session start. The skills, agents and hooks it reports are counted from the tree it just installed, never from a number in the script. |
| Stamps the version | Writes `.claude/VERSION`, which the update check reads. |
| Preserves your skills | A skill directory the kernel does not ship is carried over from the previous `.claude`, including one nested under a legacy SkillForge `skills/_user/`. When the backup is a SkillForge kernel (marker: `_protocol.md`), only `_user/` skills count as yours and its flat kernel skills stay buried, so the predecessor's machinery does not ride back in. |
| Carries over your Claude Code setup | `settings.local.json` (your permissions), `commands/`, `rules/`, `output-styles/` and your own agents come back file by file, and only where the kernel has nothing at that path, so a kernel file is never shadowed by a stale copy of itself. SkillForge's persona agents are the predecessor's machinery and stay in the backup. |
| Seeds project state | `memory/` with `lessons/`, `antipatterns/`, `patterns/` (each with a `.gitkeep`, so empty directories survive a clone), `stages/`, `BACKLOG.md`, `PARKED.md`, `OPS.md`, `keel.json`, `memory/MEMORY.md` — only where they are absent. Existing state is never overwritten, and the installer says which of the two happened. |
| Keeps four things out of git | Appends `.secrets.env`, `.qa/`, `.claude/worktrees/` and `.claude.bak.*` to `.gitignore`. A file whose last line has no newline gets one first, once, before the patterns — appending blind glues the first new pattern onto the project's last one and silently breaks both. |
| Seeds `.worktreeinclude` | One line, `.secrets.env`. A `claude --worktree` session starts in a fresh checkout, which by definition holds no ignored files, so without that line the secrets file the whole project depends on is missing there. |
| Seeds MCP, filtered | Writes `.mcp.json` only when the project has none, and writes only the servers whose launcher this machine has: serena needs `uvx`, context7 needs `npx`. A server that cannot start is worse than no server — Claude Code retries it at every session start and reports a failure you did not cause — so the rest is named in a line saying where to copy it from once the launcher exists. An existing `.mcp.json` is yours and is left exactly as it is, but it is counted: every configured server ships its whole tool schema into every session and into every subagent that session spawns, and the installer says how many are there, plus a word when serena is not among them. |
| Seeds VS Code recommendations | `.vscode/extensions.json` with Foam and a mermaid preview, and only when the project has no recommendations file of its own. The memory is a `[[wikilink]]` graph and the guides draw in mermaid; from an empty editor neither is discoverable. |
| Reports integrations | One line each for `gh`, `uvx`, `npx`, `node`, `python3`, `codex`, `gemini` and the Playwright browsers, present or absent, plus a line about Claude Design, which lives in your Claude account and cannot be detected on disk. Detection only: an installer that installs toolchains or signs anything in is an installer you cannot audit. |
| Detects residue | Runs the migration sweep in preview mode and raises the `migrate` banner when it finds real machinery. A report with flagged paths only — the `.claude.bak.*` this very install just made, for one — is not residue and raises nothing. No file is moved here. |
| Self-checks, then rolls back | The contract is at `.claude/CLAUDE.md`, every hook is executable, the installed skill count equals what the bundle it came from ships (a literal floor was a second inventory of the same thing: it said 37 while the bundle shipped more, and a half-copied bundle walked past it), `scout` and `verifier` are there, `settings.json` parses (a syntax error there silently costs the project every hook it has), and `recall`'s `anchors.sh` actually runs — against a throwaway project, because on the real one a tool may legitimately report findings, which is not a breakage. On failure the failed kernel is removed and the previous `.claude` comes back from the backup by itself: a half-installed kernel where a working one used to be is worse than an update that never happened, and you are not required to remember the backup's name. |

It ends with next steps that read the same whether you ran it or Claude did:
the `migrate` skill if residue was found, Playwright browsers for browser
QA, the project opened in Claude Code if you were at a terminal.

### After the install

Run `/integrations` in the first session: it detects what this project can
reach — CLIs, Playwright browsers, MCP servers, Claude Design, the
second-opinion models — asks one question per item, and records the answers
in the `OPS.md` access registry, what you defer in `PARKED.md`, what you
want set up in `BACKLOG.md`. It installs nothing and signs into nothing, and
until it runs every later session guesses.

`.secrets.env` the installer gitignores and names in `.worktreeinclude` but
never creates: you write it by hand. The kernel's settings deny reading it —
on Claude Code 2.1.87 the Read tool and `cat` are refused, a `grep -r` from
the directory is not, and newer versions refuse writing it too. In notes,
code and artifacts a value is written `{{secret:KEY}}`, and the leak hook
denies a write carrying one it can read in the file.

## Updating

The simplest path: download the new archive into the project folder and say:

> Update keel from the archive in this folder.

By hand it is the same command as the install, from a newer keel folder (a
fresh release, or `git pull`):

```sh
cd /path/to/project
bash keel/install.sh
```

Kernel files are replaced. Project state — memory, stages, backlog, parked
work, `OPS.md` — is not touched, and your own additions inside `.claude/`
come across. Old `.claude.bak.*` backups can be pruned freely.

### How you learn an update exists

A `SessionStart` hook compares `.claude/VERSION` against a kernel copy lying
nearby (the `keel/` folder in the project, or `$KEEL_HOME`) and against the
latest [GitHub release](https://github.com/bogdanov-igor/keel/releases).
Something strictly newer — one line, saying whether to re-run the installer
from the folder already next to the project or to download the release; you
are current — no line at all, and the normal case costs zero tokens.

The GitHub lookup is cached for 24 hours on a good answer and an hour on a
bad one, so a session started on a train or behind a firewall pays curl's
3-second ceiling once, not at every start. With neither `XDG_CACHE_HOME` nor
`HOME` set the cache has nowhere to live: the release check is skipped, the
local sources keep working. Every failure path exits silently, and the check
cannot block a session.

| Switch | Effect |
|---|---|
| `update_check` in `keel.json` | `"enabled": false` turns the check off for this project; the same block holds `repo` and `interval_hours`. |
| `KEEL_NO_UPDATE_CHECK=1` | The hook exits immediately. For CI and machines with no network. |
| `KEEL_HOME` | Path to a keel repo or an unpacked kernel. Its `VERSION` is compared with the installed one, so a build you made yourself is announced like a release. |
| `KEEL_SECRETS_FILE` | Where the leak hook reads secret values from, when they do not live in the project's `.secrets.env`. |

## Building the archive (maintainers)

```sh
bash build-archive.sh    # → dist/keel_<version>.tgz + .sha256
```

`build-archive.sh` is not shipped inside the archive. It checks every input
by name before anything runs or is copied — `ROADMAP.md` joined the archive
in 1.8.0, the build's fixture did not get it, and the failure surfaced as
`sha256: No such file`, naming neither the file nor the step that wanted it.
Then `test/run.sh`: over 400 self-tests over the kernel's scripts, offline,
on throwaway fixtures, and no build at all if one fails. Then the fresh
archive is unpacked into a temp directory and really installed, and the
result checked end to end — the contract, the seeds, hook and script
permissions, the version stamp, docs in both languages with the Russian
diagram, the licence, `settings.json` parsing, and the update check staying
silent against its own version. The work area is kept on failure.

The build is hermetic: its own cache instead of the real `~/.cache`, no
network. I pack the archive with `python3` (`tarfile` + `gzip`) instead of
the system `tar`: ustar format, entries ordered by the bytes of their path,
uid/gid 0 with empty owner names, 0755 on directories and executables and
0644 on everything else, mtime 2020-01-01 UTC, gzip with no file name or
timestamp in the stream. So the same tag gives the same sha256 on any
machine — bsdtar and GNU tar pad the octal header fields differently.
Unpacking is a plain `tar -xzf`.
