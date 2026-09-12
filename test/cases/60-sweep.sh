# Keel self-tests — 60-sweep. Sourced from test/run.sh; REPO/SK/HK/TMP and the
# helpers ok/bad/has/hasnt/section come from there.
#
# A positive control for `qa-browser`'s sweep.mjs. `node --check` in the build
# proves the file parses; it proves nothing about whether the checks fire. The
# incident the sweep exists for — a transparent layer over ONE button, which no
# screenshot shows and the old full-viewport overlay check never saw — is
# reproduced in test/fixtures/sweep.html, next to the three false positives
# measured on eight public sites while the per-control hit test was written: a
# link wrapped over two lines, a screen-reader-only skip link, a link cut off by
# a cell with overflow hidden. A sweep that reports the first and stays quiet
# about the other three is the whole promise; a sweep that reports everything is
# noise the owner learns to skip, which is how a check dies.
#
# Needs a directory from which `require('playwright')` resolves — the kernel
# ships no node_modules and never will — named by KEEL_PLAYWRIGHT_DIR, plus
# python3 to serve the fixture. Without them the case says so and skips, the
# way 90 does for gnu-tar.
sw_ready=0
if [ -n "${KEEL_PLAYWRIGHT_DIR:-}" ] && [ -d "${KEEL_PLAYWRIGHT_DIR:-/nonexistent}" ] \
   && command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  ( cd "$KEEL_PLAYWRIGHT_DIR" && node -e "require('playwright')" ) >/dev/null 2>&1 && sw_ready=1
fi

if [ "$sw_ready" != "1" ]; then
  section "qa-browser sweep — SKIPPED (set KEEL_PLAYWRIGHT_DIR to a dir where require('playwright') resolves)"
else
  section "qa-browser sweep — positive control on a fixture"
  # A port the kernel does not own: asked for and released, then bound by the
  # server a moment later. Bound to loopback only — a test that opens a port to
  # the network is a test that gets blamed for an incident it did not cause.
  sw_port="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  ( cd "$REPO/test/fixtures" && exec python3 -m http.server "$sw_port" --bind 127.0.0.1 ) \
    >/dev/null 2>&1 &
  sw_pid=$!

  sw_up=0; sw_try=0
  while [ "$sw_try" -lt 60 ]; do
    if python3 -c "import socket, sys
try:
    socket.create_connection(('127.0.0.1', $sw_port), 0.2).close()
except OSError:
    sys.exit(1)" 2>/dev/null; then sw_up=1; break; fi
    sw_try=$((sw_try + 1)); sleep 0.1
  done

  if [ "$sw_up" != "1" ]; then
    bad "the fixture server never came up on 127.0.0.1:$sw_port"
  else
    ( cd "$KEEL_PLAYWRIGHT_DIR" \
      && node "$REPO/bundle/.claude/skills/qa-browser/sweep.mjs" \
              "http://127.0.0.1:$sw_port/sweep.html" ) \
      > "$TMP/sweep.json" 2> "$TMP/sweep.err" && ok \
      || bad "sweep.mjs exited non-zero: $(tr '\n' ' ' < "$TMP/sweep.err" | tail -c 200)"

    python3 - "$TMP/sweep.json" > "$TMP/sweep.report" 2> "$TMP/sweep.pyerr" <<'PY'
import json, sys

def ok(msg):  sys.stdout.write("ok|%s\n" % msg)
def bad(msg): sys.stdout.write("fail|%s\n" % " ".join(str(msg).split()))
def check(cond, msg): ok(msg) if cond else bad(msg)

try:
    pages = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    bad("sweep output is not JSON: %s" % e)
    raise SystemExit(0)

check(isinstance(pages, list) and len(pages) == 3,
      "the sweep loads the page in three viewports (got %s)"
      % (len(pages) if isinstance(pages, list) else type(pages).__name__))

def ident(s):
    """tag#id, without the first class sel() appends."""
    return str(s or "").split(".")[0]

# Each entry: kind, selector, and whether the sweep must report it. The three
# it must NOT report are the measured false-positive classes; they are the
# reason the check has a first-line-box rule, a clip rule and a visible-part
# rule at all, and the reason they are pinned here rather than trusted.
EXPECT = [
    ("click-stolen",  "button#covered",  True),
    ("click-stolen",  "a#twoline",       False),
    ("click-stolen",  "a#skip",          False),
    ("click-stolen",  "a#clipped",       False),
    ("low-contrast",  "p#lowp",          True),
    ("low-contrast",  "p#bigp",          True),
    ("low-contrast",  "p#finep",         False),
    ("element-overflow", "div#escaping",   True),
    ("element-overflow", "div#inscroller", False),
]

for page in pages if isinstance(pages, list) else []:
    vp = page.get("viewport")
    findings = page.get("findings") or []
    broken = [f for f in findings if f.get("kind") in ("load-error", "sweep-error", "http-error")]
    check(not broken, "%spx: the fixture loaded and every check ran (%s)"
          % (vp, "; ".join(str(f)[:80] for f in broken)))
    seen = {}
    for f in findings:
        seen.setdefault(f.get("kind"), []).append(f)
    for kind, target, wanted in EXPECT:
        hits = [f for f in seen.get(kind, []) if ident(f.get("sel")) == target]
        if wanted:
            check(hits, "%spx: %s reported on %s" % (vp, kind, target))
        else:
            check(not hits, "%spx: %s NOT reported on %s (measured false positive)" % (vp, kind, target))
    # The receiver is the half of the finding that makes it actionable: "a click
    # is stolen" names nothing to go and delete.
    thief = [f for f in seen.get("click-stolen", []) if ident(f.get("sel")) == "button#covered"]
    check(thief and ident(thief[0].get("receiver")) == "div#thief",
          "%spx: the stolen click names its receiver div#thief (got %s)"
          % (vp, thief[0].get("receiver") if thief else "no finding"))
PY
    if [ -s "$TMP/sweep.pyerr" ]; then
      bad "sweep check crashed: $(tr '\n' ' ' < "$TMP/sweep.pyerr" | tail -c 300)"
    fi
    [ -s "$TMP/sweep.report" ] || bad "sweep check produced no assertions at all"
    while IFS= read -r line; do
      case "$line" in
        "ok|"*) ok ;;
        *)      bad "${line#fail|}" ;;
      esac
    done < "$TMP/sweep.report"
  fi

  # The runner's trap only removes TMP; a server left listening outlives the run.
  kill "$sw_pid" 2>/dev/null
  wait "$sw_pid" 2>/dev/null
fi
