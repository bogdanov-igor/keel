# Keel self-tests — 90-build-archive. Sourced from test/run.sh; REPO/SK/HK/TMP
# and the helpers ok/bad/has/hasnt/section come from there.
#
# The case runs a real build inside a copy of the repository. The release gate in
# that copy is stubbed: running the whole suite a second time is just these same
# cases again. That the gate is really called, and really cancels the build, is
# what the failing stub proves.

if [ "${KEEL_BUILD_GATE:-0}" = "1" ]; then
  section "build-archive — skipped (nested run from the build itself)"
else
  section "build-archive — distributable build"
  B="$TMP/ba"; mkdir -p "$B/xdg/keel"
  # The fixture is the repository by construction, not a list someone has to
  # remember to extend. ROADMAP.md joined the archive in 1.8.0 and this list did
  # not: the suite went red with `sha256: No such file`, which named neither the
  # file nor the step. Excluded is only what a build must never see — history,
  # a previous build's output, this checkout's own harness state, and any tgz.
  # A dirty working tree is copied as it stands: that is exactly what the gate
  # is asked about.
  for e in "$REPO"/* "$REPO"/.[!.]*; do
    [ -e "$e" ] || continue
    ba_name="${e##*/}"
    case "$ba_name" in .git|dist|.claude|.serena|node_modules|*.tgz) continue ;; esac
    cp -R "$e" "$B/$ba_name"
  done
  GATE="$B/test/run.sh"

  # Gate fails → nothing is packaged, and the build shows which line failed.
  printf '#!/usr/bin/env bash\necho "  FAIL: stub"\nprintf "\\n0 passed, 1 failed\\n"\nexit 1\n' > "$GATE"
  out="$(XDG_CACHE_HOME="$B/xdg" bash "$B/build-archive.sh" 2>&1)" && rc=0 || rc=$?
  [ "$rc" != "0" ] && ok || bad "a failed gate cancels the build"
  has "self-tests FAILED" "$out" "the build says the self-tests failed"
  has "FAIL: stub" "$out" "the build echoes the failing line of the suite"
  has "0 passed, 1 failed" "$out" "the build echoes the suite's final count"
  [ ! -d "$B/dist" ] && ok || bad "nothing packaged while the gate is red"

  printf '#!/usr/bin/env bash\nprintf "\\n0 passed, 0 failed\\n"\nexit 0\n' > "$GATE"
  # "GitHub already has a newer release" must not trip the build: its own cache
  # is hermetic and seeded, so an ambient one like this is simply ignored.
  printf '%s\n%s\n' "$(date +%s)" "9.9.9" > "$B/xdg/keel/latest-bogdanov-igor-keel"
  out="$(XDG_CACHE_HOME="$B/xdg" bash "$B/build-archive.sh" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = "0" ] && ok \
    || bad "build passes with a newer release in the ambient cache: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
  BVER="$(tr -d '[:space:]' < "$REPO/VERSION")"
  [ -f "$B/dist/keel_$BVER.tgz" ] && ok || bad "archive built"
  lst="$(TZ=UTC tar -tvf "$B/dist/keel_$BVER.tgz" 2>/dev/null)"
  hasnt "$(id -un)" "$lst" "tar headers carry no builder name"
  has "keel/install.sh" "$lst" "the archive carries the installer"
  # Owner and time are nailed down — 0/0 and 2020-01-01 UTC. Implementations
  # print them differently (GNU tar "0/0" and an ISO date, bsdtar "0 0" and
  # "Jan  1  2020"), so both spellings count.
  case "$lst" in *" 0/0 "*|*" 0 0 "*) ok ;; *) bad "owner in the headers is anonymised to 0/0" ;; esac
  case "$lst" in *"2020-01-01 00:00"*|*"Jan  1  2020"*) ok ;;
                 *) bad "file times pinned to 2020-01-01 UTC" ;; esac
  # The sha256 next to the archive is a receipt for the receiver: rebuilding the
  # same tag must give the same archive, or there is nothing to check against.
  sha="$(cut -d' ' -f1 < "$B/dist/keel_$BVER.tgz.sha256")"
  XDG_CACHE_HOME="$B/xdg" bash "$B/build-archive.sh" >/dev/null 2>&1
  [ "$sha" = "$(cut -d' ' -f1 < "$B/dist/keel_$BVER.tgz.sha256")" ] \
    && ok || bad "a rebuild produces the same sha256"

  # ── a declared input that is not there is named, not stumbled over ────────
  # The 1.8.0 symptom in full: the build kept going past a failed copy and the
  # suite reported `sha256: No such file` — the name of a file nobody asked for,
  # about a step that was never reached. The build now names the input it wanted.
  BM="$TMP/ba-missing"; cp -R "$B" "$BM"; rm -rf "$BM/dist"; rm -f "$BM/ROADMAP.md"
  out="$(XDG_CACHE_HOME="$BM/xdg" bash "$BM/build-archive.sh" 2>&1)" && rc=0 || rc=$?
  [ "$rc" != "0" ] && ok || bad "a missing build input cancels the build"
  has "keel: build input missing: ROADMAP.md" "$out" "the build names the input it could not find"
  ls "$BM"/dist/*.tgz >/dev/null 2>&1 && bad "nothing packaged when an input is missing" || ok

  # ── the same build under GNU tar: bytes do not depend on the tar ──────────
  # python3 does the packing and the receiver's tar is the only one that matters,
  # so a build under GNU tar owes the same bytes as one under bsdtar. The build's
  # own self-test also unpacks and installs with whichever tar comes first on PATH.
  GNUBIN="$(brew --prefix gnu-tar 2>/dev/null)/libexec/gnubin"
  if [ -x "$GNUBIN/tar" ]; then
    section "build-archive — under GNU tar"
    rm -rf "$B/dist"
    out="$(PATH="$GNUBIN:$PATH" XDG_CACHE_HOME="$B/xdg" bash "$B/build-archive.sh" 2>&1)" \
      && rc=0 || rc=$?
    [ "$rc" = "0" ] && ok \
      || bad "build and its self-test under GNU tar: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
    [ -f "$B/dist/keel_$BVER.tgz" ] && ok || bad "GNU tar: archive built"
    [ "$sha" = "$(cut -d' ' -f1 < "$B/dist/keel_$BVER.tgz.sha256")" ] \
      && ok || bad "GNU tar: same sha256 as under bsdtar"
    glst="$(PATH="$GNUBIN:$PATH" TZ=UTC tar -tvf "$B/dist/keel_$BVER.tgz" 2>/dev/null)"
    has " 0/0 " "$glst" "GNU tar: owner anonymised to 0/0"
    tar -tf "$B/dist/keel_$BVER.tgz" >/dev/null 2>&1 && ok \
      || bad "GNU tar: the archive reads back with the receiver's own tar"
  else
    section "build-archive — under GNU tar SKIPPED (no gnu-tar/gnubin)"
  fi
fi
