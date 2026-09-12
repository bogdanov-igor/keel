#!/usr/bin/env bash
# Kernel self-tests: exercise the shipped scripts against throwaway fixtures.
#
#   bash test/run.sh
#
# Every case encodes a bug that actually shipped and was caught by hand, or a
# property the docs promise. A green build is not a release gate; this is.
# Runs offline, in temp dirs, touches nothing outside them. Non-zero exit on
# any failure. Cases live in test/cases/*.sh, one file per zone, sourced into
# this shell in name order so the counters and the temp dir are shared.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
SK="$REPO/bundle/.claude/skills"
HK="$REPO/bundle/.claude/hooks"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }
has()    { case "$2" in *"$1"*) ok;; *) bad "$3 (missing: $1)";; esac; }
hasnt()  { case "$2" in *"$1"*) bad "$3 (unexpected: $1)";; *) ok;; esac; }
section(){ printf '\n• %s\n' "$1"; }

for c in "$REPO/test/cases"/*.sh; do
  . "$c"
done

printf '\n─────────────\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
