#!/usr/bin/env bash
# Build the distributable archive: dist/keel_<version>.tgz + .sha256 sidecar.
# The archive unpacks to a single keel/ folder; inside a project:
#   tar -xzf keel_<version>.tgz && bash keel/install.sh
# Usage: bash build-archive.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"

# Kernel self-tests gate the build. A script that fails its own test never ships —
# the last three releases each shipped a bug that only adversarial review caught.
if ! test_out="$(bash "$ROOT/test/run.sh" 2>&1)"; then
  printf '%s\n' "$test_out" | tail -12 >&2
  echo "keel: kernel self-tests FAILED — fix before building (bash test/run.sh)" >&2
  exit 1
fi
echo "self-tests: $(printf '%s' "$test_out" | tail -1)"

OUT="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/keel" "$OUT"
# Docs and licence ship inside the archive: whoever receives the tgz gets the
# full manual in both languages, offline, without visiting the repo.
cp "$ROOT/README.md" "$ROOT/README.ru.md" "$ROOT/LICENSE" "$ROOT/NOTICE" \
   "$ROOT/CHANGELOG.md" "$ROOT/VERSION" "$ROOT/install.sh" "$STAGE/keel/"
cp -R "$ROOT/bundle" "$STAGE/keel/bundle"
cp -R "$ROOT/docs" "$STAGE/keel/docs"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE/keel/install.sh"
find "$STAGE/keel/bundle" -name '*.sh' -exec chmod +x {} +

TGZ="$OUT/keel_${VER}.tgz"
tar -czf "$TGZ" -C "$STAGE" keel
( cd "$OUT" && shasum -a 256 "keel_${VER}.tgz" > "keel_${VER}.tgz.sha256" )

# Self-test: unpack into a temp dir and run the no-arg install for real.
T="$(mktemp -d)"
( cd "$T" && tar -xzf "$TGZ" && bash keel/install.sh >/dev/null )
fail() { echo "keel: archive self-test FAILED — $1 (work area kept at $T)" >&2; exit 1; }
[ -f "$T/.claude/CLAUDE.md" ]                     || fail "no contract"
[ -f "$T/OPS.md" ] && [ -f "$T/.mcp.json" ]       || fail "seeds missing"
[ -x "$T/.claude/hooks/forkbomb-guard.sh" ]       || fail "hooks not executable"
[ -x "$T/.claude/skills/migrate/sweep.sh" ]       || fail "migrate sweep not executable"
[ -x "$T/.claude/skills/recall/anchors.sh" ]      || fail "recall anchors not executable"
[ -x "$T/.claude/skills/memory-consolidation/graph.sh" ] || fail "memory graph not executable"
[ "$(cat "$T/.claude/VERSION")" = "$VER" ]        || fail "version not stamped for update-check"
[ -f "$T/keel/LICENSE" ] && [ -f "$T/keel/README.ru.md" ] \
  && [ -f "$T/keel/docs/ru/why-keel.md" ]         || fail "docs/licence not shipped in the archive"
[ "$(ls "$T/.claude/skills" | wc -l | tr -d ' ')" -ge 37 ] || fail "skill count too low"
# The tools the docs hand the reader must run from a fresh install, not just from the repo.
( cd "$T" && CLAUDE_PROJECT_DIR="$T" bash .claude/skills/recall/anchors.sh --check >/dev/null 2>&1 ) \
  || fail "recall --check does not run on a fresh install"
( cd "$T" && CLAUDE_PROJECT_DIR="$T" bash .claude/skills/memory-consolidation/graph.sh >/dev/null 2>&1 ) \
  || fail "memory graph does not run on a fresh install"
# The update-check hook must stay silent when the installed version is current.
out="$(cd "$T" && CLAUDE_PROJECT_DIR="$T" bash .claude/hooks/update-check.sh 2>/dev/null || true)"
case "$out" in
  *"is available"*) fail "update-check announced an update against its own version" ;;
esac
rm -rf "$T"

echo "built: $TGZ"
echo "       ${TGZ}.sha256"
echo "receiver verifies with: shasum -c keel_${VER}.tgz.sha256  (next to the tgz)"
