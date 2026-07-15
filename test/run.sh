#!/usr/bin/env bash
# Kernel self-tests: exercise the shipped scripts against throwaway fixtures.
#
#   bash test/run.sh
#
# Every case here encodes a bug that actually shipped and was caught by hand, or
# a property the docs promise. A green build is not a release gate; this is. Runs
# offline, in temp dirs, touches nothing outside them. Non-zero exit on any fail.
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

recall() { CLAUDE_PROJECT_DIR="$1" bash "$SK/recall/anchors.sh" "${@:2}" 2>&1; }
graph()  { CLAUDE_PROJECT_DIR="$1" bash "$SK/memory-consolidation/graph.sh" "${@:2}" 2>&1; }

# ── recall: query, --check rot detection ────────────────────────────────────
section "recall — query & rot detection"
R="$TMP/recall"; mkdir -p "$R/memory/antipatterns" "$R/src"
# filename == slug == name, per the remember convention.
cat > "$R/memory/antipatterns/proxy-trap.md" <<'EOF'
---
name: proxy-trap
description: Host routing broke internal callers
kind: antipattern
code:
  - src/proxy.ts#handleRequest
  - src/gone.ts
  - src/doc.ts#docd
---
Trap.
EOF
echo "export function handleRequest(){}" > "$R/src/proxy.ts"
printf '/**\n * docd does a thing\n */\nexport function docd(){}\n' > "$R/src/doc.ts"  # symbol only in def
# src/gone.ts absent → DEAD_FILE
out="$(recall "$R" src/proxy.ts)"
has "ANCHORED" "$out" "query surfaces ANCHORED section"
has "proxy-trap" "$out" "query by path finds the note"
out="$(recall "$R" handleRequest)"
has "proxy-trap" "$out" "query by symbol finds the note"
out="$(recall "$R" --check)"
has "DEAD_FILE   src/gone.ts" "$out" "deleted file → DEAD_FILE"
hasnt "DEAD_SYMBOL src/proxy.ts#handleRequest" "$out" "live symbol not flagged"
hasnt "DEAD_SYMBOL src/doc.ts#docd" "$out" "symbol defined under JSDoc stays alive"

# THE regression: suffix rename must be caught (grep -F substring bug)
section "recall — suffix rename is caught (handleRequest → handleRequestV2)"
sed -i.bak 's/handleRequest/handleRequestV2/' "$R/src/proxy.ts"; rm -f "$R/src/proxy.ts.bak"
out="$(recall "$R" --check)"
has "DEAD_SYMBOL src/proxy.ts#handleRequest" "$out" "suffix rename → DEAD_SYMBOL"

# comment tombstone: symbol surviving only in a comment does not exist
section "recall — comment mention is not existence"
printf '// handleRequest was removed in v3\nexport function other(){}\n' > "$R/src/proxy.ts"
out="$(recall "$R" --check)"
has "DEAD_SYMBOL src/proxy.ts#handleRequest" "$out" "comment-only symbol → DEAD_SYMBOL"

# ── recall: MENTIONED ranks by mention count, not matching lines ─────────────
section "recall — MENTIONED ranks by mentions, not lines"
M="$TMP/ment"; mkdir -p "$M/memory/lessons"
printf -- '---\nname: five\nkind: lesson\n---\nproxy.ts proxy.ts proxy.ts proxy.ts proxy.ts\n' > "$M/memory/lessons/five.md"
printf -- '---\nname: one\nkind: lesson\n---\nproxy.ts\n' > "$M/memory/lessons/one.md"
out="$(recall "$M" proxy.ts)"
has "5×" "$out" "note with five mentions counts 5"
# five must appear before one
five_line=$(printf '%s\n' "$out" | grep -n ' five$' | cut -d: -f1)
one_line=$(printf '%s\n' "$out" | grep -n ' one$' | cut -d: -f1)
if [ -n "$five_line" ] && [ -n "$one_line" ] && [ "$five_line" -lt "$one_line" ]; then ok; else bad "five ranks above one"; fi

# ── recall: no-crash edges ──────────────────────────────────────────────────
section "recall — degenerate inputs do not crash"
E="$TMP/empty"; mkdir -p "$E/memory/lessons"; cp "$REPO/bundle/seed/MEMORY.md" "$E/memory/" 2>/dev/null || true
recall "$E" --check >/dev/null 2>&1 && ok || bad "empty memory --check exits 0"
recall "$E" --list  >/dev/null 2>&1 && ok || bad "empty memory --list exits 0"
printf -- '---\nname: bare\n---\nno code block here\n' > "$E/memory/lessons/bare.md"
recall "$E" --check >/dev/null 2>&1 && ok || bad "note without code: block --check exits 0"

# ── recall: --backfill ──────────────────────────────────────────────────────
section "recall — backfill resolves monorepo prefix, skips ambiguous/missing, idempotent"
B="$TMP/bf"; mkdir -p "$B/memory/lessons" "$B/app/apps/web" "$B/app/packages/api" "$B/app/packages/db/src"
echo "export function handleRequest(){}" > "$B/app/apps/web/proxy.ts"
echo x > "$B/app/packages/db/src/types.gen.ts"
echo a > "$B/app/apps/web/route.ts"; echo b > "$B/app/packages/api/route.ts"   # route.ts ambiguous
cat > "$B/memory/lessons/n1.md" <<'EOF'
---
name: n1
kind: antipattern
---
Bug in apps/web/proxy.ts, also types.gen.ts, some route.ts, and ghost.ts.
EOF
out="$(recall "$B" --backfill)"                         # dry run
has "app/apps/web/proxy.ts" "$out" "backfill resolves app-relative path to real monorepo path"
has "1 anchored" "$out" "backfill dry-run counts anchored"
has "1 ambiguous" "$out" "route.ts (2 matches) is ambiguous"
has "1 unresolved" "$out" "ghost.ts is unresolved"
grep -q '^code:' "$B/memory/lessons/n1.md" && bad "dry run must not write" || ok
recall "$B" --backfill --apply >/dev/null 2>&1
grep -q 'app/apps/web/proxy.ts' "$B/memory/lessons/n1.md" && ok || bad "apply writes the anchor"
out="$(recall "$B" --check)"; has "0 dead" "$out" "backfilled anchors are all live"
out="$(recall "$B" --backfill)"; has "0 anchored" "$out" "second backfill is idempotent"

# ── graph.sh ────────────────────────────────────────────────────────────────
section "graph — edges, code-fence exclusion, empty"
G="$TMP/graph"; mkdir -p "$G/memory/lessons"
printf -- '---\nname: a\n---\nSee [[b]].\n\n```sh\ngrep "[[:space:]]" f  # not an edge\n```\nAnd `[[inline]]` prose.\n' > "$G/memory/lessons/a.md"
printf -- '---\nname: b\n---\nBack to [[a]].\n' > "$G/memory/lessons/b.md"
out="$(graph "$G" --edges)"
has "a	b" "$out" "real [[b]] edge extracted"
hasnt ":space:" "$out" "POSIX class in a code fence is not an edge"
hasnt "inline" "$out" "inline-code [[x]] is not an edge"
out="$(graph "$G")"; has "2 notes · 2 edges" "$out" "totals correct"
out="$(graph "$E")"; has "none yet" "$out" "empty memory says none yet, no phantom hub"

# ── migrate sweep ───────────────────────────────────────────────────────────
section "migrate — machinery quarantined, state preserved, re-audit filed"
S="$TMP/sf"; mkdir -p "$S/skillforge" "$S/memory/lessons" "$S/.claude/skills/_user/mine" "$S/stages"
echo bundle > "$S/skillforge/x"; echo lesson > "$S/memory/lessons/keep.md"
echo mine > "$S/.claude/skills/_user/mine/SKILL.md"; : > "$S/BACKLOG.md"
out="$(cd "$S" && CLAUDE_PROJECT_DIR="$S" bash "$SK/migrate/sweep.sh" 2>&1)"
has "MACHINERY" "$out" "sweep detects the skillforge bundle as machinery"
cd "$S" && CLAUDE_PROJECT_DIR="$S" bash "$SK/migrate/sweep.sh" --apply >/dev/null 2>&1; cd - >/dev/null
[ ! -d "$S/skillforge" ] && ok || bad "machinery moved out of project root"
[ -n "$(find "$S/.keel-migration" -name x 2>/dev/null)" ] && ok || bad "machinery lands in quarantine"
[ -f "$S/memory/lessons/keep.md" ] && ok || bad "memory note preserved"
[ -f "$S/.claude/skills/_user/mine/SKILL.md" ] && ok || bad "_user skill preserved"
grep -q 'src:migrate' "$S/BACKLOG.md" && ok || bad "re-audit filed into BACKLOG.md"

# flagged-only (a .claude.bak) is NOT machinery
F="$TMP/flag"; mkdir -p "$F/memory" "$F/.claude.bak.20260101000000"
out="$(cd "$F" && CLAUDE_PROJECT_DIR="$F" bash "$SK/migrate/sweep.sh" 2>&1)"
hasnt "MACHINERY" "$out" "a lone .claude.bak is flagged, not machinery"

# ── update-check ────────────────────────────────────────────────────────────
section "update-check — speaks only when strictly newer, silent otherwise"
U="$TMP/upd"; mkdir -p "$U/.claude" "$U/cache/keel"
cp "$REPO/bundle/seed/keel.json" "$U/keel.json"
printf '%s\n1.9.9\n' "9999999999" > "$U/cache/keel/latest-bogdanov-igor-keel"   # fresh cache, no network
uc() { echo "$1" > "$U/.claude/VERSION"; CLAUDE_PROJECT_DIR="$U" XDG_CACHE_HOME="$U/cache" bash "$HK/update-check.sh" 2>&1; }
has    "1.9.9 is available" "$(uc 1.0.0)" "older local → announces"
hasnt  "available"          "$(uc 1.9.9)" "current local → silent"
hasnt  "available"          "$(uc 2.0.0)" "local ahead of release → silent"
python3 - "$U/keel.json" <<'PY' 2>/dev/null || sed -i.bak 's/"enabled": true/"enabled": false/' "$U/keel.json"
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["update_check"]["enabled"]=False; json.dump(d,open(p,"w"))
PY
hasnt  "available"          "$(uc 1.0.0)" "opt-out → silent"

# ── report ──────────────────────────────────────────────────────────────────
printf '\n─────────────\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
