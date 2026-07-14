#!/usr/bin/env bash
# PreToolUse forkbomb circuit breaker: deny any Bash command that launches a
# PERSISTENT process (dev server / watcher / browser driver) unless it is
# wrapped by the safe-dev-server `safe-run` launcher. The launcher caps the
# descendant process tree + host memory, enforces a healthy start, and reaps
# the whole process group so a runaway cannot forkbomb the host. One-shot
# builds/tests (next build / vitest run / tsc) pass straight through.
# Matcher (settings.json): Bash. The full hook JSON (tool_input) is on stdin.
set -uo pipefail

payload="$(cat)"

# Extract the command robustly: jq if present, else python3, else give up (allow).
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && cmd="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("command","") or "")' 2>/dev/null || true)"
[ -z "$cmd" ] && { echo '{}'; exit 0; }

MSG="Blocked: this is a persistent process launch (dev server / watcher / browser driver) and must run through the circuit breaker. Re-run it via the safe-dev-server skill launcher: safe-run --label <name> --ttl <min> --url http://127.0.0.1:<port>/ -- <cmd>. It caps the descendant process tree and host memory, enforces healthy-start, and reaps the whole process group so a runaway cannot forkbomb the host (contract: forkbomb circuit breaker). One-shot commands (next build / vitest run / tsc) are unaffected."

deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$MSG"; exit 0; }
allow() { echo '{}'; exit 0; }

# ===========================================================================
# CLASSIFIER (root-rewrite). Decision: a command is PERSISTENT (-> DENY) iff
# ANY of its simple-command segments (after wrapper-recursion) launches a
# long-lived server/watcher/browser-driver. Everything else falls through to
# ALLOW — there is NO separate one-shot allow list, so a build segment can no
# longer SHADOW a dev segment in a multiline/compound command. Classification
# is HEAD-based (first effective token after stripping env-assignments and
# transparent wrappers), which kills the `grep -rn serve .` false-positive
# (head=grep, neutral) while still denying `next dev`, `vite`, `--watch`, etc.
# ===========================================================================

# 1. WRAPPED: already guarded by the safe-run launcher (or the env opt-out).
#    Checked on the RAW command so quoting can never hide the wrapper. The
#    token must be an invocation (safe-run / safe-run.sh followed by space or
#    EOL) — a mere reference like safe-run-web.log does not disarm the guard.
if printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_-])safe-run(\.sh)?([[:space:]]|$)'; then allow; fi
if printf '%s' "$cmd" | grep -Eq '(^|[ ;&|=])KEEL_SAFE_RUN=1'; then allow; fi

# 2. NORMALIZE: fold quoting/grouping/control chars to single spaces, but KEEP
#    newline (\n) intact so segment-splitting stays line-aware. SET1 = double
#    quote, single quote, backtick, '(', ')', '{', '}', backslash, TAB, CR,
#    vertical-tab, form-feed (12 chars) -> SET2 = 12 spaces. BSD/GNU tr both
#    expand the \t \r \v \f escapes. The squeeze (tr -s) then collapses runs
#    of spaces so token boundaries are clean for per-segment word-splitting.
norm="$(printf '%s' "$cmd" | tr '"'"'"'`(){}\\\t\r\v\f' '            ' | tr -s ' ')"

# is_persistent_head <head> <rest-of-tokens...> -> rc 0 if PERSISTENT.
# All matching is on the HEAD plus its sub-tokens (positional/space-delimited),
# never an arbitrary substring of the whole command.
is_persistent_head() {
  local head="$1"; shift
  local rest="$*"
  # whitespace-padded haystack so ` token ` membership tests are exact.
  local toks=" $rest "
  has() { case "$toks" in (*" $1 "*) return 0;; (*) return 1;; esac; }
  # `--help` / `--version` are universal one-shots: a head asked to print
  # usage or its version never daemonizes, so they win over every persistent
  # head (incl. a `--watch` typo).
  has '--help' && return 1
  has '--version' && return 1
  # --watch anywhere in the segment turns any head into a watcher.
  has '--watch' && return 0
  case "$head" in
    next)
      # next dev / next start -> persistent ; next build -> not.
      has dev && return 0; has start && return 0; return 1 ;;
    npm|pnpm|yarn|bun)
      # `<pm> [run] (dev|start|serve)` persistent; build is not. The optional
      # `run` keyword is transparent. Colon-suffixed package scripts
      # (dev:web, start:dev) count as their base verb.
      local t
      for t in $rest; do case "$t" in build|build:*) return 1 ;; esac; done
      for t in $rest; do
        case "$t" in dev|dev:*|start|start:*|serve|serve:*|preview|preview:*) return 0 ;; esac
      done
      return 1 ;;
    vite)
      # bare `vite`, or vite dev/serve/preview -> persistent; vite build -> not.
      has build && return 1
      return 0 ;;
    webpack)
      has serve && return 0; return 1 ;;
    webpack-dev-server|nodemon|http-server|serve)
      return 0 ;;
    playwright)
      # persistent unless --help or an install sub-token.
      has '--help' && return 1
      has install && return 1
      return 0 ;;
    @playwright/cli)
      has '--help' && return 1
      has install && return 1
      return 0 ;;
    uvicorn|gunicorn)
      return 0 ;;
    flask)
      has run && return 0; return 1 ;;
    rails)
      has server && return 0; has s && return 0; return 1 ;;
    php)
      has -S && return 0; return 1 ;;
    python|python3)
      has http.server && return 0; return 1 ;;
    *)
      return 1 ;;
  esac
}

# classify_segment <segment-string> <depth> -> rc 0 if PERSISTENT.
# Strips env-assignments + transparent wrappers to find the effective head,
# then either recurses into a shell -c/-lc script string or classifies by head.
classify_segment() {
  local seg="$1" depth="${2:-0}"
  # word-split the (already space-folded) segment.
  set -- $seg
  [ "$#" -eq 0 ] && return 1
  # strip leading env-assignments (FOO=bar) and transparent wrappers.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*) shift; continue ;;
      env|command|exec|time|nice|sudo|bunx|nohup) shift; continue ;;
      setsid)
        shift
        case "${1:-}" in -f|-w|--fork|--wait) shift ;; esac
        continue ;;
      timeout)
        shift
        # drop timeout's own options and the duration (e.g. -k 5 300 / 30s).
        while [ "$#" -gt 0 ]; do
          case "$1" in -*|[0-9]*) shift ;; *) break ;; esac
        done
        continue ;;
      npx)
        shift
        # npx -y / npx --yes is still transparent.
        case "${1:-}" in (-y|--yes) shift;; esac
        continue ;;
      *) break ;;
    esac
  done
  [ "$#" -eq 0 ] && return 1
  local head="$1"; shift
  local rest="$*"

  # RECURSE: a shell with a -c / -lc flag — the remainder (the script string,
  # already quote-folded to bare tokens) is itself a command. Re-split it on
  # separators and re-classify. Cap depth at 3 to avoid loops.
  case "$head" in
    bash|sh|zsh|dash)
      case " $rest " in
        *" -c "*|*" -lc "*|*" -lc"*|*" -c"*)
          if [ "$depth" -lt 3 ]; then
            # The script string is everything AFTER this shell's own leading
            # option block. Strip ONLY the leading option tokens (-c, -lc, -l,
            # -i, …) of THIS wrapper; the first non-option token begins the
            # inner script and everything from there on is passed verbatim so a
            # nested `bash -c next dev` keeps its own `-c` for re-recursion.
            local inner="" started=0 t
            for t in $rest; do
              if [ "$started" -eq 0 ]; then
                case "$t" in (-*) continue ;; (*) started=1 ;; esac
              fi
              inner="$inner $t"
            done
            classify_command "$inner" "$((depth + 1))" && return 0
            return 1
          fi
          ;;
      esac
      ;;
  esac

  is_persistent_head "$head" $rest && return 0
  return 1
}

# classify_command <normalized-command> <depth> -> rc 0 if ANY segment persistent.
# Splits on any run of separators: newline, ';', '&', '|' (so && || ;; | split).
classify_command() {
  local input="$1" depth="${2:-0}"
  # translate every separator char to newline, then iterate lines.
  local lined seg
  lined="$(printf '%s' "$input" | tr ';&|\n' '\n\n\n\n')"
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    classify_segment "$seg" "$depth" && return 0
  done <<EOF
$lined
EOF
  return 1
}

# 3-6. Iterate all segments; any persistent (incl. recursed) -> DENY, else ALLOW.
if classify_command "$norm" 0; then deny; fi
allow
