---
name: safe-dev-server
description: Owns every persistent process launch — dev servers, watchers, preview servers go through the safe-run launcher with a process-tree circuit breaker and whole-group teardown. The forkbomb hook denies raw launches; this is the sanctioned path.
allowed-tools: Bash(bash .claude/skills/safe-dev-server/safe-run.sh *)
---

# Safe dev server

Persistent processes launched raw can orphan, leak, and fork-storm the
host — this machine has been hung by exactly that. The forkbomb hook
(`.claude/hooks/forkbomb-guard.sh`) denies raw `next dev`, `vite`,
`--watch`, `serve` and friends; one-shot commands (`next build`,
`vitest run`, `tsc`) pass through untouched.

## Process model — read before launching

`safe-run.sh` is a foreground supervisor by design: it launches the
command as its own process group, probes `--url` for a healthy start,
then keeps supervising; when the supervisor exits — TTL expiry, breaker
trip, or being killed — its EXIT trap reaps the entire group. Launcher
alive ⇔ server alive. That equivalence is the no-strays guarantee, and
it means the launcher must run as a background task, never as a plain
blocking Bash call (a blocking call hits the tool timeout, which kills
the supervisor and takes the server down with it).

## Launch

Run with the Bash tool's `run_in_background: true`:

```sh
bash .claude/skills/safe-dev-server/safe-run.sh \
  --label web --ttl 60 --url http://127.0.0.1:3000/ -- pnpm dev
```

- `--label <name>` — names the job and its log:
  `${TMPDIR:-/tmp}/safe-run-<label>.log`.
- `--ttl <min>` — hard lifetime; at expiry the supervisor exits and
  reaps the group, so an abandoned session cannot strand a server.
- `--url <url>` — healthy-start probe: the supervisor waits for a
  response and reports ready or kills the group.
- After `--` — the real command, unquoted.

The breaker caps the descendant process tree and memory (thresholds
from `keel.json:circuit_breaker`, sane fallbacks built in) and reaps
the whole group on breach — a runaway rebuild loop dies alone instead
of taking the host with it.

## Daemonizing commands — the launcher cannot supervise them

Some CLIs detach and exit. `astro preview` (Astro 7) forks a daemon
and returns, so the supervisor reports `child exited rc=0` and reaps
an empty group while the port keeps answering: launcher dead, server
alive. That is exactly the orphan safe-run exists to prevent, and no
TTL or breaker will ever reach it.

Check the command before launching it, and for static output serve the
directory in the foreground instead of using the framework's preview
daemon:

```sh
bash .claude/skills/safe-dev-server/safe-run.sh \
  --label preview --url http://127.0.0.1:4321/ -- \
  python3 -m http.server 4321 --bind 127.0.0.1 --directory dist
```

A daemon that already escaped belongs to no group of ours — stop it
with its own stop command (`npx astro preview stop`), then relaunch in
the foreground.

When the breaker trips on host memory pressure, do not raise its caps
to get a server: QA does not need one (skill `qa-browser` serves the
built output through Playwright).

## Ready / inspect / stop

- Ready: request `--url` (curl) or read the log head — the supervisor
  logs the healthy-start verdict there.
- Stop early: kill the supervisor —
  `pkill -f 'safe-run.sh.*--label web'` — its EXIT trap tears down the
  whole group. Or let the TTL do it.
- `--self-test` prints resolved thresholds and the launch branch
  without launching; `--preflight` is a report-only host-hygiene probe.

Re-launch after a config change rather than reusing a stale server —
a server older than the code it serves is the classic false-negative.
