#!/usr/bin/env bash
# The memory graph, from the notes themselves. No index, no daemon, no build.
#
#   bash graph.sh            # hubs · orphans · dead links · totals
#   bash graph.sh --edges    # the raw adjacency list (src -> dst), one per line
#
# The edges ARE the [[wikilinks]] in memory/*.md. That is the whole data model:
# the predecessor's PageRank read the same links out of the same files, then
# scored them. Scoring is gone; the graph is not. What is left is what a human
# and a model actually use — who is central, who is unreachable, what is broken.
#
# For the picture, open memory/ in Obsidian or VS Code Foam: markdown with
# [[wikilinks]] IS their native graph format. Zero dependencies to add.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MEM="$ROOT/memory"
[ -d "$MEM" ] || { echo "memory-graph: no memory/ at $ROOT" >&2; exit 1; }

# slug = filename without .md — the same key [[wikilinks]] address notes by.
#
# Prose about wikilinks is not a wikilink. A note explaining the convention
# writes `[[slug]]` in backticks, and a shell snippet contains [[:space:]] —
# counting those as edges invents dead links and sends someone chasing ghosts.
# So: drop fenced code blocks, drop inline code spans, drop POSIX classes.
edges() {
  find "$MEM" -name '*.md' ! -name 'MEMORY.md' | while read -r f; do
    src="$(basename "$f" .md)"
    awk '/^[[:space:]]*```/ { fence = !fence; next } !fence' "$f" 2>/dev/null \
      | sed 's/`[^`]*`//g' \
      | grep -oE '\[\[[^]]+\]\]' | tr -d '[]' | while read -r dst; do
        dst="${dst%%|*}"                       # [[slug|alias]] → slug
        case "$dst" in ''|:*) continue ;; esac # [[:space:]] & friends
        printf '%s\t%s\n' "$src" "$dst"
      done
  done
}

if [ "${1:-}" = "--edges" ]; then
  edges | sort
  exit 0
fi

E="$(edges)"
notes="$(find "$MEM" -name '*.md' ! -name 'MEMORY.md' -exec basename {} .md \; | sort -u)"
n_notes="$(printf '%s\n' "$notes" | grep -c . || true)"
n_edges="$(printf '%s\n' "$E" | grep -c . || true)"

echo "memory graph: $n_notes notes · $n_edges edges"
echo

echo "HUBS (most-cited notes — what the memory keeps coming back to):"
if [ "$n_edges" -eq 0 ]; then
  echo "  none yet — no [[wikilinks]] in memory/"
else
  printf '%s\n' "$E" | cut -f2 | grep -v '^$' | sort | uniq -c | sort -rn | head -10 \
    | awk '{ printf "  %3d ← %s\n", $1, $2 }'
fi
echo

echo "DEAD LINKS ([[targets]] with no note behind them — silently break recall):"
dead=0
printf '%s\n' "$E" | cut -f2 | sort -u | while read -r t; do
  [ -n "$t" ] || continue
  if ! printf '%s\n' "$notes" | grep -qxF "$t"; then
    printf '  %s ← cited by: %s\n' "$t" \
      "$(printf '%s\n' "$E" | awk -F'\t' -v t="$t" '$2==t{printf "%s ", $1}')"
    dead=1
  fi
done
[ "$(printf '%s\n' "$E" | cut -f2 | sort -u | while read -r t; do
      [ -n "$t" ] && ! printf '%s\n' "$notes" | grep -qxF "$t" && echo x; done | grep -c x || true)" -eq 0 ] \
  && echo "  none ✓"
echo

echo "ORPHANS (no link in, no link out — unreachable by traversal):"
linked="$(printf '%s\n' "$E" | cut -f1,2 | tr '\t' '\n' | sort -u)"
orph=0
printf '%s\n' "$notes" | while read -r s; do
  [ -n "$s" ] || continue
  printf '%s\n' "$linked" | grep -qxF "$s" || { echo "  $s"; orph=1; }
done
[ "$(printf '%s\n' "$notes" | while read -r s; do
      [ -n "$s" ] && ! printf '%s\n' "$linked" | grep -qxF "$s" && echo x; done | grep -c x || true)" -eq 0 ] \
  && echo "  none ✓"
