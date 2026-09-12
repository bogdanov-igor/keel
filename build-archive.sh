#!/usr/bin/env bash
# Build the distributable archive: dist/keel_<version>.tgz + .sha256 sidecar.
# The archive unpacks to a single keel/ folder; inside a project:
#   tar -xzf keel_<version>.tgz && bash keel/install.sh
# Usage: bash build-archive.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT="$ROOT/dist"
STAGE="$(mktemp -d)"
CACHE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$CACHE"' EXIT

# The build is hermetic: no step writes to the real ~/.cache and no step needs
# the network. The update-check cache goes to a temp dir seeded with a
# deliberately ancient version, and the hook itself is switched off everywhere
# except the one assertion below that switches it back on. Without this the
# build broke the moment a release newer than the one being built appeared
# upstream — a green tree failing because of someone else's tag.
export XDG_CACHE_HOME="$CACHE"
export KEEL_NO_UPDATE_CHECK=1
mkdir -p "$CACHE/keel"
printf '%s\n%s\n' "$(date +%s)" "0.0.1" > "$CACHE/keel/latest-bogdanov-igor-keel"

# Every input is checked by name before anything runs, copies or is packed.
# ROADMAP.md joined the archive in 1.8.0 and the build's own fixture did not get
# it: the build ran on past the failed copy and the suite reported
# `sha256: No such file`, which names neither the missing file nor the step that
# needed it. A missing input is now named, and nothing else happens.
BUILD_FILES="README.md README.ru.md LICENSE NOTICE CHANGELOG.md ROADMAP.md VERSION install.sh"
BUILD_DIRS="bundle docs"
for f in $BUILD_FILES; do
  [ -f "$ROOT/$f" ] || { echo "keel: build input missing: $f" >&2; exit 1; }
done
for d in $BUILD_DIRS; do
  [ -d "$ROOT/$d" ] || { echo "keel: build input missing: $d" >&2; exit 1; }
done

# Kernel self-tests gate the build. A script that fails its own test never ships —
# the last three releases each shipped a bug that only adversarial review caught.
# KEEL_BUILD_GATE tells the build-archive case not to recurse into a build of its
# own; every other case runs in full.
if ! gate="$(KEEL_BUILD_GATE=1 bash "$ROOT/test/run.sh" 2>&1)"; then
  echo "keel: kernel self-tests FAILED — fix before building (bash test/run.sh)" >&2
  printf '%s\n' "$gate" | grep -E 'FAIL:|passed,' >&2
  exit 1
fi
echo "self-tests: $(printf '%s' "$gate" | tail -1)"

mkdir -p "$STAGE/keel" "$OUT"
# Docs and licence ship inside the archive: whoever receives the tgz gets the
# full manual in both languages, offline, without visiting the repo.
# The names were checked at the top of the build; nothing here can be missing.
for f in $BUILD_FILES; do cp "$ROOT/$f" "$STAGE/keel/"; done
for d in $BUILD_DIRS; do cp -R "$ROOT/$d" "$STAGE/keel/$d"; done
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE/keel/install.sh"
find "$STAGE/keel/bundle" -name '*.sh' -exec chmod +x {} +

TGZ="$OUT/keel_${VER}.tgz"
# Packing is done by python3 (stdlib tarfile+gzip), not the system tar. Branching
# on bsdtar/GNU tar produced different bytes from the same tree — implementations
# pad the octal header fields differently — so the sha256 was reproducible only
# within one OS. Everything that depended on the machine or the builder is nailed
# down here: ustar format, entries ordered by the bytes of their path, uid/gid 0
# with empty owner names (otherwise the builder's username rides along in the
# header), 0755 for directories and executables and 0644 for the rest, mtime
# 2020-01-01 UTC instead of the moment of cp, and a gzip stream with no filename,
# no timestamp and a fixed level. Any tar unpacks the result.
python3 - "$STAGE" "$TGZ" <<'PY'
import gzip, os, sys, tarfile

stage, out = sys.argv[1], sys.argv[2]
MTIME = 1577836800  # 2020-01-01 00:00:00 UTC

paths = []
for base, _dirs, files in os.walk(os.path.join(stage, "keel")):
    rel = os.path.relpath(base, stage)
    paths.append(rel)
    paths.extend(os.path.join(rel, f) for f in files)
paths.sort(key=lambda p: p.encode())

with open(out, "wb") as raw, \
     gzip.GzipFile(filename="", mode="wb", compresslevel=9, mtime=0, fileobj=raw) as gz, \
     tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tar:
    for rel in paths:
        full = os.path.join(stage, rel)
        st = os.stat(full)
        isdir = os.path.isdir(full)
        ti = tarfile.TarInfo(rel)
        ti.type = tarfile.DIRTYPE if isdir else tarfile.REGTYPE
        ti.mode = 0o755 if isdir or st.st_mode & 0o100 else 0o644
        ti.size = 0 if isdir else st.st_size
        ti.mtime = MTIME
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = ""
        if isdir:
            tar.addfile(ti)
        else:
            with open(full, "rb") as f:
                tar.addfile(ti, f)
PY
( cd "$OUT" && shasum -a 256 "keel_${VER}.tgz" > "keel_${VER}.tgz.sha256" )

# Self-test: unpack into a temp dir and run the no-arg install for real.
T="$(mktemp -d)"
( cd "$T" && tar -xzf "$TGZ" && bash keel/install.sh >/dev/null )
fail() { echo "keel: archive self-test FAILED — $1 (work area kept at $T)" >&2; exit 1; }
[ -f "$T/.claude/CLAUDE.md" ]                     || fail "no contract"
[ -f "$T/OPS.md" ]                                || fail "seeds missing"
# .mcp.json is seeded filtered to the servers this machine can launch, so on a
# build host without uvx and npx there is legitimately nothing to write.
if command -v uvx >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
  [ -f "$T/.mcp.json" ]                           || fail ".mcp.json not seeded"
fi
[ -x "$T/.claude/hooks/forkbomb-guard.sh" ]       || fail "hooks not executable"
[ -x "$T/.claude/skills/migrate/sweep.sh" ]       || fail "migrate sweep not executable"
[ -x "$T/.claude/skills/recall/anchors.sh" ]      || fail "recall anchors not executable"
[ -x "$T/.claude/skills/memory-consolidation/graph.sh" ] || fail "memory graph not executable"
[ "$(cat "$T/.claude/VERSION")" = "$VER" ]        || fail "version not stamped for update-check"
[ -f "$T/keel/LICENSE" ] && [ -f "$T/keel/README.ru.md" ] && [ -f "$T/keel/ROADMAP.md" ] \
  && [ -f "$T/keel/docs/ru/why-keel.md" ]         || fail "docs/licence/roadmap not shipped in the archive"
# The Russian architecture diagram is an image the Russian doc embeds: shipping
# the page without the asset gives the offline reader a broken picture.
[ -f "$T/keel/docs/assets/architecture.ru.svg" ]  || fail "ru architecture diagram not shipped"
grep -q 'architecture.ru.svg' "$T/keel/docs/ru/architecture.md" \
  || fail "docs/ru/architecture.md does not reference the ru diagram"
# The skill floor is whatever the bundle actually ships — a number written here
# by hand goes stale the first time a skill is added and stops meaning anything.
SKILL_N="$(find "$ROOT/bundle/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[ "$(ls "$T/.claude/skills" | wc -l | tr -d ' ')" -ge "$SKILL_N" ] || fail "skill count below the bundle's $SKILL_N"
# settings.json is read by the harness, not by a human: a syntax error there
# silently costs the project every hook it has.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/.claude/settings.json" \
  || fail "settings.json does not parse"
# Browser-QA scripts are shipped as ES modules and never run during this build;
# node --check is the cheapest proof they at least parse. Zero .mjs is fine.
if command -v node >/dev/null 2>&1; then
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    node --check "$m" >/dev/null 2>&1 || fail "node --check failed: ${m#$T/keel/}"
  done <<EOF
$(find "$T/keel/bundle" -name '*.mjs' 2>/dev/null)
EOF
fi
# The tools the docs hand the reader must run from a fresh install, not just from the repo.
( cd "$T" && CLAUDE_PROJECT_DIR="$T" bash .claude/skills/recall/anchors.sh --check >/dev/null 2>&1 ) \
  || fail "recall --check does not run on a fresh install"
( cd "$T" && CLAUDE_PROJECT_DIR="$T" bash .claude/skills/memory-consolidation/graph.sh >/dev/null 2>&1 ) \
  || fail "memory graph does not run on a fresh install"
# The update-check hook must stay silent when the installed version is current.
# Run against the seeded temp cache, with the build-wide mute lifted — otherwise
# this assertion would be testing the mute rather than the hook.
out="$(cd "$T" && CLAUDE_PROJECT_DIR="$T" KEEL_NO_UPDATE_CHECK=0 XDG_CACHE_HOME="$CACHE" \
       bash .claude/hooks/update-check.sh 2>/dev/null || true)"
case "$out" in
  *"is available"*) fail "update-check announced an update against its own version" ;;
esac
rm -rf "$T"

echo "built: $TGZ"
echo "       ${TGZ}.sha256"
echo "receiver verifies with: shasum -c keel_${VER}.tgz.sha256  (next to the tgz)"
