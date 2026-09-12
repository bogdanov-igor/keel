#!/usr/bin/env bash
# SessionStart hook: tell the owner when a newer Keel exists.
#
# Contract: print ONE line, and only when an update is actually available.
# Everything the hook prints enters the model's context every session, so
# silence is the default and the happy path costs zero tokens.
#
# Sources: local kernel copies (keel/ next to the project, $KEEL_HOME) and the
# GitHub releases API. Only the newest candidate is announced, and only when it
# is strictly newer than .claude/VERSION — a local build ahead of the last
# release stays quiet.
#
# Never blocks a session: no network, no cache dir (HOME and XDG_CACHE_HOME can
# both be unset), rate-limited API, bad JSON, unparseable version — every
# failure path exits 0 in silence.
set -uo pipefail
[ "${KEEL_NO_UPDATE_CHECK:-0}" = "1" ] && exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
CONF="$PROJECT/keel.json"
LOCAL_VER_FILE="$PROJECT/.claude/VERSION"

[ -f "$LOCAL_VER_FILE" ] || exit 0
LOCAL="$(tr -d '[:space:]' < "$LOCAL_VER_FILE" 2>/dev/null)"
[ -n "$LOCAL" ] || exit 0

# ── keel.json, read SCOPED to the update_check object ───────────────────────
# keel.json holds several objects and circuit_breaker has its own keys; a
# whole-file grep for "enabled": false once let an unrelated section switch the
# update check off. python3 does it properly when present; the fallback keeps
# only the substring that follows "update_check" and stops at its closing brace.
ENABLED=1
REPO="bogdanov-igor/keel"
INTERVAL_H=24

if [ -f "$CONF" ]; then
  conf=""
  conf="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
u = d.get("update_check")
if not isinstance(u, dict):
    sys.exit(1)
print("enabled=%d" % (0 if u.get("enabled") is False else 1))
print("repo=%s" % (u.get("repo") or ""))
h = u.get("interval_hours")
print("interval=%s" % (h if isinstance(h, int) and h > 0 else ""))
' "$CONF" 2>/dev/null)" || conf=""

  if [ -n "$conf" ]; then
    while IFS= read -r kv; do
      case "$kv" in
        enabled=0)   ENABLED=0 ;;
        repo=?*)     REPO="${kv#repo=}" ;;
        interval=?*) INTERVAL_H="${kv#interval=}" ;;
      esac
    done <<EOF
$conf
EOF
  else
    scope="$(tr -d ' \n\t' < "$CONF" 2>/dev/null | sed -n 's/.*"update_check"//p')"
    scope="${scope%%\}*}"
    case "$scope" in *'"enabled":false'*) ENABLED=0 ;; esac
    R="$(printf '%s' "$scope" | sed -n 's/.*"repo":"\([^"]*\)".*/\1/p')"
    [ -n "$R" ] && REPO="$R"
    I="$(printf '%s' "$scope" | sed -n 's/.*"interval_hours":\([0-9][0-9]*\).*/\1/p')"
    [ -n "$I" ] && INTERVAL_H="$I"
  fi
fi
[ "$ENABLED" -eq 1 ] || exit 0

# Numeric semver compare: is $1 strictly newer than $2?
newer() {
  local a="$1" b="$2" i ai bi
  local -a A B
  IFS=. read -r -a A <<< "${a%%-*}"
  IFS=. read -r -a B <<< "${b%%-*}"
  for i in 0 1 2; do
    ai="${A[i]:-0}"; bi="${B[i]:-0}"
    case "$ai$bi" in *[!0-9]*) return 1 ;; esac
    [ "$ai" -gt "$bi" ] && return 0
    [ "$ai" -lt "$bi" ] && return 1
  done
  return 1
}

best=""; best_src=""
consider() {
  local v="$1" src="$2"
  [ -n "$v" ] || return 0
  case "$v" in *[!0-9.a-zA-Z-]*) return 0 ;; esac
  if [ -z "$best" ] || newer "$v" "$best"; then best="$v"; best_src="$src"; fi
}

# Local sources: the keel/ folder next to the project (the tgz was refreshed but
# install.sh never re-run) and the kernel repo itself via $KEEL_HOME.
for src in "$PROJECT/keel/VERSION" "${KEEL_HOME:+$KEEL_HOME/VERSION}"; do
  [ -n "$src" ] && [ -f "$src" ] && consider "$(tr -d '[:space:]' < "$src" 2>/dev/null)" local
done

# GitHub releases, cached. The cache file is written on EVERY attempt: a failed
# fetch caches an empty answer for an hour (negative cache), so a session behind
# a firewall or on a train pays curl's 3s ceiling once, not on every start.
# Neither XDG_CACHE_HOME nor HOME need exist — then the cache has nowhere to
# live and the release check is simply skipped; local sources still work.
CACHE_HOME="${XDG_CACHE_HOME:-}"
[ -n "$CACHE_HOME" ] || CACHE_HOME="${HOME:+$HOME/.cache}"
if [ -n "$CACHE_HOME" ]; then
  CACHE_DIR="$CACHE_HOME/keel"
  CACHE="$CACHE_DIR/latest-${REPO//\//-}"
  if mkdir -p "$CACHE_DIR" 2>/dev/null; then
    now="$(date +%s)"; fresh=0; REMOTE=""
    if [ -f "$CACHE" ]; then
      ts="$(sed -n 1p "$CACHE" 2>/dev/null)"
      case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
      REMOTE="$(sed -n 2p "$CACHE" 2>/dev/null)"
      ttl=$(( INTERVAL_H * 3600 ))          # successful answer: config TTL
      [ -n "$REMOTE" ] || ttl=3600          # failed answer: retry in an hour
      [ $(( now - ts )) -lt "$ttl" ] && fresh=1
    fi
    if [ "$fresh" -ne 1 ]; then
      # 3s ceiling: a slow network must never delay a session start.
      REMOTE="$(curl -fsSL -m 3 \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
      printf '%s\n%s\n' "$now" "$REMOTE" > "$CACHE" 2>/dev/null
    fi
    consider "${REMOTE:-}" github
  fi
fi

[ -n "$best" ] || exit 0
newer "$best" "$LOCAL" || exit 0

if [ "$best_src" = "local" ]; then
  printf 'keel: version %s is available in keel/ next to this project (installed: %s) — run bash keel/install.sh from the project root.\n' \
    "$best" "$LOCAL"
else
  printf 'keel: version %s is available (installed: %s). To update: download the release, then `bash keel/install.sh` from the project root — kernel files are replaced, project state is untouched. Mention this to the owner once, then continue.\n' \
    "$best" "$LOCAL"
fi
exit 0
