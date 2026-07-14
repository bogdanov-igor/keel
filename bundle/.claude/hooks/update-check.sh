#!/usr/bin/env bash
# SessionStart hook: tell the owner when a newer Keel exists upstream.
#
# Contract: print ONE line, and only when an update is actually available.
# Everything the hook prints enters the model's context every session, so
# silence is the default and the happy path costs zero tokens.
#
# Never blocks a session: no network, no cache dir, rate-limited API, bad JSON,
# unparseable version — every failure path exits 0 in silence.
set -uo pipefail

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
CONF="$PROJECT/keel.json"
LOCAL_VER_FILE="$PROJECT/.claude/VERSION"

# Opt-out: "update_check": { "enabled": false } in keel.json.
if [ -f "$CONF" ] && tr -d ' \n\t' < "$CONF" | grep -q '"enabled":false'; then
  exit 0
fi

[ -f "$LOCAL_VER_FILE" ] || exit 0
LOCAL="$(tr -d '[:space:]' < "$LOCAL_VER_FILE")"
[ -n "$LOCAL" ] || exit 0

REPO="bogdanov-igor/keel"
if [ -f "$CONF" ]; then
  R="$(tr -d ' \n\t' < "$CONF" | sed -n 's/.*"repo":"\([^"]*\)".*/\1/p')"
  [ -n "$R" ] && REPO="$R"
fi

INTERVAL_H=24
if [ -f "$CONF" ]; then
  I="$(tr -d ' \n\t' < "$CONF" | sed -n 's/.*"interval_hours":\([0-9]*\).*/\1/p')"
  [ -n "$I" ] && INTERVAL_H="$I"
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keel"
CACHE="$CACHE_DIR/latest-${REPO//\//-}"
mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

now="$(date +%s)"
fresh=0
if [ -f "$CACHE" ]; then
  ts="$(sed -n 1p "$CACHE" 2>/dev/null)"
  case "$ts" in
    ''|*[!0-9]*) ts=0 ;;
  esac
  [ $(( now - ts )) -lt $(( INTERVAL_H * 3600 )) ] && fresh=1
fi

if [ "$fresh" -eq 1 ]; then
  REMOTE="$(sed -n 2p "$CACHE" 2>/dev/null)"
else
  # 3s ceiling: a slow network must never delay a session start.
  REMOTE="$(curl -fsSL -m 3 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$REMOTE" ] && printf '%s\n%s\n' "$now" "$REMOTE" > "$CACHE" 2>/dev/null
fi

[ -n "${REMOTE:-}" ] || exit 0
[ "$REMOTE" = "$LOCAL" ] && exit 0

# Numeric semver compare: only speak up when upstream is strictly newer.
# A local build ahead of the last release (or any unparseable pair) stays quiet.
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

if newer "$REMOTE" "$LOCAL"; then
  printf 'keel: version %s is available (installed: %s). To update: download the release, then `bash keel/install.sh` from the project root — kernel files are replaced, project state is untouched. Mention this to the owner once, then continue.\n' \
    "$REMOTE" "$LOCAL"
fi
exit 0
