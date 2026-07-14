#!/usr/bin/env bash
# safe-dev-server :: safe-run — guarded launcher.
#
# The forkbomb-guard hook routes persistent launches here. It runs the wrapped
# command as its OWN process-group leader, watches a circuit-breaker sensor over
# the WHOLE descendant tree (any binary — node, Chromium, whatever), and on any
# trip tears the entire group down atomically so NO orphans survive.
#
# Usage:
#   safe-run --label <name> --ttl <min> --url <url> -- <cmd...>
#   safe-run --self-test            # print resolved thresholds + launch branch; no real launch
#   safe-run --preflight            # report-only host-hygiene probe; mutates nothing, exit 0
#   safe-run ... --max-procs <n>    # test-only override of max_tree_procs (fork-storm proof)
#
# Persistent-vs-one-shot is auto-detected from the wrapped command to decide
# whether healthy-start applies (one-shot commands skip it).
#
# Log: ${TMPDIR:-/tmp}/safe-run-<label>.log  — always under a temp dir, never
# an absolute path outside /tmp.
set -uo pipefail

# ---------------------------------------------------------------------------
# KERNEL root resolution — identical strategy to .claude/hooks/leak-guard.sh.
# ---------------------------------------------------------------------------
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  HOST="$(cd "$CLAUDE_PROJECT_DIR" && pwd -P)"
else
  # skills/<name>/safe-run.sh -> skills -> .claude -> kernel/host
  HOST="$(cd "$SELF_DIR/../../.." && pwd -P)"
fi
KERNEL="$HOST"
if [ ! -f "$KERNEL/keel.json" ] && [ -d "$HOST/.claude" ]; then
  cand="$(dirname "$(cd "$HOST/.claude" && pwd -P)")"
  [ -f "$cand/keel.json" ] && KERNEL="$cand"
fi
if [ ! -f "$KERNEL/keel.json" ]; then
  for d in "$HOST"/*/; do
    [ -f "${d}keel.json" ] && { KERNEL="${d%/}"; break; }
  done
fi
# Also try walking up from SELF_DIR (covers real-copy topology where the hook
# env var is absent and .claude lives directly inside the kernel).
if [ ! -f "$KERNEL/keel.json" ]; then
  cand="$(cd "$SELF_DIR/../../.." && pwd -P)"
  [ -f "$cand/keel.json" ] && KERNEL="$cand"
fi
KEEL_JSON="$KERNEL/keel.json"

# ---------------------------------------------------------------------------
# Thresholds — from keel.json:circuit_breaker via jq, with hard fallbacks.
# ---------------------------------------------------------------------------
MAX_TREE_PROCS=80
TREE_RSS_MB_THRESHOLD=4096
HOST_MEM_PRESSURE_LEVEL=2
HEALTHY_START_SECONDS=45
if command -v jq >/dev/null 2>&1 && [ -f "$KEEL_JSON" ]; then
  _v="$(jq -r '.circuit_breaker.max_tree_procs // empty' "$KEEL_JSON" 2>/dev/null)"; [ -n "$_v" ] && MAX_TREE_PROCS="$_v"
  _v="$(jq -r '.circuit_breaker.tree_rss_mb // empty' "$KEEL_JSON" 2>/dev/null)"; [ -n "$_v" ] && TREE_RSS_MB_THRESHOLD="$_v"
  _v="$(jq -r '.circuit_breaker.host_mem_pressure_level // empty' "$KEEL_JSON" 2>/dev/null)"; [ -n "$_v" ] && HOST_MEM_PRESSURE_LEVEL="$_v"
  _v="$(jq -r '.circuit_breaker.healthy_start_seconds // empty' "$KEEL_JSON" 2>/dev/null)"; [ -n "$_v" ] && HEALTHY_START_SECONDS="$_v"
fi

# maxproc guard ceiling (macOS). 0 => guard disabled (e.g. Linux / unavailable).
MAXPROC="$(sysctl -n kern.maxprocperuid 2>/dev/null || echo 0)"
case "$MAXPROC" in (*[!0-9]*|'') MAXPROC=0 ;; esac

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
LABEL=""
TTL_MIN=""
URL=""
MODE="run"            # run | self-test | preflight
CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --label)      LABEL="${2:-}"; shift 2 ;;
    --ttl)        TTL_MIN="${2:-}"; shift 2 ;;
    --url)        URL="${2:-}"; shift 2 ;;
    --max-procs)  MAX_TREE_PROCS="${2:-}"; shift 2 ;;   # test-only override
    --self-test)  MODE="self-test"; shift ;;
    --preflight)  MODE="preflight"; shift ;;
    --)           shift; CMD=("$@"); break ;;
    *)            echo "safe-run: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$LABEL" ] && LABEL="job"
# Sanitize label for filesystem use (no path traversal into the log path).
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')"
LOG="${TMPDIR:-/tmp}/safe-run-${SAFE_LABEL}.log"

# ---------------------------------------------------------------------------
# Sensor primitives (verified copy-paste shell; macOS-primary, Linux-degrade).
# ---------------------------------------------------------------------------

# descendants <pid>: print EVERY descendant pid (any binary). pgrep -P recursive
# walk is primary; a `ps -axo pid=,ppid=` BFS is the no-pgrep fallback.
descendants() {
  local root="$1"
  if command -v pgrep >/dev/null 2>&1; then
    _desc_pgrep "$root"
  else
    _desc_ps "$root"
  fi
}
# NOTE: frontiers are newline-delimited STRINGS, not arrays — empty-array
# expansion under `set -u` aborts the walk on bash 3.2 (the macOS default),
# which would silently undercount the tree and defeat the breaker. Strings are
# safe to expand when empty.
_desc_pgrep() {
  local p kid frontier next
  frontier="$1"
  while [ -n "$frontier" ]; do
    next=""
    for p in $frontier; do
      for kid in $(pgrep -P "$p" 2>/dev/null); do
        echo "$kid"
        next="$next $kid"
      done
    done
    frontier="$next"
  done
}
_desc_ps() {
  # BFS over the full pid,ppid table — no pgrep needed.
  local root snap p kid frontier next
  root="$1"
  frontier="$1"
  snap="$(ps -axo pid=,ppid= 2>/dev/null)"
  while [ -n "$frontier" ]; do
    next=""
    for p in $frontier; do
      for kid in $(printf '%s\n' "$snap" | awk -v pp="$p" '$2==pp{print $1}'); do
        echo "$kid"
        next="$next $kid"
      done
    done
    frontier="$next"
  done
}

# tree_pids <root>: root + all descendants, one per line.
tree_pids() { echo "$1"; descendants "$1"; }

# tree_count <root>: number of pids in the tree (root included).
tree_count() { tree_pids "$1" | grep -c . ; }

# tree_rss_mb <root>: summed RSS of the whole tree, in MB (ps rss is KB).
tree_rss_mb() {
  local csv kb
  csv="$(tree_pids "$1" | paste -sd, -)"
  [ -z "$csv" ] && { echo 0; return; }
  kb="$(ps -o rss= -p "$csv" 2>/dev/null | awk '{s+=$1}END{print s+0}')"
  echo "$((kb/1024))"
}

# host_pressure: macOS memorystatus level (1 normal / 2 warn / 4 critical).
# Feature-detected; Linux returns 0 so the pressure trip is skipped there.
host_pressure() {
  local lvl
  lvl="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)"
  case "$lvl" in (*[!0-9]*|'') lvl=0 ;; esac
  echo "$lvl"
}

# ---------------------------------------------------------------------------
# Teardown — kill the whole process group atomically; zero orphans.
# ---------------------------------------------------------------------------
ROOT_PID=""
ROOT_PGID=""
SELF_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
TORNDOWN=0

teardown() {
  [ "$TORNDOWN" = 1 ] && return 0
  TORNDOWN=1
  # Group kill is correct only if the child became its OWN pgid leader.
  if [ -n "$ROOT_PGID" ] && [ "$ROOT_PGID" != "$SELF_PGID" ]; then
    kill -TERM -- "-$ROOT_PGID" 2>/dev/null
    local i=0
    while [ "$i" -lt 20 ]; do
      kill -0 -- "-$ROOT_PGID" 2>/dev/null || break
      perl -e 'select(undef,undef,undef,0.1)' 2>/dev/null || true
      i=$((i+1))
    done
    kill -KILL -- "-$ROOT_PGID" 2>/dev/null
  fi
  # Last-resort DFS leaf-first kill (in case group kill could not apply, e.g.
  # the child re-set its own pgid, or pgid never resolved).
  if [ -n "$ROOT_PID" ] && kill -0 "$ROOT_PID" 2>/dev/null; then
    _kill_tree_leaf_first "$ROOT_PID"
  fi
}

_kill_tree_leaf_first() {
  local root="$1" kids k
  kids="$(descendants "$root")"
  # Reverse so deepest (last discovered by BFS) die first.
  for k in $(printf '%s\n' "$kids" | tail -r 2>/dev/null || printf '%s\n' "$kids" | tac 2>/dev/null); do
    kill -TERM "$k" 2>/dev/null
  done
  kill -TERM "$root" 2>/dev/null
  perl -e 'select(undef,undef,undef,0.3)' 2>/dev/null || true
  for k in $kids; do kill -KILL "$k" 2>/dev/null; done
  kill -KILL "$root" 2>/dev/null
}

trap 'teardown' INT TERM EXIT

# trip <reason>: emit, tear down, and exit non-zero.
trip() {
  echo "BREAKER: $1" >&2
  teardown
  exit 1
}

# check_breaker: evaluate every sensor; trip on the first that exceeds.
check_breaker() {
  local tc rss lvl
  tc="$(tree_count "$ROOT_PID")"
  case "$tc" in (*[!0-9]*|'') tc=0 ;; esac

  if [ "$tc" -gt "$MAX_TREE_PROCS" ]; then
    trip "tree_procs=$tc > max_tree_procs=$MAX_TREE_PROCS"
  fi
  if [ "$MAXPROC" -gt 0 ] && [ "$tc" -gt "$((MAXPROC/2))" ]; then
    trip "tree_procs=$tc > maxproc/2=$((MAXPROC/2))"
  fi
  rss="$(tree_rss_mb "$ROOT_PID")"
  case "$rss" in (*[!0-9]*|'') rss=0 ;; esac
  if [ "$rss" -gt "$TREE_RSS_MB_THRESHOLD" ]; then
    trip "tree_rss_mb=$rss > tree_rss_mb_threshold=$TREE_RSS_MB_THRESHOLD"
  fi
  lvl="$(host_pressure)"
  if [ "$lvl" -ge "$HOST_MEM_PRESSURE_LEVEL" ] && [ "$HOST_MEM_PRESSURE_LEVEL" -gt 0 ] && [ "$lvl" -gt 0 ]; then
    # pressure level meanings are macOS-specific; only trip when a real level
    # was read (>0) AND it meets/exceeds the configured ceiling.
    if [ "$lvl" -ge "$HOST_MEM_PRESSURE_LEVEL" ]; then
      trip "host_mem_pressure=$lvl >= host_mem_pressure_level=$HOST_MEM_PRESSURE_LEVEL"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Launch-branch detection: setsid present -> setsid branch; else job-control.
# ---------------------------------------------------------------------------
launch_branch() {
  if command -v setsid >/dev/null 2>&1; then echo "setsid"; else echo "job-control"; fi
}

# ---------------------------------------------------------------------------
# Persistent-vs-one-shot heuristic from the wrapped command.
# ---------------------------------------------------------------------------
is_persistent() {
  # A --url given is the strongest persistence signal.
  [ -n "$URL" ] && return 0
  local joined="${CMD[*]:-}"
  case "$joined" in
    *" dev"*|*"dev-server"*|*" serve"*|*" start"*|*"watch"*|*"vite"*|*"next "*|\
    *"http-server"*|*"webpack-dev"*|*"nodemon"*|*"--watch"*|*"uvicorn"*|*"gunicorn"*|\
    *"rails server"*|*"rails s"*|*"php -S"*|*"python -m http.server"*)
      return 0 ;;
  esac
  return 1
}

# ===========================================================================
# MODE: self-test — print resolved thresholds + launch branch, assert the
# ROOT_PGID-separation logic, WITHOUT launching a real server.
# ===========================================================================
if [ "$MODE" = "self-test" ]; then
  echo "safe-run --self-test"
  echo "kernel_root            = $KERNEL"
  echo "keel.json        = $KEEL_JSON $( [ -f "$KEEL_JSON" ] && echo '(found)' || echo '(MISSING -> fallbacks)')"
  echo "max_tree_procs         = $MAX_TREE_PROCS"
  echo "tree_rss_mb            = $TREE_RSS_MB_THRESHOLD"
  echo "host_mem_pressure_level= $HOST_MEM_PRESSURE_LEVEL"
  echo "healthy_start_seconds  = $HEALTHY_START_SECONDS"
  echo "maxproc (kern.maxprocperuid) = $MAXPROC  -> maxproc/2 guard = $( [ "$MAXPROC" -gt 0 ] && echo "$((MAXPROC/2))" || echo 'disabled' )"
  echo "launch_branch          = $(launch_branch) $( command -v setsid >/dev/null 2>&1 && echo '(setsid present)' || echo '(setsid ABSENT -> set -m job-control, child becomes own pgid leader)')"
  echo "launcher_self_pgid     = $SELF_PGID"

  # Assert the PGID-separation guard WITHOUT launching the real wrapped command.
  # Spawn a trivial throwaway child under job control and confirm its pgid
  # differs from the launcher's own pgid — proving a negative-PGID kill would
  # target the child group, never the launcher.
  set -m
  ( exec sleep 5 ) &
  _probe_pid=$!
  set +m
  _probe_pgid="$(ps -o pgid= -p "$_probe_pid" 2>/dev/null | tr -d ' ')"
  echo "probe_child_pid        = $_probe_pid"
  echo "probe_child_pgid       = $_probe_pgid"
  kill -KILL "$_probe_pid" 2>/dev/null
  [ -n "$_probe_pgid" ] && kill -KILL -- "-$_probe_pgid" 2>/dev/null
  if [ -n "$_probe_pgid" ] && [ "$_probe_pgid" != "$SELF_PGID" ]; then
    echo "pgid_separation        = OK (child pgid $_probe_pgid != launcher pgid $SELF_PGID)"
  else
    echo "pgid_separation        = FAIL (child pgid '$_probe_pgid' == launcher pgid $SELF_PGID) -- group kill would hit the launcher" >&2
    TORNDOWN=1   # nothing real launched
    trap - INT TERM EXIT
    exit 1
  fi
  echo "SELF_TEST_OK"
  TORNDOWN=1     # nothing real to tear down
  trap - INT TERM EXIT
  exit 0
fi

# ===========================================================================
# MODE: preflight — FLAG-ONLY hygiene probe.
#
# REPORT-ONLY. This branch READS the host environment and prints what it finds
# to stderr, then ALWAYS exits 0. It is forbidden — by design and by U7's
# self-verify grep — from mutating ANYTHING: it never unloads a LaunchAgent via
# launchctl, never deletes a plist, never edits or appends to any rc file, and
# performs no global write. It only surfaces relics for the owner to act on.
#
#   (a) Orphaned LaunchAgents: any ~/Library/LaunchAgents/*.plist whose
#       ProgramArguments first element points at a path that no longer exists
#       on disk — the crash-loop relic shape (com.example.engine,
#       com.user.argus, …) that keeps relaunching a deleted binary.
#   (b) Cross-project env sourcing: any `source .../.env` or `. .../.env`
#       line in the owner's login rc files that pulls a foreign project's
#       environment into every shell.
# ===========================================================================
if [ "$MODE" = "preflight" ]; then
  # Everything below goes to stderr; the FD-2 redirect on the whole block keeps
  # the contract ("findings to stderr") even for the section headers.
  {
    echo "safe-run --preflight: hygiene probe — REPORT-ONLY, mutates nothing, exit 0"

    # --- (a) Orphaned LaunchAgents -----------------------------------------
    echo "--- (a) orphaned LaunchAgents (~/Library/LaunchAgents/*.plist with a missing ProgramArguments[0]) ---"
    _la_dir="$HOME/Library/LaunchAgents"
    _orphan_count=0
    if [ -d "$_la_dir" ]; then
      for _plist in "$_la_dir"/*.plist; do
        # Literal-glob guard: if nothing matched, the pattern stays unexpanded.
        [ -e "$_plist" ] || continue

        # Extract ProgramArguments[0] (or the scalar Program key) WITHOUT mutating
        # the file. PlistBuddy is read-only here (-c "Print ..."); on failure we
        # degrade to a plutil JSON dump, then to a grep heuristic. None write.
        _prog=""
        if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
          _prog="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$_plist" 2>/dev/null)"
          [ -z "$_prog" ] && _prog="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$_plist" 2>/dev/null)"
        fi
        if [ -z "$_prog" ] && command -v plutil >/dev/null 2>&1; then
          # plutil -convert json -o - reads to stdout; the source file is untouched.
          _prog="$(plutil -convert json -o - "$_plist" 2>/dev/null \
            | sed -n 's/.*"ProgramArguments":\[\"\([^"]*\)\".*/\1/p' \
            | head -n1)"
          if [ -z "$_prog" ]; then
            _prog="$(plutil -convert json -o - "$_plist" 2>/dev/null \
              | sed -n 's/.*"Program":"\([^"]*\)".*/\1/p' \
              | head -n1)"
          fi
        fi
        if [ -z "$_prog" ]; then
          # Last-resort heuristic: first <string> after a <key>ProgramArguments
          # or <key>Program. Pure read via grep/sed; never edits the plist.
          _prog="$(grep -A2 -E '<key>(ProgramArguments|Program)</key>' "$_plist" 2>/dev/null \
            | grep -oE '<string>[^<]*</string>' \
            | head -n1 \
            | sed -E 's#</?string>##g')"
        fi

        [ -z "$_prog" ] && continue
        # ProgramArguments[0] / Program is ALREADY a single argv element: the
        # whole executable path, spaces and all (e.g. ".../Application Support/
        # .../GoogleUpdater"). Do NOT split on whitespace — that would truncate a
        # space-bearing path and flag a present binary as missing (false orphan).
        _exe="$_prog"
        case "$_exe" in
          /*) ;;                 # absolute path — check it on disk
          *)  continue ;;        # non-absolute (e.g. "bash", relative) — skip; not an orphan signal
        esac
        if [ ! -e "$_exe" ]; then
          echo "ORPHAN: $_plist -> ProgramArguments[0]=$_exe (does not exist on disk)"
          _orphan_count=$((_orphan_count+1))
        fi
      done
    else
      echo "(no $_la_dir directory on this host — nothing to scan)"
    fi
    echo "orphaned-LaunchAgents found: $_orphan_count"
    echo "NOTE: report-only. To remove an orphan yourself: unload the agent (man launchctl: the bootout subcommand on gui/\$UID/<label>), then delete the plist by hand. safe-run will NOT do this for you."

    # --- (b) Cross-project .env sourcing in login rc files -----------------
    echo "--- (b) cross-project '.env' sourcing in login rc files ---"
    _env_hits=0
    for _rc in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile"; do
      [ -f "$_rc" ] || continue
      # Match `source <path>/.env` or `. <path>/.env` (with optional surrounding
      # quotes), skipping commented-out lines. grep is a pure read.
      _matches="$(grep -nE '^[[:space:]]*(source|\.)[[:space:]]+["'"'"']?[^[:space:]"'"'"']*/\.env\b' "$_rc" 2>/dev/null \
        | grep -vE '^[0-9]+:[[:space:]]*#')"
      if [ -n "$_matches" ]; then
        printf '%s\n' "$_matches" | while IFS= read -r _line; do
          echo "ENV-SOURCE: $_rc:$_line"
        done
        _n="$(printf '%s\n' "$_matches" | grep -c .)"
        _env_hits=$((_env_hits + _n))
      fi
    done
    echo "cross-project .env source lines found: $_env_hits"
    echo "NOTE: report-only. safe-run will NOT edit any rc file; remove unwanted source lines yourself."

    echo "safe-run --preflight: done (report-only, no mutation performed)"
  } >&2

  TORNDOWN=1
  trap - INT TERM EXIT
  exit 0
fi

# ===========================================================================
# MODE: run — guarded launch.
# ===========================================================================
if [ "${#CMD[@]}" -eq 0 ]; then
  echo "safe-run: no command after -- ; nothing to launch" >&2
  TORNDOWN=1
  trap - INT TERM EXIT
  exit 2
fi

{
  echo "=== safe-run $(date -u +%Y-%m-%dT%H:%M:%SZ) label=$LABEL ttl=${TTL_MIN:-none} url=${URL:-none} ==="
  echo "kernel=$KERNEL branch=$(launch_branch) max_tree_procs=$MAX_TREE_PROCS tree_rss_mb=$TREE_RSS_MB_THRESHOLD pressure>=$HOST_MEM_PRESSURE_LEVEL healthy=${HEALTHY_START_SECONDS}s"
  echo "cmd: ${CMD[*]}"
} >>"$LOG" 2>&1

# --- Launch the child as its OWN process-group leader. ---------------------
if command -v setsid >/dev/null 2>&1; then
  # Alternate branch: hosts WITH setsid.
  setsid "${CMD[@]}" >>"$LOG" 2>&1 &
  ROOT_PID=$!
else
  # Primary branch on THIS host (setsid absent): enable job control so the
  # '&' child is placed in its own new process group, becoming its own pgid
  # leader. ROOT_PGID then differs from the launcher's pgid.
  set -m
  "${CMD[@]}" >>"$LOG" 2>&1 &
  ROOT_PID=$!
  set +m
fi
ROOT_PGID="$(ps -o pgid= -p "$ROOT_PID" 2>/dev/null | tr -d ' ')"

# Safety: refuse to manage a group kill that would hit our own pgid.
if [ -z "$ROOT_PGID" ]; then
  echo "safe-run: could not resolve child pgid; falling back to pid-tree kill on teardown" >&2
elif [ "$ROOT_PGID" = "$SELF_PGID" ]; then
  echo "BREAKER: child pgid ($ROOT_PGID) == launcher pgid — refusing to manage (would self-kill)" >&2
  ROOT_PGID=""   # disable group kill; DFS pid-tree fallback still applies
  teardown
  exit 1
fi

echo "safe-run: launched pid=$ROOT_PID pgid=${ROOT_PGID:-?} (launcher pgid=$SELF_PGID) log=$LOG" >&2

# Immediate breaker sample: a runaway can begin forking the instant it starts,
# so check before we ever enter healthy-start / TTL waits.
check_breaker

# --- TTL deadline ----------------------------------------------------------
DEADLINE=0
if [ -n "$TTL_MIN" ]; then
  case "$TTL_MIN" in (*[!0-9]*|'') TTL_MIN=0 ;; esac
  [ "$TTL_MIN" -gt 0 ] && DEADLINE=$(( $(date +%s) + TTL_MIN*60 ))
fi

# --- Healthy-start gate (persistent launches only) -------------------------
if is_persistent && [ -n "$URL" ]; then
  hs_deadline=$(( $(date +%s) + HEALTHY_START_SECONDS ))
  healthy=0
  while [ "$(date +%s)" -lt "$hs_deadline" ]; do
    if ! kill -0 "$ROOT_PID" 2>/dev/null; then
      echo "BREAKER: process died during healthy-start (pid=$ROOT_PID)" >&2
      teardown
      exit 1
    fi
    if command -v curl >/dev/null 2>&1 && \
       curl -fsS -o /dev/null --max-time 2 "$URL" 2>/dev/null; then
      healthy=1
      break
    fi
    check_breaker   # keep the breaker live even while waiting to come up
    perl -e 'select(undef,undef,undef,0.5)' 2>/dev/null || true
  done
  if [ "$healthy" != 1 ]; then
    echo "BREAKER: healthy-start failed — $URL not 200 within ${HEALTHY_START_SECONDS}s" >&2
    teardown
    exit 1
  fi
  echo "safe-run: healthy-start OK ($URL responded 200)" >&2
elif is_persistent; then
  echo "safe-run: persistent launch without --url; skipping HTTP healthy-start (liveness-only)" >&2
else
  echo "safe-run: one-shot command; skipping healthy-start" >&2
fi

# --- Supervision loop: breaker + TTL + child-exit --------------------------
# Poll tightly (0.2s) so a fork-storm trips the breaker DURING ramp-up — before
# the tree fully explodes — rather than only after it has already spawned.
while kill -0 "$ROOT_PID" 2>/dev/null; do
  check_breaker
  if [ "$DEADLINE" -gt 0 ] && [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "safe-run: TTL (${TTL_MIN}m) reached — tearing down" >&2
    teardown
    exit 0
  fi
  perl -e 'select(undef,undef,undef,0.2)' 2>/dev/null || true
done

# Child exited on its own — reap its status and propagate.
wait "$ROOT_PID" 2>/dev/null
rc=$?
echo "safe-run: child exited rc=$rc" >&2
teardown
exit "$rc"
