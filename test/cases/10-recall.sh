# Keel self-tests — 10-recall. Sourced by test/run.sh; REPO/SK/HK/TMP and
# ok/bad/has/hasnt/section come from there.
recall() { CLAUDE_PROJECT_DIR="$1" bash "$SK/recall/anchors.sh" "${@:2}" 2>&1; }

section "recall — query & rot detection"
R="$TMP/recall"; mkdir -p "$R/memory/antipatterns" "$R/src"
cat > "$R/memory/antipatterns/proxy-trap.md" <<'NOTE'
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
NOTE
echo "export function handleRequest(){}" > "$R/src/proxy.ts"
printf '/**\n * docd does a thing\n */\nexport function docd(){}\n' > "$R/src/doc.ts"
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

section "recall — comment mention is not existence"
printf '// handleRequest was removed in v3\nexport function other(){}\n' > "$R/src/proxy.ts"
out="$(recall "$R" --check)"
has "DEAD_SYMBOL src/proxy.ts#handleRequest" "$out" "comment-only symbol → DEAD_SYMBOL"

section "recall — MENTIONED ranks by mentions, not lines"
M="$TMP/ment"; mkdir -p "$M/memory/lessons"
printf -- '---\nname: five\nkind: lesson\n---\nproxy.ts proxy.ts proxy.ts proxy.ts proxy.ts\n' > "$M/memory/lessons/five.md"
printf -- '---\nname: one\nkind: lesson\n---\nproxy.ts\n' > "$M/memory/lessons/one.md"
out="$(recall "$M" proxy.ts)"
has "5×" "$out" "note with five mentions counts 5"
five_line=$(printf '%s\n' "$out" | grep -n ' five$' | cut -d: -f1)
one_line=$(printf '%s\n' "$out" | grep -n ' one$' | cut -d: -f1)
if [ -n "$five_line" ] && [ -n "$one_line" ] && [ "$five_line" -lt "$one_line" ]; then ok; else bad "five ranks above one"; fi

section "recall — degenerate inputs do not crash"
E="$TMP/empty"; mkdir -p "$E/memory/lessons"; cp "$REPO/bundle/seed/MEMORY.md" "$E/memory/" 2>/dev/null || true
recall "$E" --check >/dev/null 2>&1 && ok || bad "empty memory --check exits 0"
recall "$E" --list  >/dev/null 2>&1 && ok || bad "empty memory --list exits 0"
printf -- '---\nname: bare\n---\nno code block here\n' > "$E/memory/lessons/bare.md"
recall "$E" --check >/dev/null 2>&1 && ok || bad "note without code: block --check exits 0"

section "recall — backfill resolves monorepo prefix, skips ambiguous/missing, idempotent"
B="$TMP/bf"; mkdir -p "$B/memory/lessons" "$B/app/apps/web" "$B/app/packages/api" "$B/app/packages/db/src"
echo "export function handleRequest(){}" > "$B/app/apps/web/proxy.ts"
echo x > "$B/app/packages/db/src/types.gen.ts"
echo a > "$B/app/apps/web/route.ts"; echo b > "$B/app/packages/api/route.ts"
cat > "$B/memory/lessons/n1.md" <<'NOTE'
---
name: n1
kind: antipattern
---
Bug in apps/web/proxy.ts, also types.gen.ts, some route.ts, and ghost.ts.
NOTE
out="$(recall "$B" --backfill)"
has "app/apps/web/proxy.ts" "$out" "backfill resolves app-relative path to real monorepo path"
has "1 anchored" "$out" "backfill dry-run counts anchored"
has "1 ambiguous" "$out" "route.ts (2 matches) is ambiguous"
has "1 unresolved" "$out" "ghost.ts is unresolved"
grep -q '^code:' "$B/memory/lessons/n1.md" && bad "dry run must not write" || ok
recall "$B" --backfill --apply >/dev/null 2>&1
grep -q 'app/apps/web/proxy.ts' "$B/memory/lessons/n1.md" && ok || bad "apply writes the anchor"
out="$(recall "$B" --check)"; has "0 dead" "$out" "backfilled anchors are all live"
out="$(recall "$B" --backfill)"; has "0 anchored" "$out" "second backfill is idempotent"
