# Install & update

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `bash`, `tar`, `curl` — present on macOS and Linux out of the box
- Optional: Playwright for browser QA (`npx playwright install chromium`);
  `uvx` for the seeded serena MCP; `npx` for context7

Keel itself needs no runtime services: no MCP server of its own, no daemon,
no index to build. The kernel is shell and markdown.

## Quickstart

**1.** Download `keel_1.6.0.tgz` and `keel_1.6.0.tgz.sha256` from
[Releases](https://github.com/bogdanov-igor/keel/releases/latest) into your
project folder.

**2.** Open the project in Claude Code and say:

> Install keel from the archive in this folder: verify the sha256, unpack it,
> run `keel/install.sh`, then tell me what it set up.

**3.** If the project ran SkillForge — or any system before this one — add:

> Clean up the leftovers from the old system and propose the re-audit.

Claude verifies the checksum, unpacks, installs and reports. The cleanup
step quarantines the predecessor's machinery without deleting anything and
files a re-audit into `BACKLOG.md` — see [migration](migration.md).

## By hand

Two paths, both running the same installer.

### From the archive

You have two files side by side: `keel_1.6.0.tgz` and its `.sha256` sidecar.

```sh
cd /path/to/project                 # copy both files here
shasum -c keel_1.6.0.tgz.sha256     # verify integrity first: expect "OK"
tar -xzf keel_1.6.0.tgz
bash keel/install.sh                # no argument = install into this directory
```

The unpacked `keel/` folder can stay in the project (re-running `install.sh`
updates the kernel later) or be deleted. If it stays, add `keel/` and the
`.tgz` to `.gitignore`.

### From the source repo

```sh
git clone https://github.com/bogdanov-igor/keel.git
bash keel/install.sh /path/to/project
```

## What the installer does

| Action | Detail |
|---|---|
| Installs the kernel | Copies `bundle/.claude` in as a real directory, never a symlink — symlinks break memory paths and hook resolution. An existing `.claude` is moved to `.claude.bak.<timestamp>` first. |
| Preserves your skills | Skill directories the kernel does not ship are carried over from the previous `.claude`, including skills nested under a legacy SkillForge `skills/_user/`. A skill you wrote yourself is never lost. |
| Seeds project state | Creates `memory/`, `stages/`, `BACKLOG.md`, `PARKED.md`, `OPS.md`, `keel.json`, `.mcp.json` — only where absent. Existing project state is never overwritten. |
| Protects secrets | Adds `.secrets.env` and `.qa/` to `.gitignore`. |
| Stamps the version | Writes `.claude/VERSION`, which the update check reads. |
| Detects residue | Reports SkillForge leftovers and points at the `migrate` skill. It moves nothing itself — an installer does not touch your files. |

## Updating

The simplest path: download the new archive into the project folder and say:

> Update keel from the archive in this folder.

By hand it is the same command as the install. Get the newer keel folder
(download the release, or `git pull`) and run:

```sh
cd /path/to/project
bash keel/install.sh
```

Kernel files are replaced. Project state — memory, stages, backlog, parked
work, your own skills — is not touched. Old `.claude.bak.*` backups can be
pruned freely.

### How you learn an update exists

A `SessionStart` hook compares `.claude/VERSION` against the latest release
upstream and prints one line when a newer version exists, then stays quiet
for 24 hours (cached in `~/.cache/keel/`). When you are current it prints
nothing at all, so the normal case costs zero tokens.

The check never blocks a session: the network call has a 3-second ceiling,
and every failure path — offline, rate-limited, unparseable — exits
silently.

Turn it off in `keel.json`:

```json
{
  "update_check": {
    "enabled": false,
    "repo": "bogdanov-igor/keel",
    "interval_hours": 24
  }
}
```

## Building the archive (maintainers)

```sh
bash build-archive.sh    # → dist/keel_<version>.tgz + .sha256
```

`build-archive.sh` is not shipped inside the archive. It runs the kernel's
own test suite (`test/run.sh`) first and refuses to build if anything fails.
It then verifies the result end to end: unpacks the tgz it just built into a
temp directory, runs a real install, and checks the contract, the seeded
files, hook permissions, the version stamp, docs, the licence, and that the
update check stays silent against its own version. On failure the work area
is kept for inspection.
